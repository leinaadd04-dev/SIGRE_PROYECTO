/* SIGRE · Campana de notificaciones (compartida por todas las páginas internas)
   - Lee GET /api/notificaciones y muestra el contador y el panel.
   - Se actualiza sola cada 30 segundos mientras la pestaña está visible y
     muestra un aviso emergente cuando llega una notificación nueva.
   - Al abrir una notificación la marca como leída y lleva a su página. */
(() => {
    const cabecera = document.querySelector(".cabecera_dashboard");
    if (!cabecera) return;

    const API_BASE = window.SIGRE_API;   // js/config.js
    const CLAVE_TOKEN = "sigre_token";
    const INTERVALO = 30000;

    const ICONOS = {
        emergencia: "fa-triangle-exclamation",
        jornada: "fa-people-group",
        desaparecido: "fa-magnifying-glass",
        solicitud: "fa-hand-holding-heart",
        comentario: "fa-comment-dots",
        centro: "fa-house-chimney-medical",
        cuenta: "fa-user-shield"
    };

    let notificaciones = [];
    let idsConocidos = null;   // null hasta la primera carga: no se muestran avisos de lo viejo
    let cargando = false;

    function leerToken() {
        try {
            return localStorage.getItem(CLAVE_TOKEN);
        } catch (error) {
            return null;
        }
    }

    const CLAVE_NOTIFICACIONES_OCULTAS = "sigre_notificaciones_ocultas";

    function leerNotificacionesOcultas() {
        try {
            return JSON.parse(
                localStorage.getItem(CLAVE_NOTIFICACIONES_OCULTAS) || "[]"
            ).map(String);
        } catch (error) {
            return [];
        }
    }

    function guardarNotificacionOculta(id) {
        const ocultas = new Set(leerNotificacionesOcultas());
        ocultas.add(String(id));

        try {
            localStorage.setItem(
                CLAVE_NOTIFICACIONES_OCULTAS,
                JSON.stringify([...ocultas])
            );
        } catch (error) {
            console.error("No se pudo guardar la notificación oculta.", error);
        }
    }


    function crear(etiqueta, clase, texto) {
        const elemento = document.createElement(etiqueta);
        if (clase) elemento.className = clase;
        if (texto !== undefined) elemento.textContent = texto;
        return elemento;
    }

    function icono(nombre) {
        const i = crear("i", "fa-solid " + nombre);
        i.setAttribute("aria-hidden", "true");
        return i;
    }

    function hace(fechaIso) {
        const segundos = Math.max(0, (Date.now() - new Date(fechaIso).getTime()) / 1000);
        if (segundos < 60) return "Hace un momento";
        const minutos = Math.floor(segundos / 60);
        if (minutos < 60) return "Hace " + minutos + " min";
        const horas = Math.floor(minutos / 60);
        if (horas < 24) return "Hace " + horas + " h";
        const dias = Math.floor(horas / 24);
        if (dias < 7) return dias === 1 ? "Ayer" : "Hace " + dias + " días";
        return new Date(fechaIso).toLocaleDateString("es-CO", { day: "numeric", month: "short" });
    }

    /* ---------- Campana y panel ---------- */

    let derecha = cabecera.querySelector(".cabecera_derecha");
    if (!derecha) {
        derecha = crear("div", "cabecera_derecha");
        cabecera.appendChild(derecha);
    }

    // Reutiliza la campana de la página (si es un enlace, la cambia por un botón).
    let campana = derecha.querySelector(".boton_campana");
    if (!campana || campana.tagName !== "BUTTON") {
        const nueva = crear("button", "boton_campana");
        nueva.type = "button";
        nueva.appendChild(icono("fa-bell"));
        if (campana) campana.replaceWith(nueva);
        else derecha.prepend(nueva);
        campana = nueva;
    }
    campana.setAttribute("aria-label", "Notificaciones");
    campana.setAttribute("aria-haspopup", "dialog");
    campana.setAttribute("aria-expanded", "false");
    campana.setAttribute("aria-controls", "sigre-panel-notificaciones");

    let contador = campana.querySelector(".contador_notificaciones");
    if (!contador) {
        contador = crear("span", "contador_notificaciones");
        campana.appendChild(contador);
    }
    contador.style.display = "none";

    const contenedor = crear("div", "sigre_notif_contenedor");
    derecha.insertBefore(contenedor, campana);
    contenedor.appendChild(campana);

    const panel = crear("section", "sigre_notif_panel");
    panel.id = "sigre-panel-notificaciones";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", "Notificaciones");
    panel.hidden = true;

    const encabezado = crear("div", "sigre_notif_encabezado");
    encabezado.appendChild(crear("h2", null, "Notificaciones"));
    const botonTodas = crear("button", "sigre_notif_todas", "Marcar todas como leídas");
    botonTodas.type = "button";
    encabezado.appendChild(botonTodas);

    const estado = crear("p", "sigre_notif_estado");
    estado.setAttribute("role", "status");
    const lista = crear("ul", "sigre_notif_lista");

    panel.append(encabezado, estado, lista);
    contenedor.appendChild(panel);

    const avisos = crear("div", "sigre_notif_avisos");
    avisos.setAttribute("aria-live", "polite");
    document.body.appendChild(avisos);

    function pintarContador(cantidad) {
        if (cantidad > 0) {
            contador.textContent = cantidad > 9 ? "9+" : String(cantidad);
            contador.style.display = "flex";
            campana.setAttribute("aria-label", "Notificaciones, " + cantidad + " sin leer");
        } else {
            contador.style.display = "none";
            campana.setAttribute("aria-label", "Notificaciones");
        }
        botonTodas.hidden = cantidad === 0;
        // El menú de la cuenta (js/cuenta_sigre.js) muestra el mismo número.
        document.dispatchEvent(new CustomEvent("sigre:notificaciones", { detail: { noLeidas: cantidad } }));
    }

    function pintarLista() {
        lista.replaceChildren();
        if (!notificaciones.length) {
            estado.textContent = "No tienes notificaciones por ahora.";
            estado.hidden = false;
            return;
        }
        estado.hidden = true;
        notificaciones.forEach(function (item) {
            const fila = crear("li", "sigre_notif_item tipo_" + item.tipo + (item.leida ? " leida" : ""));
            const boton = crear("button", "sigre_notif_boton");
            boton.type = "button";
            boton.dataset.id = item.id;

            const circulo = crear("span", "sigre_notif_icono");
            circulo.appendChild(icono(ICONOS[item.tipo] || "fa-bell"));

            const texto = crear("span", "sigre_notif_texto");
            texto.append(
                crear("strong", null, item.titulo),
                crear("span", "sigre_notif_mensaje", item.mensaje),
                crear("time", null, hace(item.creada_en))
            );
            texto.lastChild.dateTime = item.creada_en;

            boton.append(circulo, texto);
            if (!item.leida) {
                const punto = crear("span", "sigre_notif_punto");
                punto.setAttribute("aria-label", "Sin leer");
                boton.appendChild(punto);
            }
            
            const botonQuitar = crear("button", "sigre_notif_quitar");
            botonQuitar.type = "button";
            botonQuitar.setAttribute(
                "aria-label",
                "Quitar notificación: " + item.titulo
            );
            botonQuitar.title = "Quitar notificación";
            botonQuitar.innerHTML = "&times;";

            fila.append(boton, botonQuitar);
            lista.appendChild(fila);
        });
    }

    function mostrarAviso(item) {
        const aviso = crear("button", "sigre_notif_aviso tipo_" + item.tipo);
        aviso.type = "button";
        const circulo = crear("span", "sigre_notif_icono");
        circulo.appendChild(icono(ICONOS[item.tipo] || "fa-bell"));
        const texto = crear("span", "sigre_notif_texto");
        texto.append(crear("strong", null, item.titulo), crear("span", "sigre_notif_mensaje", item.mensaje));
        aviso.append(circulo, texto);
        aviso.addEventListener("click", function () {
            aviso.remove();
            abrirNotificacion(item);
        });
        avisos.appendChild(aviso);
        setTimeout(function () { aviso.classList.add("saliendo"); }, 7000);
        setTimeout(function () { aviso.remove(); }, 7600);
    }

    /* ---------- API ---------- */

    async function pedir(ruta, metodo) {
        const respuesta = await fetch(API_BASE + ruta, {
            method: metodo || "GET",
            headers: { Authorization: "Bearer " + leerToken() }
        });
        let datos = {};
        try {
            datos = await respuesta.json();
        } catch (error) {
            // Respuesta vacía o no JSON.
        }
        if (!respuesta.ok) throw new Error(datos.error || datos.msg || "No se pudieron cargar las notificaciones.");
        return datos;
    }

    async function cargar() {
        if (cargando) return;
        if (!leerToken()) {
            pintarContador(0);
            estado.textContent = "Inicia sesión para ver tus notificaciones.";
            estado.hidden = false;
            return;
        }
        cargando = true;
        try {
            const datos = await pedir("/api/notificaciones");
            const ocultas = new Set(leerNotificacionesOcultas());

            notificaciones = (datos.notificaciones || []).filter(function (item) {
                return !ocultas.has(String(item.id));
            });

            pintarContador(
                notificaciones.filter(function (item) {
                    return !item.leida;
                }).length
            );

            pintarLista();

            const nuevas = idsConocidos === null ? [] :
                notificaciones.filter(function (item) { return !item.leida && !idsConocidos.has(item.id); });
            idsConocidos = new Set(notificaciones.map(function (item) { return item.id; }));
            nuevas.slice(0, 3).reverse().forEach(mostrarAviso);
            if (nuevas.length) {
                campana.classList.remove("sonando");
                void campana.offsetWidth;
                campana.classList.add("sonando");
            }
        } catch (error) {
            if (!notificaciones.length) {
                estado.textContent = error.message === "Failed to fetch"
                    ? "No hay conexión con el servidor de SIGRE."
                    : error.message;
                estado.hidden = false;
            }
        } finally {
            cargando = false;
        }
    }

    async function marcarLeida(item) {
        if (item.leida) return;
        item.leida = true;
        pintarLista();
        pintarContador(notificaciones.filter(function (n) { return !n.leida; }).length);
        try {
            await pedir("/api/notificaciones/" + encodeURIComponent(item.id) + "/leida", "POST");
        } catch (error) {
            // Se reintentará con la siguiente carga.
        }
    }

    async function abrirNotificacion(item) {
        await marcarLeida(item);
        if (!item.enlace) return;
        const destino = new URL(item.enlace, window.location.href);
        const mismaPagina = destino.pathname === window.location.pathname && destino.search === window.location.search;
        cerrarPanel();
        if (mismaPagina && destino.hash) {
            if (window.location.hash === destino.hash) window.dispatchEvent(new HashChangeEvent("hashchange"));
            else window.location.hash = destino.hash;
            document.querySelector(destino.hash)?.scrollIntoView({ behavior: "smooth", block: "start" });
        } else if (!mismaPagina) {
            window.location.href = destino.href;
        }
    }

    /* ---------- Eventos ---------- */

    // En celulares angostos la campana se oculta y el panel se abre desde el
    // menú de la cuenta: entonces se muestra flotando sobre la página.
    function colocarPanel() {
        const campanaVisible = campana.offsetParent !== null;
        if (campanaVisible && panel.parentElement !== contenedor) {
            contenedor.appendChild(panel);
        } else if (!campanaVisible && panel.parentElement !== document.body) {
            document.body.appendChild(panel);
        }
        panel.classList.toggle("sigre_notif_flotante", !campanaVisible);
    }

    function abrirPanel() {
        colocarPanel();
        panel.hidden = false;
        campana.setAttribute("aria-expanded", "true");
        cargar();
    }

    function cerrarPanel() {
        panel.hidden = true;
        campana.setAttribute("aria-expanded", "false");
    }

    campana.addEventListener("click", function (evento) {
        evento.stopPropagation();
        if (panel.hidden) abrirPanel();
        else cerrarPanel();
    });

    lista.addEventListener("click", function (evento) {
    const botonQuitar = evento.target.closest(".sigre_notif_quitar");
    if (!botonQuitar) return;

    evento.preventDefault();
    evento.stopPropagation();

    const fila = botonQuitar.closest(".sigre_notif_item");
    if (!fila) return;

    const botonNotificacion = fila.querySelector(".sigre_notif_boton");
    const id = botonNotificacion?.dataset.id;

    if (!id) return;

    guardarNotificacionOculta(id);

    notificaciones = notificaciones.filter(function (item) {
        return String(item.id) !== String(id);
    });

    pintarLista();

    pintarContador(
        notificaciones.filter(function (item) {
            return !item.leida;
        }).length
    );
});

    botonTodas.addEventListener("click", async function () {
        notificaciones.forEach(function (n) { n.leida = true; });
        pintarLista();
        pintarContador(0);
        try {
            await pedir("/api/notificaciones/leidas", "POST");
        } catch (error) {
            cargar();
        }
    });

    document.addEventListener("click", function (evento) {
        if (!panel.hidden && !contenedor.contains(evento.target) && !panel.contains(evento.target)) cerrarPanel();
    });
    document.addEventListener("keydown", function (evento) {
        if (evento.key === "Escape" && !panel.hidden) {
            cerrarPanel();
            if (campana.offsetParent !== null) campana.focus();
        }
    });
    document.addEventListener("visibilitychange", function () {
        if (document.visibilityState === "visible") cargar();
    });
    window.setInterval(function () {
        if (document.visibilityState === "visible") cargar();
    }, INTERVALO);

    // Otras partes de la página pueden pedir una actualización inmediata.
    window.SigreNotificaciones = { actualizar: cargar, abrir: abrirPanel };

    cargar();
})();
