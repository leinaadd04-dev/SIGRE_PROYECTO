/* SIGRE · Notificaciones push (llegan al celular aunque la app esté cerrada)
   - Agrega al menú ☰ "Activar notificaciones en este dispositivo".
   - Al activarlas, el navegador pide permiso y entrega una dirección de push
     que se guarda en el servidor (POST /api/push/suscribir).
   - Al cerrar sesión se desactivan en este dispositivo, para que la próxima
     persona que use el celular no reciba los avisos de la cuenta anterior.
   Expone window.SigrePush.desactivar(). */
(() => {
    const API = window.SIGRE_API;
    const enlacesMenu = document.querySelector(".cuenta_menu_enlaces");

    function leerToken() {
        try {
            return localStorage.getItem("sigre_token");
        } catch (error) {
            return null;
        }
    }

    const soportado = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
    const esIphone = /iphone|ipad|ipod/i.test(navigator.userAgent);

    async function pedir(ruta, cuerpo) {
        const respuesta = await fetch(API + ruta, {
            method: cuerpo ? "POST" : "GET",
            headers: Object.assign(
                { Authorization: "Bearer " + leerToken() },
                cuerpo ? { "Content-Type": "application/json" } : {}
            ),
            body: cuerpo ? JSON.stringify(cuerpo) : undefined
        });
        const datos = await respuesta.json().catch(() => ({}));
        if (!respuesta.ok) throw new Error(datos.error || "No se pudo completar la acción.");
        return datos;
    }

    // La clave pública VAPID viene en base64url; el navegador la pide en bytes.
    function claveEnBytes(texto) {
        const relleno = "=".repeat((4 - (texto.length % 4)) % 4);
        const binario = atob((texto + relleno).replace(/-/g, "+").replace(/_/g, "/"));
        return Uint8Array.from(binario, letra => letra.charCodeAt(0));
    }

    async function registro() {
        // Espera al service worker (lo registra js/config.js en la versión publicada).
        const existente = await navigator.serviceWorker.getRegistration();
        if (!existente) return null;
        return navigator.serviceWorker.ready;
    }

    async function suscripcionActual() {
        if (!soportado) return null;
        const reg = await registro();
        return reg ? reg.pushManager.getSubscription() : null;
    }

    async function activar() {
        // El permiso se pide primero, en el mismo toque: si se espera a la red,
        // algunos navegadores ya no muestran la pregunta.
        const permiso = await Notification.requestPermission();
        if (permiso !== "granted") {
            throw new Error(permiso === "denied"
                ? "Bloqueaste las notificaciones. Actívalas en la configuración del navegador (ícono del candado → Notificaciones)."
                : "No diste permiso para las notificaciones.");
        }

        const reg = await registro();
        if (!reg) throw new Error("Las notificaciones funcionan en la versión publicada de SIGRE (sigre.onrender.com).");
        const { activo, clave } = await pedir("/api/push/clave-publica");
        if (!activo) throw new Error("Las notificaciones push aún no están configuradas en el servidor.");

        let suscripcion = await reg.pushManager.getSubscription();
        if (!suscripcion) {
            suscripcion = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: claveEnBytes(clave) });
        }
        await pedir("/api/push/suscribir", suscripcion.toJSON());
    }

    async function desactivar() {
        const suscripcion = await suscripcionActual();
        if (!suscripcion) return;
        if (leerToken()) {
            await pedir("/api/push/desuscribir", { endpoint: suscripcion.endpoint }).catch(() => {});
        }
        await suscripcion.unsubscribe();
    }

    window.SigrePush = {
        // Al cerrar sesión: no espera más de 2 segundos para no trabar la salida.
        desactivar: () => Promise.race([desactivar(), new Promise(listo => setTimeout(listo, 2000))])
    };

    if (!enlacesMenu || !leerToken()) return;

    /* ---------- Opción del menú ☰ ---------- */

    const opcion = document.createElement("button");
    opcion.type = "button";
    opcion.className = "cuenta_menu_enlace cuenta_menu_push";
    const nota = document.createElement("small");
    nota.className = "cuenta_menu_push_nota";
    nota.hidden = true;

    // Va justo después de "Notificaciones".
    const campana = Array.from(enlacesMenu.children).find(hijo => /Notificaciones/.test(hijo.textContent));
    enlacesMenu.insertBefore(opcion, campana ? campana.nextSibling : enlacesMenu.lastChild);
    enlacesMenu.insertBefore(nota, opcion.nextSibling);

    let activas = false;

    function pintar(texto) {
        opcion.innerHTML = activas
            ? '<i class="fa-solid fa-bell-slash"></i><span>Desactivar avisos en este dispositivo</span>'
            : '<i class="fa-solid fa-mobile-screen"></i><span>Activar avisos en este dispositivo</span>';
        nota.textContent = texto || "";
        nota.hidden = !texto;
    }

    async function revisar() {
        try {
            const suscripcion = await suscripcionActual();
            activas = Boolean(suscripcion) && Notification.permission === "granted";
        } catch (error) {
            activas = false;
        }
        pintar(activas ? "Te llegan avisos aunque SIGRE esté cerrada." : "");
    }

    opcion.addEventListener("click", async () => {
        if (!soportado) {
            pintar(esIphone
                ? "En iPhone, primero instala SIGRE: botón Compartir → «Agregar a inicio», y ábrela desde ese ícono."
                : "Este navegador no permite notificaciones. Prueba con Chrome.");
            return;
        }
        opcion.disabled = true;
        try {
            if (activas) {
                await desactivar();
                activas = false;
                pintar("Ya no te llegarán avisos en este dispositivo.");
            } else {
                await activar();
                activas = true;
                pintar("¡Listo! Te llegarán avisos aunque SIGRE esté cerrada.");
            }
        } catch (error) {
            pintar(error.message);
        } finally {
            opcion.disabled = false;
        }
    });

    pintar();
    revisar();
})();
