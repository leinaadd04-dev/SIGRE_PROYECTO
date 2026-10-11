
const CACHE = "sigre-v1";

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", evento => {
    // Borra las copias de versiones anteriores.
    evento.waitUntil(
        caches.keys()
            .then(claves => Promise.all(claves.filter(clave => clave !== CACHE).map(clave => caches.delete(clave))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener("fetch", evento => {
    const peticion = evento.request;
    const url = new URL(peticion.url);
    if (peticion.method !== "GET" || url.origin !== self.location.origin || url.pathname.startsWith("/api/")) {
        return;   // lo maneja el navegador normalmente
    }
    evento.respondWith(
        fetch(peticion)
            .then(respuesta => {
                if (respuesta.ok) {
                    const copia = respuesta.clone();
                    caches.open(CACHE).then(cache => cache.put(peticion, copia));
                }
                return respuesta;
            })
            .catch(() => caches.match(peticion).then(copia => copia || Response.error()))
    );
});
