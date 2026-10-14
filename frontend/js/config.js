/* SIGRE · Configuración compartida (se carga primero en todas las páginas)
   - window.SIGRE_API: dirección del servidor Flask.
       En tu PC (Live Server en el puerto 5500 o python -m http.server en 8000)
       la API está aparte, en el puerto 5000 del mismo equipo.
       Publicado en internet (Render), Flask entrega las páginas y la API desde
       la misma dirección, así que se usa la dirección de la página.
   - Registra el service worker para que SIGRE se pueda instalar como app.
     Solo en internet (HTTPS): en desarrollo no se registra para no guardar
     versiones viejas de los archivos mientras programas. */
(() => {
    const { protocol, hostname, port, origin } = window.location;
    const desarrollo = protocol === "file:" || port === "5500" || port === "8000";

    window.SIGRE_API = desarrollo ? `http://${hostname || "127.0.0.1"}:5000` : origin;

    if (!desarrollo && "serviceWorker" in navigator && protocol === "https:") {
        window.addEventListener("load", () => {
            navigator.serviceWorker.register("service-worker.js").catch(() => {
                // Sin service worker la página funciona igual; solo no se instala.
            });
        });
    }
})();
