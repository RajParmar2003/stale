// =====================================================================
//  Stale.app — native macOS shell around the Stale web UI.
//
//  What the native layer adds that a browser cannot:
//    • Reads installed apps directly (runs `system_profiler`) — no Terminal step.
//    • Lives in the menu bar; window toggles from there or the Dock.
//    • Posts a notification when apps have gone stale.
//    • Optional launch-at-login.
//
//  The UI itself is the EXACT same web app in ../stale, bundled into the .app
//  and served to a WKWebView over a custom `stale://` scheme. Same engine as the
//  Local/Web entities; this is just the "App" entity.
// =====================================================================

import AppKit
import WebKit
import UserNotifications
import ServiceManagement

// MARK: - Custom scheme handler (serves bundled web assets to the WKWebView)

/// Serves files from Resources/web over stale://app/<path>. Using a custom scheme
/// (rather than file://) gives the page a stable, secure origin so IndexedDB,
/// service workers, and fetch() all behave like a normal website.
final class WebAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let fileURL = root.appendingPathComponent(path)

        guard let data = try? Data(contentsOf: fileURL) else {
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(resp); task.didFinish(); return
        }
        let headers = [
            "Content-Type": Self.mime(for: fileURL.pathExtension),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js":   return "text/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json; charset=utf-8"
        case "svg":  return "image/svg+xml"
        case "png":  return "image/png"
        case "ico":  return "image/x-icon"
        case "woff2": return "font/woff2"
        default:     return "application/octet-stream"
        }
    }
}

/// Serves real app icons over stale-icon://icon?path=<app path>. The web layer uses these
/// as <img> sources, so each visible row shows its genuine logo. Icons are rendered to PNG
/// on demand and cached in-process.
///
/// Security: we serve an icon only for an existing `.app` **bundle** (a directory whose name
/// ends in .app) with no `..` traversal in the path. That covers apps wherever they actually
/// live — /Applications, ~/Applications, ~/Downloads, ~/Desktop, etc. — while refusing to read
/// arbitrary files (e.g. /etc/passwd) as images.
final class IconSchemeHandler: NSObject, WKURLSchemeHandler {
    private var cache = [String: Data]()

    private func isAllowed(_ path: String) -> Bool {
        guard !path.contains(".."), path.lowercased().hasSuffix(".app") else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "path" })?.value
        else { fail(task); return }

        let png = iconPNG(for: path)
        guard let data = png else { fail(task); return }
        let headers = ["Content-Type": "image/png", "Cache-Control": "max-age=86400",
                       "Access-Control-Allow-Origin": "*"]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        task.didReceive(resp); task.didFinish()
    }

    private func iconPNG(for appPath: String) -> Data? {
        if let hit = cache[appPath] { return hit }
        guard isAllowed(appPath) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: appPath)
        let side: CGFloat = 64
        let target = NSSize(width: side, height: side)
        let resized = NSImage(size: target)
        resized.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: target),
                 from: NSRect(origin: .zero, size: img.size),
                 operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        cache[appPath] = png
        return png
    }
}

// MARK: - App scanning (the thing the browser can't do)

enum Scanner {
    /// Runs `system_profiler SPApplicationsDataType -json`, then augments each app entry
    /// with its CFBundleIdentifier (read from the bundle's Info.plist) so the web layer
    /// can look apps up precisely on the App Store. Returns the augmented JSON string.
    static func scan() -> Result<String, Error> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPApplicationsDataType", "-json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            // Read before waitUntilExit to avoid deadlock on large output.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                return .failure(NSError(domain: "Stale", code: Int(proc.terminationStatus),
                                        userInfo: [NSLocalizedDescriptionKey: "system_profiler failed"]))
            }
            let augmented = augmentBundleIds(data) ?? data
            guard let s = String(data: augmented, encoding: .utf8) else {
                return .failure(NSError(domain: "Stale", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "encode failed"]))
            }
            return .success(s)
        } catch { return .failure(error) }
    }

    /// Inject "bundle_id" into each app dict by reading <path>/Contents/Info.plist.
    /// Returns nil on any parse problem (caller falls back to the raw JSON).
    private static func augmentBundleIds(_ data: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var apps = root["SPApplicationsDataType"] as? [[String: Any]] else { return nil }
        for i in apps.indices {
            guard let path = apps[i]["path"] as? String else { continue }
            let plist = path + "/Contents/Info.plist"
            if let dict = NSDictionary(contentsOfFile: plist),
               let bid = dict["CFBundleIdentifier"] as? String {
                apps[i]["bundle_id"] = bid
            }
        }
        root["SPApplicationsDataType"] = apps
        return try? JSONSerialization.data(withJSONObject: root)
    }
}

// MARK: - Homebrew updater (one-click, hidden background process)

enum Brew {
    /// Locate the brew binary (Apple Silicon first, then Intel). nil if Homebrew isn't installed.
    static func path() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    /// A cask token is safe to pass as an argument: Homebrew tokens are [a-z0-9-@._] only.
    static func isValidToken(_ t: String) -> Bool {
        !t.isEmpty && t.range(of: "^[a-z0-9][a-z0-9@._-]*$", options: .regularExpression) != nil
    }
}

/// Runs Homebrew in a hidden process, streaming output lines to a callback. Tries
/// `upgrade --cask <token>` first; if the cask isn't brew-managed yet, falls back to
/// `install --cask <token>` (which adopts/installs the latest). Nothing is shown in a
/// Terminal window — progress is surfaced inside the app instead.
final class CaskUpgrade {

