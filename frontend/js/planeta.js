/* SIGRE · Planeta 3D (escena de Spline) en "¿Qué es SIGRE?" del inicio.
   - Solo en pantallas de 768 px o más: en el celular no se descarga nada.
   - Carga la escena cuando la sección está por aparecer y la quita al salir,
     para que no siga dibujando (memoria y batería) fuera de la vista.
   - Usa el mismo visor que la intro (js/intro.js): si ya está cargado, no lo repite. */
(function () {
    const VISOR = "https://cdn.spline.design/@splinetool/viewer@2.0.131/build/spline-viewer.webgl.js";
    const ESCENA = "https://prod.spline.design/jfG72sPRBqORINaL/scene.splinecode";

    const contenedor = document.getElementById("planeta-sigre");
    const pantallaAncha = window.matchMedia("(min-width: 768px)");
    const reducirMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!contenedor || reducirMovimiento || !("IntersectionObserver" in window)) return;

    function cargarVisor() {
        if (customElements.get("spline-viewer") || document.querySelector(`script[src="${VISOR}"]`)) return;
        const script = document.createElement("script");
        script.type = "module";
        script.src = VISOR;
        document.head.appendChild(script);
    }

    function mostrar() {
        if (!pantallaAncha.matches || contenedor.firstChild) return;
        cargarVisor();
        const visor = document.createElement("spline-viewer");
        visor.setAttribute("url", ESCENA);
        contenedor.appendChild(visor);
    }

    function quitar() {
        contenedor.replaceChildren();
    }

    const observador = new IntersectionObserver(entradas => {
        if (entradas[0].isIntersecting) mostrar();
        else quitar();
    }, { rootMargin: "200px 0px" });
    observador.observe(contenedor);

    // Al agrandar la ventana se vuelve a revisar si la sección está a la vista.
    pantallaAncha.addEventListener("change", evento => {
        observador.unobserve(contenedor);
        if (evento.matches) observador.observe(contenedor);
        else quitar();
    });
})();
