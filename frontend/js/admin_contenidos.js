/* SIGRE · Panel de administración, parte 2:
   solicitudes de ayuda (cartas), emergencias, jornadas y directorio.
   Usa las utilidades de js/admin.js (window.SigreAdmin). */
(() => {
    const A = window.SigreAdmin;
    if (!A) return;
    const { API_BASE, llamarApi, htmlSafe, fecha, mostrarMensaje, textoError } = A;

    const T = {
        categoria: { alimentos: "Alimentos", atencion_medica: "Atención médica", alojamiento: "Alojamiento", transporte: "Transporte", ropa: "Ropa", otra: "Otra" },
        motivo: { evaluar_danos: "Evaluar daños", condiciones_vivienda: "Revisar condiciones de la vivienda", riesgo_estructural: "Riesgo estructural", encuesta_social: "Encuesta o caracterización del hogar", otra: "Otro motivo" },
        alcance: { comunidad: "Comunidad o barrio", familias: "Grupo de familias", hogar: "Hogar" },
        urgencia: { baja: "Baja", media: "Media", alta: "Alta", critica: "Crítica" },
        franja: { manana: "mañana (8 a. m. – 12 m.)", tarde: "tarde (2 p. m. – 5 p. m.)", cualquiera: "cualquier horario" },
        estado: { pendiente: "Pendiente", en_revision: "En revisión", programada: "Visita programada", en_atencion: "En atención", atendida: "Atendida", cancelada: "Cancelada" },
        nivel: { bajo: "Bajo", medio: "Medio", alto: "Alto", critico: "Crítico" },
        jornada: { limpieza: "Limpieza comunitaria", salud: "Salud comunitaria", solidaridad: "Solidaridad", apoyo: "Apoyo a la comunidad" },
        grupo: { emergencias: "Emergencias", estado: "Entidades del Estado", salud: "Salud en Montería", comunidad: "Comunidad" }
    };

    function fechaLarga(iso) {
        const partes = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || "");
        if (!partes) return "";
        return new Date(+partes[1], +partes[2] - 1, +partes[3])
            .toLocaleDateString("es-CO", { day: "numeric", month: "long", year: "numeric" });
    }

    // Descarga un archivo protegido (con el token) sin abrir otra pestaña.
    async function descargar(ruta, nombre) {
        const respuesta = await fetch(API_BASE + ruta, { headers: { Authorization: "Bearer " + A.leerToken() } });
        if (!respuesta.ok) {
            let mensaje = "No se pudo descargar el archivo.";
            try { mensaje = (await respuesta.json()).error || mensaje; } catch (error) { /* sin JSON */ }
            throw new Error(mensaje);
        }
        const url = URL.createObjectURL(await respuesta.blob());
        const enlace = document.createElement("a");
        enlace.href = url;
        enlace.download = nombre;
        document.body.appendChild(enlace);
        enlace.click();
        enlace.remove();
        setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    }

    /* =================== Solicitudes (cartas) =================== */

    const listaSolicitudes = document.getElementById("lista-solicitudes-admin");
    const filtroSolicitudes = document.getElementById("filtro-estado-solicitudes");
    const ventanaCarta = document.getElementById("ventana-carta");
    const contenidoCarta = document.getElementById("carta-contenido");
    const estadoCarta = document.getElementById("carta-estado");
    let solicitudes = [];
    let solicitudAbierta = null;

    function asunto(s) {
        return s.tipo === "visita"
            ? `Solicitud de visita a vivienda – ${T.motivo[s.motivo_visita] || "Visita"}`
            : `Solicitud de ayuda – ${T.categoria[s.categoria] || "Ayuda"}`;
    }

    // Fecha completa en hora local (creada_en viene en UTC).
    function fechaCarta(iso) {
        return new Date(iso).toLocaleDateString("es-CO", { day: "numeric", month: "long", year: "numeric" });
    }

    function aQuien(s) {
        const base = { comunidad: "la comunidad", familias: "un grupo de familias", hogar: "su hogar" }[s.alcance] || "";
        return base + (s.nombre_comunidad ? ` de ${s.nombre_comunidad}` : "");
    }

    function beneficiarios(s) {
        return (T.alcance[s.alcance] || s.alcance) + (s.nombre_comunidad ? ` (${s.nombre_comunidad})` : "");
    }

    async function cargarSolicitudes() {
        listaSolicitudes.innerHTML = `<p class="admin_vacio">Cargando solicitudes...</p>`;
        try {
            const estado = filtroSolicitudes.value;
            solicitudes = await llamarApi("/api/admin/solicitudes" + (estado ? "?estado=" + estado : ""));
            mostrarMensaje("mensaje-solicitudes", "");
            if (!solicitudes.length) {
                listaSolicitudes.innerHTML = `<p class="admin_vacio">No hay solicitudes con ese estado.</p>`;
                return;
            }
            listaSolicitudes.innerHTML = solicitudes.map(function (s) {
                return `<button type="button" class="admin_sobre urgencia_${htmlSafe(s.urgencia)}" data-solicitud="${s.id}">
                    <span class="admin_sobre_icono"><i class="fa-solid ${s.tipo === "visita" ? "fa-house-circle-check" : "fa-envelope"}"></i></span>
                    <span class="admin_sobre_texto">
                        <strong>${htmlSafe(asunto(s))}</strong>
                        <span>De ${htmlSafe(s.nombre_contacto)} · ${htmlSafe(beneficiarios(s))} · ${s.personas_afectadas} ${s.personas_afectadas === 1 ? "persona" : "personas"}</span>
                        <small>${htmlSafe(s.descripcion.slice(0, 120))}${s.descripcion.length > 120 ? "…" : ""}</small>
                    </span>
                    <span class="admin_sobre_meta">
                        <span class="admin_chip urgencia_chip_${htmlSafe(s.urgencia)}">Urgencia ${htmlSafe((T.urgencia[s.urgencia] || "").toLowerCase())}</span>
                        <span class="admin_chip">${htmlSafe(T.estado[s.estado] || s.estado)}</span>
                        <small>${htmlSafe(fecha(s.creada_en, true))}</small>
                    </span>
                </button>`;
            }).join("");
        } catch (error) {
            listaSolicitudes.innerHTML = "";
            mostrarMensaje("mensaje-solicitudes", textoError(error), "error");
        }
    }

    function renderizarCarta(s) {
        const esVisita = s.tipo === "visita";
        const filas = [
            ["Tipo", esVisita ? "Visita a vivienda" : "Solicitud de ayuda"],
            [esVisita ? "Motivo" : "Categoría", esVisita ? T.motivo[s.motivo_visita] : T.categoria[s.categoria]],
            ["Urgencia", T.urgencia[s.urgencia]],
            ["Beneficiarios", beneficiarios(s)],
            ["Personas", String(s.personas_afectadas)],
            ["Dirección o sector", s.direccion]
        ];
        if (esVisita && s.fecha_visita_preferida) {
            filas.push(["Fecha preferida", `${fechaLarga(s.fecha_visita_preferida)}, en la ${T.franja[s.franja_horaria] || ""}`]);
        }
        filas.push(["Contacto", `${s.nombre_contacto} · Tel. ${s.telefono_contacto}`], ["Cuenta SIGRE", s.cuenta_email]);

        const ubicacion = s.latitud != null
            ? `<tr><th>Ubicación</th><td><a href="https://www.google.com/maps?q=${s.latitud},${s.longitud}" target="_blank" rel="noopener noreferrer">Ver en el mapa <i class="fa-solid fa-arrow-up-right-from-square"></i></a></td></tr>`
            : "";
        const telefono = String(s.telefono_contacto || "").replace(/[^0-9+]/g, "");

        contenidoCarta.innerHTML = `
            <header class="admin_carta_cabecera">
                <div><strong>SIGRE</strong><span>Sistema de Gestión de Riesgos y Emergencias · Montería, Córdoba</span></div>
                <div class="admin_carta_radicado"><strong>Radicado N.° SIGRE-${String(s.id).padStart(5, "0")}</strong><span>${htmlSafe(fecha(s.creada_en, true))}</span></div>
            </header>
            <p>Montería, ${htmlSafe(fechaCarta(s.creada_en))}</p>
            <p>Señores<br><strong>Equipo de atención de emergencias</strong><br>Montería, Córdoba</p>
            <p id="carta-asunto"><strong>Asunto: ${htmlSafe(asunto(s))} (urgencia ${htmlSafe((T.urgencia[s.urgencia] || "").toLowerCase())})</strong></p>
            <p>Respetados señores:</p>
            <p>Por medio de la presente, <strong>${htmlSafe(s.nombre_contacto)}</strong> solicita ${esVisita ? "una visita del equipo a la vivienda ubicada en" : "apoyo en"}
               <strong>${htmlSafe(s.direccion)}</strong>, en beneficio de ${htmlSafe(aQuien(s))},
               situación que afecta a ${s.personas_afectadas} ${s.personas_afectadas === 1 ? "persona" : "personas"}.</p>
            <blockquote>${htmlSafe(s.descripcion)}</blockquote>
            <table class="admin_carta_datos">
                ${filas.map(function (f) { return `<tr><th>${htmlSafe(f[0])}</th><td>${htmlSafe(f[1] || "—")}</td></tr>`; }).join("")}
                ${ubicacion}
            </table>
            <p class="admin_carta_nota">El solicitante autorizó que esta información se comparta con el equipo responsable de atender la solicitud.</p>
            <p>Atentamente,</p>
            <p class="admin_carta_firma"><strong>${htmlSafe(s.nombre_contacto)}</strong><br>
               <a href="tel:${htmlSafe(telefono)}">Tel. ${htmlSafe(s.telefono_contacto)}</a> · ${htmlSafe(s.cuenta_email)}</p>`;

        estadoCarta.value = s.estado;
        document.getElementById("carta-adjunto").hidden = !s.adjunto_mime;

        // El correo lleva un resumen; el PDF se descarga y se adjunta a mano
        // (los navegadores no permiten adjuntar archivos desde un enlace mailto).
        const cuerpo = [
            "Cordial saludo,", "",
            `Remito la solicitud SIGRE-${String(s.id).padStart(5, "0")}: ${asunto(s)} (urgencia ${(T.urgencia[s.urgencia] || "").toLowerCase()}).`,
            `Solicitante: ${s.nombre_contacto} · Tel. ${s.telefono_contacto}`,
            `Dirección: ${s.direccion}`,
            `Beneficiarios: ${beneficiarios(s)} · ${s.personas_afectadas} personas`, "",
            "Adjunto la carta completa en PDF.", "", "Atentamente,"
        ].join("\n");
        document.getElementById("carta-correo").href =
            `mailto:?subject=${encodeURIComponent(`SIGRE-${String(s.id).padStart(5, "0")} · ${asunto(s)}`)}&body=${encodeURIComponent(cuerpo)}`;
    }

    function abrirCarta(id) {
        solicitudAbierta = solicitudes.find(function (s) { return s.id === id; });
        if (!solicitudAbierta) return;
        mostrarMensaje("mensaje-carta", "");
        renderizarCarta(solicitudAbierta);
        ventanaCarta.hidden = false;
        document.body.classList.add("admin_modal_abierto");
        document.getElementById("carta-cerrar").focus();
    }

    function cerrarCarta() {
        ventanaCarta.hidden = true;
        document.body.classList.remove("admin_modal_abierto");
        solicitudAbierta = null;
    }

    listaSolicitudes.addEventListener("click", function (evento) {
        const sobre = evento.target.closest("[data-solicitud]");
        if (sobre) abrirCarta(Number(sobre.dataset.solicitud));
    });
    filtroSolicitudes.addEventListener("change", cargarSolicitudes);
    document.getElementById("carta-cerrar").addEventListener("click", cerrarCarta);
    ventanaCarta.addEventListener("click", function (evento) { if (evento.target === ventanaCarta) cerrarCarta(); });
    document.addEventListener("keydown", function (evento) { if (evento.key === "Escape" && !ventanaCarta.hidden) cerrarCarta(); });

    estadoCarta.addEventListener("change", async function () {
        const s = solicitudAbierta;
        if (!s) return;
        const anterior = s.estado;
        estadoCarta.disabled = true;
        try {
            await llamarApi(`/api/admin/solicitudes/${s.id}/estado`, { method: "POST", body: JSON.stringify({ estado: estadoCarta.value }) });
            s.estado = estadoCarta.value;
            mostrarMensaje("mensaje-carta", `Estado actualizado a "${T.estado[s.estado]}". La persona lo verá en "Mis solicitudes".`, "exito");
            cargarSolicitudes();
        } catch (error) {
            estadoCarta.value = anterior;
            mostrarMensaje("mensaje-carta", textoError(error), "error");
        } finally {
            estadoCarta.disabled = false;
        }
    });

    document.getElementById("carta-descargar").addEventListener("click", async function () {
        if (!solicitudAbierta) return;
        try {
            await descargar(`/api/admin/solicitudes/${solicitudAbierta.id}/carta`, `SIGRE-solicitud-${String(solicitudAbierta.id).padStart(5, "0")}.pdf`);
            mostrarMensaje("mensaje-carta", "Carta descargada. Para enviarla, pulsa \"Enviar por correo\" y adjunta el PDF.", "exito");
        } catch (error) {
            mostrarMensaje("mensaje-carta", textoError(error), "error");
        }
    });

    document.getElementById("carta-adjunto").addEventListener("click", async function () {
        if (!solicitudAbierta) return;
        const extension = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf" }[solicitudAbierta.adjunto_mime] || "bin";
        try {
            await descargar(`/api/admin/solicitudes/${solicitudAbierta.id}/adjunto`, `solicitud-${solicitudAbierta.id}-adjunto.${extension}`);
        } catch (error) {
            mostrarMensaje("mensaje-carta", textoError(error), "error");
        }
    });

    A.registrarSeccion("solicitudes", cargarSolicitudes);

    /* =================== Emergencias =================== */

    const listaEmergencias = document.getElementById("lista-emergencias-admin");
    const formEmergencia = document.getElementById("formulario-emergencia");

    async function cargarEmergencias() {
        listaEmergencias.innerHTML = `<p class="admin_vacio">Cargando emergencias...</p>`;
        try {
            const emergencias = await llamarApi("/api/admin/emergencias");
            mostrarMensaje("mensaje-emergencias", "");
            if (!emergencias.length) {
                listaEmergencias.innerHTML = `<p class="admin_vacio">No hay emergencias registradas. La tarjeta del inicio dirá "Sin emergencias activas".</p>`;
                return;
            }
            listaEmergencias.innerHTML = emergencias.map(function (e) {
                const activa = e.estado === "activa";
                const lugar = [e.sector, e.municipio, e.departamento].filter(Boolean).join(", ");
                return `<article class="admin_centro ${activa ? "" : "cerrado"}">
                    <span class="admin_centro_icono nivel_${htmlSafe(e.nivel_riesgo)}"><i class="fa-solid fa-triangle-exclamation"></i></span>
                    <div class="admin_centro_datos">
                        <div class="admin_centro_cabecera">
                            <h4>${htmlSafe(e.tipo)}</h4>
                            <span class="admin_chip ${activa ? "activo" : "cerrado"}">${activa ? "Activa" : "Finalizada"}</span>
                            <span class="admin_chip">Riesgo ${htmlSafe((T.nivel[e.nivel_riesgo] || "").toLowerCase())}</span>
                        </div>
                        <p class="admin_centro_tipo"><i class="fa-solid fa-location-dot"></i> ${htmlSafe(lugar)}</p>
                        <p class="admin_centro_tipo">${htmlSafe(e.descripcion)}</p>
                        <p class="admin_centro_meta">Publicada ${htmlSafe(fecha(e.creada_en, true))}${e.finalizada_en ? " · Finalizada " + htmlSafe(fecha(e.finalizada_en, true)) : ""}</p>
                    </div>
                    ${activa ? `<div class="admin_centro_acciones"><button type="button" class="admin_boton_secundario" data-finalizar="${e.id}"><i class="fa-solid fa-circle-check"></i> Finalizar</button></div>` : ""}
                </article>`;
            }).join("");
        } catch (error) {
            listaEmergencias.innerHTML = "";
            mostrarMensaje("mensaje-emergencias", textoError(error), "error");
        }
    }

    document.getElementById("boton-nueva-emergencia").addEventListener("click", function () {
        formEmergencia.hidden = false;
        mostrarMensaje("mensaje-formulario-emergencia", "");
        formEmergencia.tipo.focus();
    });
    document.getElementById("cancelar-emergencia").addEventListener("click", function () {
        formEmergencia.reset();
        formEmergencia.hidden = true;
    });

    formEmergencia.addEventListener("submit", async function (evento) {
        evento.preventDefault();
        const datos = Object.fromEntries(new FormData(formEmergencia));
        Object.keys(datos).forEach(function (k) { datos[k] = String(datos[k]).trim(); });
        if (datos.tipo.length < 3) return mostrarMensaje("mensaje-formulario-emergencia", "Escribe el tipo de emergencia.", "error");
        if (datos.descripcion.length < 10) return mostrarMensaje("mensaje-formulario-emergencia", "Describe la emergencia (mínimo 10 caracteres).", "error");
        if (datos.alcance !== "departamento" && !datos.municipio) return mostrarMensaje("mensaje-formulario-emergencia", "Escribe el municipio afectado.", "error");
        if (datos.alcance === "sector" && !datos.sector) return mostrarMensaje("mensaje-formulario-emergencia", "Escribe el sector o barrio afectado.", "error");
        if (!window.confirm(`¿Publicar "${datos.tipo}" como emergencia activa? La verá toda la comunidad en el inicio.`)) return;
        try {
            await llamarApi("/api/admin/emergencias", { method: "POST", body: JSON.stringify(datos) });
            formEmergencia.reset();
            formEmergencia.hidden = true;
            mostrarMensaje("mensaje-emergencias", "Emergencia publicada. Ya aparece en el inicio de la comunidad.", "exito");
            cargarEmergencias();
        } catch (error) {
            mostrarMensaje("mensaje-formulario-emergencia", textoError(error), "error");
        }
    });

    listaEmergencias.addEventListener("click", async function (evento) {
        const boton = evento.target.closest("[data-finalizar]");
        if (!boton || !window.confirm("¿Finalizar esta emergencia? Dejará de mostrarse en el inicio.")) return;
        try {
            await llamarApi(`/api/admin/emergencias/${boton.dataset.finalizar}/finalizar`, { method: "POST" });
            mostrarMensaje("mensaje-emergencias", "Emergencia finalizada.", "exito");
            cargarEmergencias();
        } catch (error) {
            mostrarMensaje("mensaje-emergencias", textoError(error), "error");
        }
    });

    A.registrarSeccion("emergencias", cargarEmergencias);

    /* =================== Jornadas =================== */

    const listaJornadas = document.getElementById("lista-jornadas-admin");
    const formJornada = document.getElementById("formulario-jornada");
    const sugerenciasJornada = document.getElementById("sugerencias-jornada");
    const textoUbicacionJornada = document.getElementById("texto-ubicacion-jornada");
    const botonGuardarJornada = formJornada.querySelector('button[type="submit"]');
    let jornadasAdmin = [];
    let jornadaEditando = null;

    async function cargarJornadas() {
        listaJornadas.innerHTML = `<p class="admin_vacio">Cargando jornadas...</p>`;
        try {
            const jornadas = await llamarApi("/api/jornadas?todas=1");
            jornadasAdmin = jornadas;
            mostrarMensaje("mensaje-jornadas", "");
            if (!jornadas.length) {
                listaJornadas.innerHTML = `<p class="admin_vacio">Aún no hay jornadas publicadas desde el panel.</p>`;
                return;
            }
            const ahora = Date.now();
            listaJornadas.innerHTML = jornadas.map(function (j) {
                const pasada = new Date(j.fecha_inicio).getTime() < ahora;
                const cancelada = j.estado === "cancelada";
                return `<article class="admin_centro ${pasada || cancelada ? "cerrado" : ""}">
                    <span class="admin_centro_icono"><i class="fa-solid fa-calendar-check"></i></span>
                    <div class="admin_centro_datos">
                        <div class="admin_centro_cabecera">
                            <h4>${htmlSafe(j.nombre)}</h4>
                            <span class="admin_chip ${cancelada ? "activo" : pasada ? "cerrado" : "abierto"}">${cancelada ? "Cancelada" : pasada ? "Realizada" : "Publicada"}</span>
                        </div>
                        <p class="admin_centro_tipo">${htmlSafe(T.jornada[j.categoria])} · ${htmlSafe(fecha(j.fecha_inicio, true))} · ${htmlSafe(j.lugar)}</p>
                        <p class="admin_centro_tipo">${htmlSafe(j.descripcion)}</p>
                        <p class="admin_centro_tipo"><i class="fa-solid fa-user-group"></i> <strong>${j.participantes || 0}</strong> persona${j.participantes === 1 ? "" : "s"} inscrita${j.participantes === 1 ? "" : "s"}</p>
                        <div class="admin_participantes" id="participantes-jornada-${j.id}" hidden></div>
                    </div>
                    <div class="admin_centro_acciones">
                        ${j.participantes ? `<button type="button" class="admin_boton_secundario" data-jornada-participantes="${j.id}" aria-expanded="false" aria-controls="participantes-jornada-${j.id}">
                            <i class="fa-solid fa-users"></i> Ver participantes</button>` : ""}
                        ${pasada ? "" : `<button type="button" class="admin_boton_secundario" data-jornada-editar="${j.id}"><i class="fa-solid fa-pen"></i> Editar</button>`}
                        ${pasada ? "" : `<button type="button" class="admin_boton_secundario" data-jornada-estado="${j.id}" data-nuevo="${cancelada ? "publicada" : "cancelada"}">
                            <i class="fa-solid ${cancelada ? "fa-rotate-left" : "fa-ban"}"></i> ${cancelada ? "Publicar de nuevo" : "Cancelar"}</button>`}
                        <button type="button" class="admin_boton_secundario peligro" data-jornada-eliminar="${j.id}"><i class="fa-solid fa-trash"></i> Eliminar</button>
                    </div>
                </article>`;
            }).join("");
        } catch (error) {
            listaJornadas.innerHTML = "";
            mostrarMensaje("mensaje-jornadas", textoError(error), "error");
        }
    }

    function fijarUbicacionJornada(lugar) {
        formJornada.latitud.value = lugar ? lugar.lat : "";
        formJornada.longitud.value = lugar ? lugar.lon : "";
        textoUbicacionJornada.textContent = lugar
            ? "Ubicación: " + lugar.nombre.split(",").slice(0, 3).join(",")
            : "Sin ubicación: el botón \"Ver ubicación\" no aparecerá.";
        sugerenciasJornada.hidden = true;
    }

    // Hora de Colombia (UTC-5, sin horario de verano) en el formato de datetime-local.
    function fechaLocalColombia(iso) {
        return new Date(new Date(iso).getTime() - 5 * 3600000).toISOString().slice(0, 16);
    }

    function abrirFormularioJornada(jornada) {
        formJornada.reset();
        jornadaEditando = jornada ? jornada.id : null;
        fijarUbicacionJornada(null);
        formJornada.fecha_inicio.min = fechaLocalColombia(new Date().toISOString());
        if (jornada) {
            formJornada.nombre.value = jornada.nombre;
            formJornada.categoria.value = jornada.categoria;
            formJornada.fecha_inicio.value = fechaLocalColombia(jornada.fecha_inicio);
            formJornada.lugar.value = jornada.lugar;
            formJornada.descripcion.value = jornada.descripcion;
            if (jornada.latitud != null) {
                formJornada.latitud.value = jornada.latitud;
                formJornada.longitud.value = jornada.longitud;
                textoUbicacionJornada.textContent = "Ubicación guardada en el mapa. Búscala de nuevo si cambiaste el lugar.";
            }
        }
        botonGuardarJornada.innerHTML = jornada
            ? `<i class="fa-solid fa-floppy-disk"></i> Guardar cambios`
            : `<i class="fa-solid fa-calendar-plus"></i> Publicar jornada`;
        formJornada.hidden = false;
        mostrarMensaje("mensaje-formulario-jornada", jornada
            ? `Editando "${jornada.nombre}". Si cambias la fecha o el lugar, se avisará a las personas inscritas.`
            : "");
        formJornada.scrollIntoView({ behavior: "smooth", block: "start" });
        formJornada.nombre.focus({ preventScroll: true });
    }

    function cerrarFormularioJornada() {
        formJornada.hidden = true;
        jornadaEditando = null;
    }

    document.getElementById("boton-nueva-jornada").addEventListener("click", function () { abrirFormularioJornada(null); });
    document.getElementById("cancelar-jornada").addEventListener("click", cerrarFormularioJornada);

    document.getElementById("ubicar-jornada").addEventListener("click", async function () {
        const lugar = formJornada.lugar.value.trim();
        if (lugar.length < 3) return mostrarMensaje("mensaje-formulario-jornada", "Primero escribe el lugar.", "error");
        sugerenciasJornada.hidden = false;
        sugerenciasJornada.innerHTML = `<li class="admin_sugerencia_aviso">Buscando...</li>`;
        try {
            const respuesta = await fetch(`${API_BASE}/api/rutas/buscar?q=${encodeURIComponent(lugar)}`);
            const resultados = await respuesta.json();
            if (!respuesta.ok) throw new Error(resultados.error || "No se pudo buscar el lugar.");
            if (!resultados.length) {
                sugerenciasJornada.innerHTML = `<li class="admin_sugerencia_aviso">No se encontró en Montería. Prueba con un lugar conocido cercano.</li>`;
                return;
            }
            sugerenciasJornada.innerHTML = "";
            resultados.forEach(function (resultado) {
                const item = document.createElement("li");
                const boton = document.createElement("button");
                boton.type = "button";
                boton.innerHTML = '<i class="fa-solid fa-location-dot"></i>';
                boton.appendChild(document.createTextNode(" " + resultado.nombre));
                boton.addEventListener("click", function () { fijarUbicacionJornada(resultado); });
                item.appendChild(boton);
                sugerenciasJornada.appendChild(item);
            });
        } catch (error) {
            sugerenciasJornada.innerHTML = `<li class="admin_sugerencia_aviso">${htmlSafe(textoError(error))}</li>`;
        }
    });

    formJornada.addEventListener("submit", async function (evento) {
        evento.preventDefault();
        const datos = Object.fromEntries(new FormData(formJornada));
        Object.keys(datos).forEach(function (k) { datos[k] = String(datos[k]).trim(); });
        if (datos.nombre.length < 3) return mostrarMensaje("mensaje-formulario-jornada", "Escribe el nombre de la jornada.", "error");
        if (!datos.fecha_inicio) return mostrarMensaje("mensaje-formulario-jornada", "Elige la fecha y la hora.", "error");
        if (datos.lugar.length < 3) return mostrarMensaje("mensaje-formulario-jornada", "Escribe el lugar.", "error");
        if (datos.descripcion.length < 10) return mostrarMensaje("mensaje-formulario-jornada", "Describe la jornada (mínimo 10 caracteres).", "error");
        datos.latitud = datos.latitud || null;
        datos.longitud = datos.longitud || null;
        const editando = jornadaEditando;
        try {
            await llamarApi(editando ? `/api/admin/jornadas/${editando}` : "/api/admin/jornadas",
                { method: "POST", body: JSON.stringify(datos) });
            cerrarFormularioJornada();
            mostrarMensaje("mensaje-jornadas", editando
                ? "Cambios guardados. La jornada ya se ve actualizada en el módulo Jornadas."
                : "Jornada publicada. Ya aparece en el módulo Jornadas.", "exito");
            cargarJornadas();
        } catch (error) {
            mostrarMensaje("mensaje-formulario-jornada", textoError(error), "error");
        }
    });

    async function alternarParticipantes(boton) {
        const id = boton.dataset.jornadaParticipantes;
        const caja = document.getElementById(`participantes-jornada-${id}`);
        const abrir = caja.hidden;
        caja.hidden = !abrir;
        boton.setAttribute("aria-expanded", String(abrir));
        boton.innerHTML = abrir
            ? `<i class="fa-solid fa-chevron-up"></i> Ocultar participantes`
            : `<i class="fa-solid fa-users"></i> Ver participantes`;
        if (!abrir) return;
        caja.innerHTML = `<p class="admin_vacio">Cargando participantes...</p>`;
        try {
            const personas = await llamarApi(`/api/jornadas/${id}/participantes`);
            caja.innerHTML = personas.length ? `<ol class="admin_lista_participantes">${personas.map(function (p) {
                return `<li>
                    <strong>${htmlSafe(p.nombre)}</strong>
                    ${p.email ? `<a href="mailto:${htmlSafe(p.email)}">${htmlSafe(p.email)}</a>` : ""}
                    ${p.telefono ? `<a href="tel:${htmlSafe(p.telefono)}"><i class="fa-solid fa-phone"></i> ${htmlSafe(p.telefono)}</a>` : `<span>Sin teléfono</span>`}
                    <span>Inscrita el ${htmlSafe(fecha(p.inscrito_en, true))}</span>
                </li>`;
            }).join("")}</ol>` : `<p class="admin_vacio">Nadie se ha inscrito todavía.</p>`;
        } catch (error) {
            caja.innerHTML = `<p class="admin_vacio">${htmlSafe(textoError(error))}</p>`;
        }
    }

    listaJornadas.addEventListener("click", async function (evento) {
        const verParticipantes = evento.target.closest("[data-jornada-participantes]");
        if (verParticipantes) return alternarParticipantes(verParticipantes);
        const editar = evento.target.closest("[data-jornada-editar]");
        if (editar) {
            const jornada = jornadasAdmin.find(function (j) { return String(j.id) === editar.dataset.jornadaEditar; });
            if (jornada) abrirFormularioJornada(jornada);
            return;
        }
        const estado = evento.target.closest("[data-jornada-estado]");
        const eliminar = evento.target.closest("[data-jornada-eliminar]");
        try {
            if (estado) {
                await llamarApi(`/api/admin/jornadas/${estado.dataset.jornadaEstado}/estado`, { method: "POST", body: JSON.stringify({ estado: estado.dataset.nuevo }) });
                mostrarMensaje("mensaje-jornadas", estado.dataset.nuevo === "cancelada" ? "Jornada cancelada: ya no se muestra a la comunidad." : "Jornada publicada de nuevo.", "exito");
                cargarJornadas();
            }
            if (eliminar && window.confirm("¿Eliminar esta jornada? No se puede deshacer.")) {
                await llamarApi(`/api/admin/jornadas/${eliminar.dataset.jornadaEliminar}/eliminar`, { method: "POST" });
                mostrarMensaje("mensaje-jornadas", "Jornada eliminada.", "exito");
                cargarJornadas();
            }
        } catch (error) {
            mostrarMensaje("mensaje-jornadas", textoError(error), "error");
        }
    });

    A.registrarSeccion("jornadas", cargarJornadas);

    /* =================== Directorio =================== */

    const listaDirectorio = document.getElementById("lista-directorio-admin");
    const formEntidad = document.getElementById("formulario-entidad");
    let entidades = [];
    let entidadEditando = null;

    async function cargarDirectorio() {
        listaDirectorio.innerHTML = `<p class="admin_vacio">Cargando directorio...</p>`;
        try {
            entidades = await llamarApi("/api/directorio");
            mostrarMensaje("mensaje-directorio", "");
            if (!entidades.length) {
                listaDirectorio.innerHTML = `<p class="admin_vacio">El directorio está vacío.</p>`;
                return;
            }
            listaDirectorio.innerHTML = entidades.map(function (e) {
                const contacto = [e.telefono ? "Tel. " + e.telefono : "", e.direccion, e.web].filter(Boolean).join(" · ");
                return `<article class="admin_centro">
                    <span class="admin_centro_icono grupo_${htmlSafe(e.grupo)}"><i class="fa-solid fa-address-book"></i></span>
                    <div class="admin_centro_datos">
                        <div class="admin_centro_cabecera"><h4>${htmlSafe(e.nombre)}</h4><span class="admin_chip">${htmlSafe(T.grupo[e.grupo])}</span></div>
                        ${e.detalle ? `<p class="admin_centro_tipo">${htmlSafe(e.detalle)}</p>` : ""}
                        <p class="admin_centro_meta">${htmlSafe(contacto)}</p>
                    </div>
                    <div class="admin_centro_acciones">
                        <button type="button" class="admin_boton_secundario" data-entidad-editar="${e.id}"><i class="fa-solid fa-pen"></i> Editar</button>
                        <button type="button" class="admin_boton_secundario peligro" data-entidad-eliminar="${e.id}"><i class="fa-solid fa-trash"></i> Eliminar</button>
                    </div>
                </article>`;
            }).join("");
        } catch (error) {
            listaDirectorio.innerHTML = "";
            mostrarMensaje("mensaje-directorio", textoError(error), "error");
        }
    }

    function abrirFormularioEntidad(entidad) {
        entidadEditando = entidad || null;
        formEntidad.reset();
        document.getElementById("titulo-formulario-entidad").textContent = entidad ? "Editar: " + entidad.nombre : "Nueva entidad";
        if (entidad) {
            ["nombre", "grupo", "telefono", "orden", "detalle", "direccion", "web"].forEach(function (campo) {
                formEntidad[campo].value = entidad[campo] == null ? "" : entidad[campo];
            });
        }
        mostrarMensaje("mensaje-formulario-entidad", "");
        formEntidad.hidden = false;
        formEntidad.scrollIntoView({ behavior: "smooth", block: "start" });
        formEntidad.nombre.focus({ preventScroll: true });
    }

    document.getElementById("boton-nueva-entidad").addEventListener("click", function () { abrirFormularioEntidad(null); });
    document.getElementById("cancelar-entidad").addEventListener("click", function () { formEntidad.hidden = true; });

    formEntidad.addEventListener("submit", async function (evento) {
        evento.preventDefault();
        const datos = Object.fromEntries(new FormData(formEntidad));
        Object.keys(datos).forEach(function (k) { datos[k] = String(datos[k]).trim(); });
        datos.orden = datos.orden === "" ? 100 : Number(datos.orden);
        if (datos.nombre.length < 2) return mostrarMensaje("mensaje-formulario-entidad", "Escribe el nombre de la entidad.", "error");
        if (!datos.telefono && !datos.direccion && !datos.web) return mostrarMensaje("mensaje-formulario-entidad", "Agrega al menos un teléfono, una dirección o un sitio web.", "error");
        if (datos.web && !/^https:\/\//.test(datos.web)) return mostrarMensaje("mensaje-formulario-entidad", "El sitio web debe empezar por https://", "error");
        try {
            await llamarApi(entidadEditando ? `/api/admin/directorio/${entidadEditando.id}` : "/api/admin/directorio", { method: "POST", body: JSON.stringify(datos) });
            formEntidad.hidden = true;
            mostrarMensaje("mensaje-directorio", entidadEditando ? "Entidad actualizada." : "Entidad agregada al directorio.", "exito");
            cargarDirectorio();
        } catch (error) {
            mostrarMensaje("mensaje-formulario-entidad", textoError(error), "error");
        }
    });

    listaDirectorio.addEventListener("click", async function (evento) {
        const editar = evento.target.closest("[data-entidad-editar]");
        const eliminar = evento.target.closest("[data-entidad-eliminar]");
        if (editar) abrirFormularioEntidad(entidades.find(function (e) { return e.id === Number(editar.dataset.entidadEditar); }));
        if (eliminar) {
            const entidad = entidades.find(function (e) { return e.id === Number(eliminar.dataset.entidadEliminar); });
            if (!entidad || !window.confirm(`¿Quitar "${entidad.nombre}" del directorio?`)) return;
            try {
                await llamarApi(`/api/admin/directorio/${entidad.id}/eliminar`, { method: "POST" });
                mostrarMensaje("mensaje-directorio", "Entidad eliminada.", "exito");
                cargarDirectorio();
            } catch (error) {
                mostrarMensaje("mensaje-directorio", textoError(error), "error");
            }
        }
    });

    A.registrarSeccion("directorio", cargarDirectorio);
})();
