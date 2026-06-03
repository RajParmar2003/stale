/* =====================================================================
   Stale service worker — offline app shell.
   - Caches the app shell so Stale opens instantly and works offline once
     installed to the Dock.
   - Does NOT cache the Homebrew API (15 MB): that is handled by the app's
     IndexedDB cache, which keeps a parsed, query-ready copy with a TTL.
   - Bump CACHE on any shell change to invalidate old caches.
   ===================================================================== */
/* Namespace the cache per entity so the LOCAL instance and the WEB instance keep
   independent offline shells, even in the unlikely case they share an origin. */
const BUILD = (self.location.hostname === "localhost" || self.location.hostname === "127.0.0.1" || self.location.hostname === "[::1]")
  ? "local" : "web";
const CACHE = "stale-shell-" + BUILD + "-v2";
const SHELL = [
  "./",
  "./index.html",
  "./assets/css/styles.css",
  "./assets/js/app.js",
  "./manifest.webmanifest",
  "./assets/icons/favicon.svg",
  "./assets/icons/icon-192.png",
  "./assets/icons/icon-512.png",
  "./assets/icons/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // resilient: don't fail the whole install if one asset is missing
      Promise.allSettled(SHELL.map((url) => cache.add(url)))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // Only handle our own origin. External hosts (Homebrew API, iTunes API, App Store
  // artwork) go straight to the network so we never serve stale data or cache 15 MB.
  if (url.origin !== self.location.origin) return;

  // Code (HTML/JS/CSS) → network-first: always get the latest, fall back to cache offline.
  // This prevents the classic "stale JS after an update" bug.
  const isCode = /\.(html|js|css)$/.test(url.pathname) || url.pathname === "/" || url.pathname.endsWith("/");
  if (isCode) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
          return res;
        })
        .catch(() => caches.match(req))
    );
    return;
  }

  // Everything else (icons, fonts, manifest) → cache-first for speed, refresh in background.
  event.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req)
        .then((res) => {
          if (res && res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
          return res;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