    func run(token: String,
             onLine: @escaping (String) -> Void,
             onDone: @escaping (_ ok: Bool) -> Void) {
        guard Brew.path() != nil, Brew.isValidToken(token) else { onDone(false); return }
        runBrew(["upgrade", "--cask", token], onLine: onLine) { ok in
            if ok { onDone(true); return }
            // Upgrade can fail simply because the cask isn't installed via brew. Adopt it.
            onLine("· not brew-managed yet — installing latest…")
            self.runBrew(["install", "--cask", "--adopt", token], onLine: onLine, onDone: onDone)
        }
    }

    private func runBrew(_ args: [String],
                         onLine: @escaping (String) -> Void,
                         onDone: @escaping (_ ok: Bool) -> Void) {
        guard let brew = Brew.path() else { onDone(false); return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"          // faster, predictable
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
                DispatchQueue.main.async { onLine(String(line)) }
            }
        }
        proc.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { onDone(p.terminationStatus == 0) }
        }
        do { try proc.run() } catch { onDone(false) }
    }
}

// MARK: - Main controller

final class AppController: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)             // Dock icon + menu bar
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        setupMenuBar()
        setupWindow()
        showWindow()
    }

    // ----- Web view -----
    private func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let web = webRoot()
        cfg.setURLSchemeHandler(WebAssetSchemeHandler(root: web), forURLScheme: "stale")
        cfg.setURLSchemeHandler(IconSchemeHandler(), forURLScheme: "stale-icon")  // real app logos
        cfg.userContentController.add(self, name: "staleScan")        // JS → Swift bridge
        cfg.userContentController.add(self, name: "staleUpdate")      // one-click brew upgrade
        cfg.userContentController.add(self, name: "staleBrewCheck")   // is Homebrew available?
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        if #available(macOS 13.3, *) { wv.isInspectable = true }       // right-click → Inspect in dev
        return wv
    }

    private func webRoot() -> URL {
        // Resources/web inside the bundle; fall back to a sibling ../stale during dev.
        if let r = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("index.html").path) {
            return r
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("..")
    }

    private func setupWindow() {
        webView = makeWebView()
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 820),
                          styleMask: style, backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Stale"
        window.center()
        window.setFrameAutosaveName("StaleMainWindow")
        window.contentView = webView
        window.isReleasedWhenClosed = false
        webView.load(URLRequest(url: URL(string: "stale://app/index.html")!))
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ----- Menu bar -----
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Use a native SF Symbol (template image, tracks the menu-bar appearance) — not an emoji.
        if let btn = statusItem.button {
            if let img = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Stale") {
                img.isTemplate = true
                btn.image = img
            } else {
                btn.title = "Stale"      // fallback on older systems
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Stale", action: #selector(openFromMenu), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Scan Now", action: #selector(scanFromMenu), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stale", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openFromMenu() { showWindow() }
    @objc private func scanFromMenu() {
        showWindow()
        webView.evaluateJavaScript("window.__staleRequestScan && window.__staleRequestScan()", completionHandler: nil)
    }

    // ----- Launch at login (SMAppService, macOS 13+) -----
    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister(); sender.state = .off }
            else { try SMAppService.mainApp.register(); sender.state = .on }
        } catch { NSSound.beep() }
    }

    // hold strong refs to in-flight upgrades, keyed by row key, so they aren't deallocated
    private var upgrades = [String: CaskUpgrade]()

    // ----- JS → Swift bridge -----
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "staleScan":      handleScan()
        case "staleBrewCheck": handleBrewCheck()
        case "staleUpdate":    handleUpdate(message.body)
        default: break
        }
    }

    private func handleScan() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Scanner.scan()
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    // base64 so we never have to escape the (large) JSON payload into JS source.
                    let b64 = Data(json.utf8).base64EncodedString()
                    self.webView.evaluateJavaScript("window.__staleReceiveScan(atob(\"\(b64)\"))", completionHandler: nil)
                case .failure:
                    self.webView.evaluateJavaScript("window.toast && window.toast('Could not read your apps.')", completionHandler: nil)
                }
            }
        }
    }

    private func handleBrewCheck() {
        let available = Brew.path() != nil
        webView.evaluateJavaScript("window.__staleBrewAvailable && window.__staleBrewAvailable(\(available))", completionHandler: nil)
    }

    private func handleUpdate(_ body: Any) {
        guard let dict = body as? [String: Any],
              let token = dict["token"] as? String,
              let key = dict["key"] as? String,
              Brew.isValidToken(token) else { return }

        let jsKey = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let upgrade = CaskUpgrade()
        upgrades[key] = upgrade
        upgrade.run(token: token,
            onLine: { [weak self] line in
                let safe = line.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                self?.webView.evaluateJavaScript("window.__staleUpdateProgress && window.__staleUpdateProgress('\(jsKey)','\(safe)')", completionHandler: nil)
            },
            onDone: { [weak self] ok in
                self?.upgrades[key] = nil
                self?.webView.evaluateJavaScript("window.__staleUpdateDone && window.__staleUpdateDone('\(jsKey)',\(ok))", completionHandler: nil)
            })
    }

    // ----- Notify when apps are stale (page calls staleNotify via a second handler if wired) -----
    func notifyStale(count: Int) {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Stale"
        content.body = count == 1 ? "1 app has gone stale." : "\(count) apps have gone stale."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "stale-\(Date().timeIntervalSince1970)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Keep app alive when window closes (menu bar app); reopen on Dock click.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }; return true
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
