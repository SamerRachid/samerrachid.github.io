/* Balkoun service worker.
   Pages: network first, so a published change is seen on the next open; the last good copy of the
   app shell answers when the network is down. Static files (brand, photos, fonts): cache first with a
   background refresh. Database calls are never cached. The version below changes whenever this file
   changes, which retires old caches. */
const VERSION = "bk-2026-09-08a";
const SHELL = VERSION + "-shell";
const STATIC = VERSION + "-static";
const PHOTOS = VERSION + "-photos";
const SHELL_URLS = ["/", "/index.html", "/manifest.webmanifest", "/brand/icon-192.png", "/brand/icon-512.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(SHELL_URLS).catch(() => null)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => !k.startsWith(VERSION)).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

const isNav = (req) => req.mode === "navigate" || (req.headers.get("accept") || "").includes("text/html");
const sameOrigin = (url) => url.origin === self.location.origin;
const isPhoto = (url) => /supabase\.co\/storage\//.test(url.href) || /\.(jpe?g|png|webp|gif)$/i.test(url.pathname);
const isStatic = (url) => sameOrigin(url) && (/^\/(brand|assets)\//.test(url.pathname) || /\.(css|js|svg|woff2?)$/i.test(url.pathname) && url.pathname !== "/sw.js");
const isFont = (url) => /fonts\.(googleapis|gstatic)\.com$/.test(url.hostname);
const isApi = (url) => /supabase\.co$/.test(url.hostname) && !/\/storage\//.test(url.pathname);

async function networkFirstPage(req) {
  try {
    const res = await fetch(req);
    if (res && res.ok) { const c = await caches.open(SHELL); c.put("/index.html", res.clone()); }
    return res;
  } catch (e) {
    const c = await caches.open(SHELL);
    return (await c.match("/index.html")) || (await c.match("/")) || Response.error();
  }
}
async function staleWhileRevalidate(req, cacheName, maxEntries) {
  const c = await caches.open(cacheName);
  const hit = await c.match(req);
  const refresh = fetch(req).then((res) => { if (res && (res.ok || res.type === "opaque")) { c.put(req, res.clone()); if (maxEntries) trim(c, maxEntries); } return res; }).catch(() => null);
  return hit || (await refresh) || Response.error();
}
async function trim(c, max) { const keys = await c.keys(); if (keys.length > max) await c.delete(keys[0]); }

self.addEventListener("fetch", (e) => {
  const req = e.request; if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (isApi(url)) return;                                   // live data, always from the network
  if (isNav(req) && sameOrigin(url)) { e.respondWith(networkFirstPage(req)); return; }
  if (isStatic(url) || isFont(url)) { e.respondWith(staleWhileRevalidate(req, STATIC, 200)); return; }
  if (isPhoto(url)) { e.respondWith(staleWhileRevalidate(req, PHOTOS, 300)); return; }
});

self.addEventListener("message", (e) => { if (e.data === "skipWaiting") self.skipWaiting(); });
