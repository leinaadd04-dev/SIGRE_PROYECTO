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

/* Modo oscuro: se recuerda en el navegador y se aplica antes de pintar la página. */
(() => {
    const CLAVE = "sigre_tema";
    const leer = () => {
        try { return localStorage.getItem(CLAVE) === "oscuro" ? "oscuro" : "claro"; } catch (error) { return "claro"; }
    };
    document.documentElement.dataset.tema = leer();

    const hoja = document.createElement("link");
    hoja.rel = "stylesheet";
    hoja.href = "css/tema_oscuro.css";
    document.head.appendChild(hoja);

    document.addEventListener("DOMContentLoaded", () => {
        const boton = document.createElement("button");
        boton.type = "button";
        boton.className = "tema_boton";
        const pintar = () => {
            const oscuro = leer() === "oscuro";
            boton.innerHTML = oscuro
                ? '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
                : '<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';
            boton.title = oscuro ? "Modo claro" : "Modo oscuro";
            boton.setAttribute("aria-label", boton.title);
        };
        boton.addEventListener("click", () => {
            const nuevo = leer() === "oscuro" ? "claro" : "oscuro";
            try { localStorage.setItem(CLAVE, nuevo); } catch (error) { /* sin almacenamiento */ }
            document.documentElement.dataset.tema = nuevo;
            pintar();
        });
        pintar();
        document.body.appendChild(boton);
    });
})();
