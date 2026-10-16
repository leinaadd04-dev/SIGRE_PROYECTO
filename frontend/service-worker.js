/* SIGRE · Service worker (permite instalar SIGRE como app en el celular)
   - Páginas, estilos, scripts e imágenes: primero se piden a internet (siempre
     la versión más nueva) y se guarda una copia; sin conexión se usa la copia.
   - La API (/api/...) nunca se guarda: lleva datos personales.
   - Notificaciones push: las muestra aunque SIGRE esté cerrada y, al tocarlas,
     abre la página que corresponde (backend/push.py las envía). */
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

/* ---------- Notificaciones push ---------- */

self.addEventListener("push", evento => {
    let aviso = {};
    try {
        aviso = evento.data ? evento.data.json() : {};
    } catch (error) {
        aviso = { mensaje: evento.data ? evento.data.text() : "" };
    }
    evento.waitUntil(self.registration.showNotification(aviso.titulo || "SIGRE", {
        body: aviso.mensaje || "Tienes una notificación nueva.",
        icon: "imagenes/iconos/icono-192.png",
        badge: "imagenes/iconos/icono-192.png",
        tag: aviso.etiqueta,            // la misma notificación no se repite
        data: { enlace: aviso.enlace || "dashboard.html" },
        // Las emergencias se quedan en pantalla hasta que la persona las toque.
        requireInteraction: aviso.tipo === "emergencia",
        vibrate: aviso.tipo === "emergencia" ? [300, 150, 300, 150, 300] : [150]
    }));
});

self.addEventListener("notificationclick", evento => {
    evento.notification.close();
    const destino = new URL(evento.notification.data.enlace || "dashboard.html", self.registration.scope).href;
    evento.waitUntil(
        self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(ventanas => {
            // Si SIGRE ya está abierta, se usa esa ventana; si no, se abre una.
            const abierta = ventanas.find(ventana => ventana.url.startsWith(self.registration.scope));
            if (abierta) return abierta.navigate(destino).then(ventana => (ventana || abierta).focus());
            return self.clients.openWindow(destino);
        })
    );
});
