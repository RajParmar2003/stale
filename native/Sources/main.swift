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
        default:     return "application/octet-stream"
        }
    }
}

// MARK: - App scanning (the thing the browser can't do)

enum Scanner {
    /// Runs `system_profiler SPApplicationsDataType -json` and returns the raw JSON string.
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
            guard proc.terminationStatus == 0, let s = String(data: data, encoding: .utf8) else {
                return .failure(NSError(domain: "Stale", code: Int(proc.terminationStatus),
                                        userInfo: [NSLocalizedDescriptionKey: "system_profiler failed"]))
            }
            return .success(s)
        } catch { return .failure(error) }
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
        cfg.userContentController.add(self, name: "staleScan")        // JS → Swift bridge
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
        statusItem.button?.title = "🍂"
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

    // ----- JS → Swift bridge: run the scan, hand JSON back to the page -----
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "staleScan" else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Scanner.scan()
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    // base64 so we never have to escape the (large) JSON payload into JS source.
                    let b64 = Data(json.utf8).base64EncodedString()
                    let js = "window.__staleReceiveScan(atob(\"\(b64)\"))"
                    self.webView.evaluateJavaScript(js, completionHandler: nil)
                case .failure:
                    self.webView.evaluateJavaScript(
                        "window.toast && window.toast('Could not read your apps.')", completionHandler: nil)
                }
            }
        }
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
