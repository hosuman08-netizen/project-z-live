const SHELL = "z-shell-v1";
const PRECACHE = ["/", "/app/", "/app/index.html", "/manifest.webmanifest", "/assets/favicon.svg"];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(SHELL)
      .then((c) => c.addAll(PRECACHE))
      .then(() => self.skipWaiting())
      .catch(() => {})
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== SHELL).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const u = new URL(e.request.url);
  if (u.origin !== self.location.origin) return;
  if (u.pathname.startsWith("/api/")) return;
  if (e.request.method !== "GET") return;
  if (e.request.mode === "navigate") {
    e.respondWith(
      fetch(e.request).catch(() => caches.match("/app/index.html").then((r) => r || caches.match("/")))
    );
  }
});
