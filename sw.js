// Offline support for the home-screen install.
// The page itself is network-first (so updates show up right away when online); images are cache-first.
// Bump VERSION when assets change so old caches are dropped.
const VERSION = 'rlyeh-v5';
self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(['./', 'index.html', 'manifest.webmanifest'])).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const page = e.request.mode === 'navigate' || /\/(index\.html)?$/.test(new URL(e.request.url).pathname);
  e.respondWith(caches.open(VERSION).then(async c => {
    const hit = await c.match(e.request);
    const net = fetch(e.request, page ? { cache: 'no-cache' } : undefined)
      .then(r => { if (r.ok) c.put(e.request, r.clone()); return r; }).catch(() => hit);
    return page ? net.then(r => r || hit) : (hit || net);
  }));
});
