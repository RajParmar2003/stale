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
const CACHE = "stale-shell-" + BUILD + "-v1";
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

  // Let the Homebrew API go straight to the network (app handles offline via IndexedDB).
  if (url.hostname.endsWith("formulae.brew.sh")) return;

  // App shell: cache-first, with a background refresh for same-origin assets.
  event.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req)
        .then((res) => {
          if (res && res.ok && url.origin === self.location.origin) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
          }
          return res;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
