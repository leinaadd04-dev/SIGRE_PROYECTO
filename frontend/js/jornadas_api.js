// SIGRE · Jornadas comunitarias con datos reales (GET /api/jornadas).
// - Tarjetas, jornada destacada (la próxima), avatares de quienes van y la
//   gráfica "Participación por categoría" salen de la base de datos.
// - "Quiero participar" inscribe a la cuenta en el servidor.
// - "Ver quiénes van" abre la lista de participantes.
// Filtros, corazones (mis intereses) y "Ver ubicación" los maneja js/jornadas.js.
(() => {
    const API_BASE = window.SIGRE_API;   // js/config.js
    const CLAVE_TOKEN = "sigre_token";
    const grid = document.getElementById("jornadas-grid");
    if (!grid) return;

    const CATEGORIAS = {
        limpieza: { texto: "Limpieza comunitaria", corto: "Limpieza", icono: "fa-broom", color: "icono_verde", barra: "#2e7d32" },
        salud: { texto: "Salud comunitaria", corto: "Salud", icono: "fa-kit-medical", color: "icono_coral", barra: "#2c7da0" },
        solidaridad: { texto: "Solidaridad", corto: "Solidaridad", icono: "fa-hand-holding-heart", color: "icono_amarillo", barra: "#e63946" },
        apoyo: { texto: "Apoyo a la comunidad", corto: "Apoyo", icono: "fa-people-group", color: "icono_azul", barra: "#ffb703" }
    };
    // Los mismos animalitos que se eligen en "Mi cuenta" (js/cuenta_sigre.js).
    const ANIMALES = {
        perro: ["🐶", "#ffe8cc"], gato: ["🐱", "#fff3c4"], zorro: ["🦊", "#ffe0d1"], panda: ["🐼", "#e8ecef"],
        koala: ["🐨", "#e3e8f4"], leon: ["🦁", "#ffefc2"], rana: ["🐸", "#dff5d8"], mono: ["🐵", "#f3e3d3"],
        conejo: ["🐰", "#fce8f0"], tigre: ["🐯", "#ffe6c7"], oso: ["🐻", "#efe2d6"], buho: ["🦉", "#ece9fb"]
    };
    const COLORES_INICIAL = ["#4A90D9", "#5A4FCF", "#2F855A", "#C05621", "#B83280", "#2C7A7B", "#6B46C1"];

    let jornadas = [];

    const htmlSafe = valor => String(valor == null ? "" : valor).replace(/[&<>"']/g, c => (
        { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
    ));

    function leerToken() {
        try {
            return localStorage.getItem(CLAVE_TOKEN);
        } catch (error) {
            return null;
        }
    }

    async function api(ruta, opciones) {
        const token = leerToken();
        const encabezados = Object.assign(
            token ? { Authorization: "Bearer " + token } : {},
            opciones && opciones.body ? { "Content-Type": "application/json" } : {}
        );
        const respuesta = await fetch(API_BASE + ruta, Object.assign({}, opciones, { headers: encabezados }));
        let datos = null;
        try {
            datos = await respuesta.json();
        } catch (error) {
            // Respuesta sin JSON.
        }
        if (respuesta.status === 401 && token) {
            throw new Error("Tu sesión expiró. Vuelve a iniciar sesión.");
        }
        if (!respuesta.ok) throw new Error((datos && (datos.error || datos.msg)) || "No se pudo completar la acción.");
        return datos;
    }

    function cuando(fechaIso, conDia) {
        return new Date(fechaIso).toLocaleString("es-CO", {
            weekday: conDia ? "long" : undefined, day: "numeric", month: "long",
            hour: "numeric", minute: "2-digit"
        });
    }

    function avatar(persona, clase) {
        const animal = ANIMALES[persona.animal];
        if (animal) {
            return `<span class="${clase} avatar_animal" style="background:${animal[1]}" title="${htmlSafe(persona.nombre)}" aria-hidden="true">${animal[0]}</span>`;
        }
        const nombre = String(persona.nombre || "?");
        let suma = 0;
        for (const letra of nombre) suma += letra.codePointAt(0);
        const color = COLORES_INICIAL[suma % COLORES_INICIAL.length];
        return `<span class="${clase}" style="background:${color}" title="${htmlSafe(nombre)}" aria-hidden="true">${htmlSafe(nombre.trim().charAt(0).toUpperCase() || "?")}</span>`;
    }

    function textoAsistentes(j) {
        const total = j.participantes || 0;
        if (!total) return "Sé la primera persona en inscribirte";
        if (j.participo) {
            return total === 1 ? "Tú vas" : `Tú y ${total - 1} persona${total - 1 === 1 ? "" : "s"} más van`;
        }
        return `${total} persona${total === 1 ? " va" : "s van"}`;
    }

    function bloqueAsistentes(j) {
        const avatares = (j.vista_previa || []).slice(0, 3).map(p => avatar(p, "avatar_mini")).join("");
        return `<button type="button" class="jornada_asistentes boton_ver_participantes" data-jornada="${j.id}" ${j.participantes ? "" : "disabled"}>
            ${avatares ? `<span class="avatares_grupo">${avatares}</span>` : ""}
            <span class="texto_asistentes">${htmlSafe(textoAsistentes(j))}</span>
            ${j.participantes ? `<span class="ver_asistentes">Ver quiénes van <i class="fa-solid fa-chevron-right" aria-hidden="true"></i></span>` : ""}
        </button>`;
    }

    function botonParticipar(j, clase) {
        return `<button type="button" class="${clase}${j.participo ? " seleccionado" : ""}" data-participar="${j.id}" aria-pressed="${j.participo}">
            ${j.participo ? "Cancelar participación" : "Quiero participar"}
        </button>`;
    }

    function tarjeta(j) {
        const categoria = CATEGORIAS[j.categoria] || CATEGORIAS.apoyo;
        const ubicacion = j.latitud != null
            ? `<button type="button" class="boton_ver_ubicacion" data-lat="${j.latitud}" data-lon="${j.longitud}" data-nombre="${htmlSafe(j.nombre)}">
                   <i class="fa-solid fa-location-dot"></i> Ver ubicación
               </button>`
            : "";
        return `<article class="tarjeta_jornada jornada_publicada" data-categoria="${htmlSafe(j.categoria)}" data-jornada="${j.id}">
            <div class="jornada_icono ${categoria.color}"><i class="fa-solid ${categoria.icono}"></i></div>
            <div class="jornada_contenido">
                <span class="jornada_categoria">${htmlSafe(categoria.texto)}</span>
                <h3>${htmlSafe(j.nombre)}</h3>
                <p>${htmlSafe(j.descripcion)}</p>
                <div class="jornada_datos">
                    <div><i class="fa-regular fa-calendar"></i><span>Fecha: <strong>${htmlSafe(cuando(j.fecha_inicio, true))}</strong></span></div>
                    <div><i class="fa-solid fa-location-dot"></i><span>Lugar: <strong>${htmlSafe(j.lugar)}</strong></span></div>
                </div>
                ${bloqueAsistentes(j)}
                <div class="fila_acciones_tarjeta">
                    ${ubicacion}
                    ${botonParticipar(j, "boton_participar_tarjeta")}
                    <button type="button" class="boton_me_gusta" data-id="sigre-${j.id}" data-nombre="${htmlSafe(j.nombre)}" aria-pressed="false" aria-label="Guardar en mis intereses">
                        <i class="fa-regular fa-heart"></i>
                    </button>
                </div>
            </div>
        </article>`;
    }

    /* ---------- Pintar ---------- */

    function pintarDestacada() {
        const seccion = document.getElementById("jornada-destacada");
        if (!seccion) return;
        // La más próxima que todavía no ha empezado (o la primera de la lista).
        const ahora = Date.now();
        const j = jornadas.find(item => new Date(item.fecha_inicio).getTime() >= ahora) || jornadas[0];
        if (!j) {
            seccion.hidden = true;
            return;
        }
        const categoria = CATEGORIAS[j.categoria] || CATEGORIAS.apoyo;
        document.getElementById("destacada-categoria").textContent = categoria.texto;
        document.getElementById("destacada-nombre").textContent = j.nombre;
        document.getElementById("destacada-descripcion").textContent = j.descripcion;
        document.getElementById("destacada-fecha").textContent = cuando(j.fecha_inicio, true);
        document.getElementById("destacada-lugar").textContent = j.lugar;
        document.getElementById("destacada-asistentes").textContent = textoAsistentes(j);
        document.getElementById("destacada-acciones").innerHTML =
            botonParticipar(j, "boton_unirme") +
            (j.participantes ? `<button type="button" class="boton_ver_ubicacion boton_ver_participantes" data-jornada="${j.id}"><i class="fa-solid fa-user-group"></i> Ver quiénes van</button>` : "") +
            (j.latitud != null ? `<button type="button" class="boton_ver_ubicacion" data-lat="${j.latitud}" data-lon="${j.longitud}" data-nombre="${htmlSafe(j.nombre)}"><i class="fa-solid fa-location-dot"></i> Ver ubicación</button>` : "");
        seccion.hidden = false;
    }

    function pintarTarjetas() {
        const estado = document.getElementById("estado-jornadas");
        if (estado) estado.textContent = `${jornadas.length} publicada${jornadas.length === 1 ? "" : "s"}`;
        if (!jornadas.length) {
            grid.innerHTML = `<p class="jornadas_vacio">Por ahora no hay jornadas publicadas. Cuando una entidad publique una, aparecerá aquí y te llegará una notificación.</p>`;
        } else {
            grid.innerHTML = jornadas.map(tarjeta).join("");
        }
        // Respeta el filtro elegido y actualiza corazones (js/jornadas.js).
        const chipActivo = document.querySelector(".chip_filtro.activo");
        if (chipActivo) chipActivo.click();
        document.dispatchEvent(new CustomEvent("sigre:jornadas-pintadas"));
    }

    function pintarMisParticipaciones() {
        const lista = document.getElementById("lista-participadas");
        if (!lista) return;
        const mias = jornadas.filter(j => j.participo);
        if (!leerToken()) {
            lista.innerHTML = `<p class="aviso_sin_intereses">Inicia sesión para inscribirte en una jornada.</p>`;
            return;
        }
        if (!mias.length) {
            lista.innerHTML = `<p class="aviso_sin_intereses">Aún no te has inscrito en una jornada.</p>`;
            return;
        }
        lista.innerHTML = mias.map(j => `<div class="item_lista_jornada">
            <span class="nombre_item_lista">${htmlSafe(j.nombre)}<small>${htmlSafe(cuando(j.fecha_inicio))}</small></span>
            <button type="button" class="quitar_item_jornada" data-participar="${j.id}" aria-label="Cancelar participación en ${htmlSafe(j.nombre)}">
                <i class="fa-solid fa-xmark" aria-hidden="true"></i>
            </button>
        </div>`).join("");
    }

    function pintarGrafica(estadisticas) {
        const contenedor = document.getElementById("grafico-barras");
        if (!contenedor) return;
        const porCategoria = {};
        estadisticas.forEach(e => { porCategoria[e.categoria] = e; });
        const maximo = Math.max(1, ...estadisticas.map(e => e.promedio));
        const total = estadisticas.reduce((suma, e) => suma + e.participantes, 0);

        contenedor.innerHTML = Object.keys(CATEGORIAS).map(clave => {
            const c = CATEGORIAS[clave];
            const e = porCategoria[clave] || { promedio: 0, jornadas: 0, participantes: 0 };
            const alto = e.promedio > 0 ? Math.max(8, Math.round(e.promedio / maximo * 100)) : 3;
            const valor = Number.isInteger(e.promedio) ? e.promedio : e.promedio.toFixed(1);
            const detalle = `${c.corto}: ${e.participantes} inscrito${e.participantes === 1 ? "" : "s"} en ${e.jornadas} jornada${e.jornadas === 1 ? "" : "s"}`;
            return `<div class="barra_item" title="${htmlSafe(detalle)}">
                <span class="barra_valor">${valor}</span>
                <div class="barra" style="height:${alto}%;background:${c.barra}"></div>
                <span class="barra_etiqueta">${c.corto}</span>
            </div>`;
        }).join("");
        contenedor.setAttribute("aria-label", "Promedio de personas inscritas por jornada: " +
            Object.keys(CATEGORIAS).map(clave => `${CATEGORIAS[clave].corto} ${(porCategoria[clave] || { promedio: 0 }).promedio}`).join(", "));

        const subtitulo = document.getElementById("grafico-subtitulo");
        if (subtitulo) {
            subtitulo.textContent = total
                ? `Promedio de personas inscritas por jornada · ${total} inscripcion${total === 1 ? "" : "es"} en total`
                : "Aún no hay inscripciones: ¡anímate a participar!";
        }
    }

    function pintarTodo() {
        pintarTarjetas();
        pintarDestacada();
        pintarMisParticipaciones();
    }

    /* ---------- Cargar ---------- */

    async function cargarGrafica() {
        try {
            pintarGrafica(await api("/api/jornadas/estadisticas"));
        } catch (error) {
            const subtitulo = document.getElementById("grafico-subtitulo");
            if (subtitulo) subtitulo.textContent = "No se pudo cargar la gráfica.";
        }
    }

    async function cargar() {
        try {
            jornadas = await api("/api/jornadas");
            pintarTodo();
        } catch (error) {
            const estado = document.getElementById("estado-jornadas");
            if (estado) estado.textContent = "Sin conexión";
            grid.innerHTML = `<p class="jornadas_vacio">${htmlSafe(error.message === "Failed to fetch"
                ? "No hay conexión con el servidor de SIGRE. Revisa que Flask esté en ejecución."
                : error.message)}</p>`;
        }
        cargarGrafica();
    }

    /* ---------- Avisos ---------- */

    function avisar(texto, tipo) {
        let aviso = document.getElementById("aviso-jornadas");
        if (!aviso) {
            aviso = document.createElement("div");
            aviso.id = "aviso-jornadas";
            aviso.className = "aviso_flotante_jornadas";
            aviso.setAttribute("role", "status");
            document.body.appendChild(aviso);
        }
        aviso.textContent = texto;
        aviso.dataset.tipo = tipo || "exito";
        aviso.classList.add("visible");
        clearTimeout(avisar.temporizador);
        avisar.temporizador = setTimeout(() => aviso.classList.remove("visible"), 3500);
    }

    /* ---------- Participar ---------- */

    async function alternarParticipacion(id, boton) {
        const j = jornadas.find(item => String(item.id) === String(id));
        if (!j) return;
        if (!leerToken()) {
            avisar("Inicia sesión para inscribirte en una jornada.", "error");
            return;
        }
        if (j.participo && !window.confirm(`¿Cancelar tu participación en "${j.nombre}"?`)) return;
        if (boton) boton.disabled = true;
        try {
            const resultado = await api(`/api/jornadas/${j.id}/participar`, {
                method: "POST",
                body: JSON.stringify({ participar: !j.participo })
            });
            avisar(resultado.mensaje);
            // Recarga para traer los avatares y el total actualizados.
            jornadas = await api("/api/jornadas");
            pintarTodo();
            cargarGrafica();
        } catch (error) {
            avisar(error.message === "Failed to fetch" ? "No hay conexión con el servidor." : error.message, "error");
            if (boton) boton.disabled = false;
        }
    }

    /* ---------- Ventana "Quiénes van" ---------- */

    const ventana = document.getElementById("ventana-participantes");
    const listaParticipantes = document.getElementById("lista-participantes");
    const estadoParticipantes = document.getElementById("participantes-estado");
    let focoPrevio = null;

    async function abrirParticipantes(id) {
        const j = jornadas.find(item => String(item.id) === String(id));
        if (!j || !ventana) return;
        focoPrevio = document.activeElement;
        document.getElementById("participantes-titulo").textContent = j.nombre;
        document.getElementById("participantes-subtitulo").textContent = textoAsistentes(j);
        listaParticipantes.innerHTML = "";
        estadoParticipantes.textContent = "Cargando...";
        estadoParticipantes.hidden = false;
        ventana.hidden = false;
        document.getElementById("boton-cerrar-participantes").focus();
        try {
            const personas = await api(`/api/jornadas/${j.id}/participantes`);
            estadoParticipantes.hidden = personas.length > 0;
            estadoParticipantes.textContent = personas.length ? "" : "Todavía no hay personas inscritas.";
            listaParticipantes.innerHTML = personas.map(p => `<li class="participante${p.es_yo ? " participante_yo" : ""}">
                ${avatar(p, "avatar_participante")}
                <span class="participante_datos">
                    <strong>${htmlSafe(p.nombre)}${p.es_yo ? " <em>(tú)</em>" : ""}</strong>
                    ${p.email ? `<a href="mailto:${htmlSafe(p.email)}">${htmlSafe(p.email)}</a>` : ""}
                    ${p.telefono ? `<a href="tel:${htmlSafe(p.telefono)}"><i class="fa-solid fa-phone" aria-hidden="true"></i> ${htmlSafe(p.telefono)}</a>` : ""}
                    <small>Inscrito el ${htmlSafe(new Date(p.inscrito_en).toLocaleDateString("es-CO", { day: "numeric", month: "short" }))}</small>
                </span>
            </li>`).join("");
        } catch (error) {
            estadoParticipantes.textContent = error.message;
        }
    }

    function cerrarParticipantes() {
        if (!ventana || ventana.hidden) return;
        ventana.hidden = true;
        if (focoPrevio) focoPrevio.focus();
    }

    /* ---------- Eventos ---------- */

    document.addEventListener("click", evento => {
        const participar = evento.target.closest("[data-participar]");
        if (participar) {
            alternarParticipacion(participar.dataset.participar, participar);
            return;
        }
        const ver = evento.target.closest(".boton_ver_participantes");
        if (ver && !ver.disabled) abrirParticipantes(ver.dataset.jornada);
    });

    if (ventana) {
        document.getElementById("boton-cerrar-participantes").addEventListener("click", cerrarParticipantes);
        ventana.addEventListener("click", evento => {
            if (evento.target === ventana) cerrarParticipantes();
        });
        document.addEventListener("keydown", evento => {
            if (evento.key === "Escape") cerrarParticipantes();
        });
    }

    // Mantiene los totales al día si otras personas se inscriben.
    setInterval(() => {
        if (document.visibilityState !== "visible" || (ventana && !ventana.hidden)) return;
        api("/api/jornadas").then(datos => {
            if (JSON.stringify(datos) === JSON.stringify(jornadas)) return;
            jornadas = datos;
            pintarTodo();
            cargarGrafica();
        }).catch(() => {});
    }, 60000);

    cargar();
})();
