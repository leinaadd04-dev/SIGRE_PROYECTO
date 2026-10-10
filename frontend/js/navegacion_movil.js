/* SIGRE · Navegación inferior para celular (todas las páginas del ciudadano)
   - Mismo estilo que las pestañas del panel de administración: una barra con
     pestañas que se desliza de lado, la página actual resaltada y SOS en rojo.
   - Reemplaza la barra que traía cada página, para que todas sean iguales.
   - SOS pregunta y luego llama a la línea única de emergencias 123.
   Expone window.SigreSOS() para que otros botones SOS hagan lo mismo. */
(() => {
    if (!document.querySelector(".cabecera_dashboard") || document.body.classList.contains("pagina_admin")) return;

    const OPCIONES = [
        { href: "dashboard.html", icono: "fa-house", texto: "Inicio" },
        { href: "rutas.html", icono: "fa-route", texto: "Rutas" },
        { href: "centros.html", icono: "fa-house-chimney", texto: "Centros" },
        { sos: true },
        { href: "solicitar_ayuda.html", icono: "fa-hand-holding-heart", texto: "Pedir ayuda" },
        { href: "jornadas.html", icono: "fa-people-group", texto: "Jornadas" },
        { href: "desaparecidos.html", icono: "fa-person-circle-question", texto: "Desaparecidos" }
    ];

    function llamarSOS() {
        const confirmar = window.confirm(
            "¿Llamar a la línea única de emergencias 123?\n\n" +
            "Úsala si tú u otra persona está en peligro."
        );
        if (confirmar) window.location.href = "tel:123";
    }
    window.SigreSOS = llamarSOS;

    const paginaActual = window.location.pathname.split("/").pop() || "dashboard.html";

    let nav = document.querySelector(".navegacion_inferior");
    if (!nav) {
        nav = document.createElement("nav");
        document.body.appendChild(nav);
    }
    nav.className = "navegacion_inferior nav_movil_sigre";
    nav.setAttribute("aria-label", "Navegación principal");
    nav.replaceChildren();

    OPCIONES.forEach(opcion => {
        let elemento;
        if (opcion.sos) {
            elemento = document.createElement("button");
            elemento.type = "button";
            elemento.className = "nav_movil_pestana nav_movil_sos";
            elemento.setAttribute("aria-label", "SOS: llamar a la línea de emergencias 123");
            elemento.innerHTML = '<i class="fa-solid fa-tower-broadcast" aria-hidden="true"></i><span>SOS</span>';
            elemento.addEventListener("click", llamarSOS);
        } else {
            elemento = document.createElement("a");
            elemento.href = opcion.href;
            elemento.className = "nav_movil_pestana";
            elemento.innerHTML = `<i class="fa-solid ${opcion.icono}" aria-hidden="true"></i><span>${opcion.texto}</span>`;
            if (opcion.href === paginaActual) {
                elemento.classList.add("activa");
                elemento.setAttribute("aria-current", "page");
            }
        }
        nav.appendChild(elemento);
    });

    document.body.classList.add("con_nav_movil");

    // Deja visible la pestaña de la página actual aunque la barra se deslice.
    const activa = nav.querySelector(".activa");
    if (activa) {
        requestAnimationFrame(() => {
            nav.scrollLeft = activa.offsetLeft - (nav.clientWidth - activa.offsetWidth) / 2;
        });
    }
})();
