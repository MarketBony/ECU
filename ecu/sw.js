/* ECU — service worker.
 * Tout est servi depuis le cache : l'application fonctionne hors-ligne, et le
 * réseau n'est sollicité que pour rafraîchir data.json en arrière-plan.
 */
const CACHE = 'ecu-v3';
const COQUILLE = [
  './',
  './index.html',
  './ecu.js',
  './data.json',
  './logo.svg',
  './logo-maskable.svg',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-512.png',
  './apple-touch-icon.png',
  './vendor/three.module.min.js',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(COQUILLE))
      .then(() => self.skipWaiting())
      .catch(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  // data.json : le réseau d'abord, pour repartir sur un graphe à jour après un
  // commit ; le cache prend le relais hors-ligne.
  if (new URL(req.url).pathname.endsWith('/data.json')) {
    e.respondWith(
      fetch(req)
        .then(r => { const c = r.clone(); caches.open(CACHE).then(k => k.put(req, c)); return r; })
        .catch(() => caches.match(req)),
    );
    return;
  }

  // le reste : cache d'abord, c'est figé entre deux versions
  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(r => {
      if (r.ok && new URL(req.url).origin === location.origin) {
        const c = r.clone(); caches.open(CACHE).then(k => k.put(req, c));
      }
      return r;
    })),
  );
});
