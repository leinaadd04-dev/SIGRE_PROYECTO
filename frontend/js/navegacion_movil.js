/* SIGRE · Navegación de las páginas del ciudadano (celular y escritorio)
   - Celular: barra inferior con el mismo estilo que las pestañas del panel de
     administración (se desliza de lado, página actual resaltada, SOS en rojo).
   - Escritorio: los enlaces de la cabecera, con las mismas opciones.
   - Reemplaza los enlaces que traía cada página, para que todas sean iguales.
     Las opciones de la cuenta (Mi perfil, Notificaciones…) están en el menú ☰
     (js/cuenta_sigre.js).
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

    // Escritorio: mismos módulos en la cabecera y "Cerrar sesión" al final.
    const navEscritorio = document.querySelector(".cabecera_dashboard .navegacion_escritorio");
    if (navEscritorio) {
        navEscritorio.classList.add("nav_escritorio_sigre");
        navEscritorio.setAttribute("aria-label", "Navegación principal");
        navEscritorio.replaceChildren();
        OPCIONES.filter(opcion => !opcion.sos).forEach(opcion => {
            const enlace = document.createElement("a");
            enlace.href = opcion.href;
            enlace.className = "enlace_escritorio";
            enlace.title = opcion.texto;
            enlace.innerHTML = `<i class="fa-solid ${opcion.icono}" aria-hidden="true"></i><span>${opcion.texto}</span>`;
            if (opcion.href === paginaActual) {
                enlace.classList.add("activo");
                enlace.setAttribute("aria-current", "page");
            }
            navEscritorio.appendChild(enlace);
        });
        const salir = document.createElement("a");
        salir.href = "#";
        salir.className = "enlace_escritorio nav_escritorio_salir";
        salir.title = "Cerrar sesión";
        salir.innerHTML = '<i class="fa-solid fa-right-from-bracket" aria-hidden="true"></i><span>Cerrar sesión</span>';
        salir.addEventListener("click", evento => {
            evento.preventDefault();
            // Mismo cierre que el menú ☰: también apaga los avisos push del dispositivo.
            if (window.SigreCuenta && window.SigreCuenta.cerrarSesion) {
                window.SigreCuenta.cerrarSesion();
                return;
            }
            try {
                localStorage.removeItem("sigre_usuario");
                localStorage.removeItem("sigre_token");
            } catch (error) { /* nada que limpiar */ }
            window.location.href = "index.html";
        });
        navEscritorio.appendChild(salir);
    }

    // Deja visible la pestaña de la página actual aunque la barra se deslice.
    const activa = nav.querySelector(".activa");
    if (activa) {
        requestAnimationFrame(() => {
            nav.scrollLeft = activa.offsetLeft - (nav.clientWidth - activa.offsetWidth) / 2;
        });
    }
})();
