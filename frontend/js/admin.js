/* SIGRE · Panel de administración (rol autoridad)
   El servidor comprueba el rol en cada operación; esta página solo decide qué mostrar. */
(() => {
    const API_BASE = window.SIGRE_API;   // js/config.js
    const ROLES = { ciudadano: "Ciudadano", voluntario: "Voluntario", autoridad: "Autoridad / entidad" };

    const acceso = document.getElementById("admin-acceso");
    const panel = document.getElementById("admin-panel");
    const cargadas = {};
    let centros = [];

    /* ---------- Utilidades ---------- */

    function htmlSafe(valor) {
        return String(valor == null ? "" : valor).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    }

    function leerToken() {
        try {
            return localStorage.getItem("sigre_token");
        } catch (error) {
            return null;
        }
    }

    function fecha(iso, conHora) {
        const valor = new Date(iso);
        if (Number.isNaN(valor.getTime())) return "";
        return valor.toLocaleString("es-CO", conHora
            ? { dateStyle: "medium", timeStyle: "short" }
            : { dateStyle: "medium" });
    }

    function mostrarMensaje(id, texto, tipo) {
        const elemento = document.getElementById(id);
        elemento.textContent = texto;
        elemento.className = "admin_mensaje" + (tipo ? " " + tipo : "");
    }

    async function llamarApi(ruta, opciones) {
        const configuracion = Object.assign({}, opciones);
        configuracion.headers = Object.assign(
            { Authorization: "Bearer " + leerToken() },
            configuracion.body ? { "Content-Type": "application/json" } : {}
        );
        const respuesta = await fetch(API_BASE + ruta, configuracion);
        let datos = null;
        try {
            datos = await respuesta.json();
        } catch (error) { /* respuesta sin JSON */ }
        if (respuesta.status === 401 || respuesta.status === 422) {
            mostrarAcceso("Tu sesión expiró. Inicia sesión de nuevo.", true);
            throw new Error("Tu sesión expiró.");
        }
        if (!respuesta.ok) {
            throw new Error((datos && datos.error) || "No se pudo completar la operación.");
        }
        return datos;
    }

    function textoError(error) {
        return error instanceof TypeError
            ? "No se pudo conectar con el servidor de SIGRE. Verifica que Flask esté en ejecución."
            : error.message;
    }

    function mostrarAcceso(texto, conLogin) {
        panel.hidden = true;
        acceso.hidden = false;
        acceso.innerHTML = "";
        const icono = document.createElement("i");
        icono.className = "fa-solid fa-lock";
        const parrafo = document.createElement("p");
        parrafo.textContent = texto;
        acceso.append(icono, parrafo);
        const enlace = document.createElement("a");
        enlace.className = "admin_boton";
        enlace.href = conLogin ? "login.html" : "dashboard.html";
        enlace.textContent = conLogin ? "Iniciar sesión" : "Ir a la vista ciudadana";
        acceso.appendChild(enlace);
    }

    /* ---------- Pestañas ---------- */

    const pestanas = document.querySelectorAll(".admin_pestana");
    // Secciones que registra js/admin_contenidos.js (solicitudes, emergencias, jornadas, directorio).
    const cargadoresExternos = {};

    function abrirSeccion(nombre) {
        if (!document.getElementById("seccion-" + nombre)) nombre = "resumen";
        pestanas.forEach(function (pestana) {
            const activa = pestana.dataset.seccion === nombre;
            pestana.classList.toggle("activa", activa);
            pestana.setAttribute("aria-selected", activa ? "true" : "false");
            document.getElementById("seccion-" + pestana.dataset.seccion).hidden = !activa;
        });
        history.replaceState(null, "", "#" + nombre);
        if (!cargadas[nombre]) {
            cargadas[nombre] = true;
            const cargador = { usuarios: cargarUsuarios, centros: cargarCentros, desaparecidos: cargarDesaparecidos }[nombre]
                || cargadoresExternos[nombre];
            if (cargador) cargador();
        }
    }

    pestanas.forEach(function (pestana) {
        pestana.addEventListener("click", function () { abrirSeccion(pestana.dataset.seccion); });
    });
    // Una notificación puede llevar a una sección (#solicitudes): se abre con datos frescos.
    window.addEventListener("hashchange", function () {
        const nombre = window.location.hash.slice(1);
        if (panel.hidden || !nombre) return;
        cargadas[nombre] = false;
        abrirSeccion(nombre);
    });

    /* ---------- Resumen ---------- */

    function renderizarResumen(r) {
        const tarjetas = [
            { seccion: "usuarios", icono: "fa-users", color: "morado", valor: r.usuarios_total, titulo: "Usuarios registrados",
              detalle: `${r.ciudadanos} ciudadanos · ${r.voluntarios} voluntarios · ${r.autoridades} autoridades` },
            { seccion: "desaparecidos", icono: "fa-person-circle-question", color: "rojo", valor: r.desaparecidos_activos, titulo: "Desaparecidos activos",
              detalle: `${r.desaparecidos_encontrados} marcados como encontrados` },
            { seccion: "centros", icono: "fa-house-chimney", color: "verde", valor: r.centros_abiertos, titulo: "Centros abiertos",
              detalle: `${r.centros_total} registrados en total` },
            { seccion: "solicitudes", icono: "fa-hand-holding-heart", color: "naranja", valor: r.solicitudes_pendientes, titulo: "Solicitudes de ayuda pendientes",
              detalle: "Enviadas desde el módulo Solicitar ayuda" }
        ];
        const contenedor = document.getElementById("admin-estadisticas");
        contenedor.innerHTML = tarjetas.map(function (t) {
            const etiqueta = t.seccion ? "button" : "div";
            return `<${etiqueta} ${t.seccion ? `type="button" data-ir="${t.seccion}"` : ""} class="admin_estadistica ${t.color}">
                <span class="admin_estadistica_icono"><i class="fa-solid ${t.icono}"></i></span>
                <strong>${Number(t.valor).toLocaleString("es-CO")}</strong>
                <span class="admin_estadistica_titulo">${t.titulo}</span>
                <small>${htmlSafe(t.detalle)}</small>
            </${etiqueta}>`;
        }).join("");
        contenedor.querySelectorAll("[data-ir]").forEach(function (boton) {
            boton.addEventListener("click", function () { abrirSeccion(boton.dataset.ir); });
        });
    }

    /* ---------- Usuarios ---------- */

    const tablaUsuarios = document.getElementById("tabla-usuarios");
    let temporizadorBusqueda = null;

    async function cargarUsuarios() {
        const texto = document.getElementById("buscar-usuario").value.trim();
        tablaUsuarios.innerHTML = `<tr><td colspan="5" class="admin_vacio">Cargando usuarios...</td></tr>`;
        try {
            const usuarios = await llamarApi("/api/admin/usuarios" + (texto ? "?q=" + encodeURIComponent(texto) : ""));
            mostrarMensaje("mensaje-usuarios", "");
            if (!usuarios.length) {
                tablaUsuarios.innerHTML = `<tr><td colspan="5" class="admin_vacio">No hay usuarios que coincidan.</td></tr>`;
                return;
            }
            tablaUsuarios.innerHTML = usuarios.map(function (u) {
                const opciones = Object.keys(ROLES).map(function (rol) {
                    return `<option value="${rol}" ${rol === u.rol ? "selected" : ""}>${ROLES[rol]}</option>`;
                }).join("");
                return `<tr>
                    <td data-titulo="Nombre"><strong>${htmlSafe(u.nombre || "Sin nombre")}</strong>${u.es_yo ? ' <span class="admin_chip">Tú</span>' : ""}</td>
                    <td data-titulo="Correo">${htmlSafe(u.email)}</td>
                    <td data-titulo="Teléfono">${htmlSafe(u.telefono || "—")}</td>
                    <td data-titulo="Registro">${htmlSafe(fecha(u.creado_en))}</td>
                    <td data-titulo="Rol">
                        <select class="admin_select_rol rol_${u.rol}" data-usuario="${u.id}" data-rol="${u.rol}" data-nombre="${htmlSafe(u.nombre || u.email)}"
                            ${u.es_yo ? 'disabled title="No puedes cambiar tu propio rol"' : ""} aria-label="Rol de ${htmlSafe(u.nombre || u.email)}">${opciones}</select>
                    </td>
                </tr>`;
            }).join("");
        } catch (error) {
            tablaUsuarios.innerHTML = "";
            mostrarMensaje("mensaje-usuarios", textoError(error), "error");
        }
    }

    document.getElementById("buscar-usuario").addEventListener("input", function () {
        clearTimeout(temporizadorBusqueda);
        temporizadorBusqueda = setTimeout(cargarUsuarios, 400);
    });

    tablaUsuarios.addEventListener("change", async function (evento) {
        const select = evento.target.closest("[data-usuario]");
        if (!select) return;
        const anterior = select.dataset.rol;
        const nuevo = select.value;
        const aviso = nuevo === "autoridad"
            ? `¿Dar acceso de administrador a ${select.dataset.nombre}? Podrá ver todos los usuarios y gestionar centros y reportes.`
            : `¿Cambiar el rol de ${select.dataset.nombre} a "${ROLES[nuevo]}"?`;
        if (!window.confirm(aviso)) {
            select.value = anterior;
            return;
        }
        select.disabled = true;
        try {
            const respuesta = await llamarApi(`/api/admin/usuarios/${select.dataset.usuario}/rol`, {
                method: "POST", body: JSON.stringify({ rol: nuevo })
            });
            select.dataset.rol = nuevo;
            select.className = "admin_select_rol rol_" + nuevo;
            mostrarMensaje("mensaje-usuarios", respuesta.mensaje, "exito");
        } catch (error) {
            select.value = anterior;
            mostrarMensaje("mensaje-usuarios", textoError(error), "error");
        } finally {
            select.disabled = false;
        }
    });

    /* ---------- Centros y albergues ---------- */

    const listaCentros = document.getElementById("lista-centros-admin");
    const contenedorFormulario = document.getElementById("formulario-centro-contenedor");
    const formulario = document.getElementById("formulario-centro");
    let centroEditando = null;
    let mapaCentro = null;
    let marcadorCentro = null;

    function nivelOcupacion(centro) {
        if (!centro.capacidad) return "sin_cupos";
        const porcentaje = centro.ocupados / centro.capacidad * 100;
        if (porcentaje >= 100) return "completo";
        if (porcentaje >= 85) return "rojo";
        if (porcentaje >= 50) return "amarillo";
        return "verde";
    }

    function renderizarCentros() {
        if (!centros.length) {
            listaCentros.innerHTML = `<p class="admin_vacio">Aún no hay centros registrados. Pulsa "Nuevo centro" para agregar el primero.</p>`;
            return;
        }
        listaCentros.innerHTML = centros.map(function (c) {
            const esAcopio = c.tipo === "acopio";
            const nivel = nivelOcupacion(c);
            const porcentaje = c.capacidad ? Math.min(100, Math.round(c.ocupados / c.capacidad * 100)) : 0;
            return `<article class="admin_centro ${c.estado === "cerrado" ? "cerrado" : ""}">
                <span class="admin_centro_icono ${nivel}"><i class="fa-solid ${esAcopio ? "fa-boxes-stacked" : "fa-house-chimney"}"></i></span>
                <div class="admin_centro_datos">
                    <div class="admin_centro_cabecera">
                        <h4>${htmlSafe(c.nombre)}</h4>
                        <span class="admin_chip ${c.estado}">${c.estado === "abierto" ? "Abierto" : "Cerrado"}</span>
                    </div>
                    <p class="admin_centro_tipo">${esAcopio ? "Centro de acopio" : "Albergue"} · ${htmlSafe(c.direccion)}</p>
                    ${c.capacidad ? `<div class="admin_cupos"><span>Cupos: <strong>${c.ocupados} / ${c.capacidad}</strong></span><div class="admin_barra ${nivel}"><span style="width:${porcentaje}%"></span></div></div>` : ""}
                    ${c.necesidades ? `<p class="admin_centro_necesidades"><i class="fa-solid fa-hand-holding-heart"></i> ${htmlSafe(c.necesidades)}</p>` : ""}
                    <p class="admin_centro_meta">${c.latitud != null ? '<i class="fa-solid fa-location-dot"></i> Con ubicación en el mapa' : '<i class="fa-solid fa-triangle-exclamation"></i> Sin ubicación en el mapa'} · Actualizado ${htmlSafe(fecha(c.actualizado_en, true))}</p>
                </div>
                <div class="admin_centro_acciones">
                    <button type="button" class="admin_boton_secundario" data-inventario="${c.id}"><i class="fa-solid fa-boxes-stacked"></i> Inventario</button>
                    <button type="button" class="admin_boton_secundario" data-editar="${c.id}"><i class="fa-solid fa-pen"></i> Editar</button>
                    <button type="button" class="admin_boton_secundario peligro" data-eliminar="${c.id}"><i class="fa-solid fa-trash"></i> Eliminar</button>
                </div>
            </article>`;
        }).join("");
    }

    async function cargarCentros() {
        listaCentros.innerHTML = `<p class="admin_vacio">Cargando centros...</p>`;
        try {
            centros = await llamarApi("/api/centros");
            mostrarMensaje("mensaje-centros", "");
            renderizarCentros();
        } catch (error) {
            listaCentros.innerHTML = "";
            mostrarMensaje("mensaje-centros", textoError(error), "error");
        }
    }

    function fijarUbicacionCentro(lat, lon) {
        formulario.latitud.value = lat == null ? "" : lat.toFixed(6);
        formulario.longitud.value = lon == null ? "" : lon.toFixed(6);
        if (!mapaCentro) return;
        if (lat == null) {
            if (marcadorCentro) mapaCentro.removeLayer(marcadorCentro);
            marcadorCentro = null;
            return;
        }
        if (marcadorCentro) marcadorCentro.setLatLng([lat, lon]);
        else {
            // Marca arrastrable para ajustar la posición exacta.
            marcadorCentro = L.marker([lat, lon], { draggable: true }).addTo(mapaCentro);
            marcadorCentro.on("dragend", function () {
                const posicion = marcadorCentro.getLatLng();
                fijarUbicacionCentro(posicion.lat, posicion.lng);
            });
        }
    }

    function abrirFormularioCentro(centro) {
        centroEditando = centro || null;
        formulario.reset();
        document.getElementById("titulo-formulario-centro").textContent = centro ? `Editar: ${centro.nombre}` : "Nuevo centro";
        if (centro) {
            ["nombre", "tipo", "estado", "direccion", "capacidad", "ocupados", "telefono", "descripcion", "necesidades"].forEach(function (campo) {
                formulario[campo].value = centro[campo] == null ? "" : centro[campo];
            });
        }
        mostrarMensaje("mensaje-formulario-centro", "");
        buscadorLugar.value = "";
        sugerenciasLugar.hidden = true;
        actualizarCamposTipo();
        contenedorFormulario.hidden = false;

        if (!mapaCentro && window.L) {
            mapaCentro = L.map("mapa-centro-admin").setView([8.757, -75.884], 13);
            L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
                attribution: "&copy; OpenStreetMap contributors", maxZoom: 19
            }).addTo(mapaCentro);
            mapaCentro.on("click", function (e) { fijarUbicacionCentro(e.latlng.lat, e.latlng.lng); });
        }
        if (mapaCentro) {
            setTimeout(function () { mapaCentro.invalidateSize(); }, 50);
            if (centro && centro.latitud != null) {
                fijarUbicacionCentro(centro.latitud, centro.longitud);
                mapaCentro.setView([centro.latitud, centro.longitud], 16);
            } else {
                fijarUbicacionCentro(null, null);
                mapaCentro.setView([8.757, -75.884], 13);
            }
        }
        contenedorFormulario.scrollIntoView({ behavior: "smooth", block: "start" });
        formulario.nombre.focus({ preventScroll: true });
    }

    // Los cupos solo aplican a albergues; un centro de acopio recibe donaciones.
    function actualizarCamposTipo() {
        const esAlbergue = formulario.tipo.value === "albergue";
        formulario.querySelectorAll(".campo_cupos").forEach(function (campo) {
            campo.hidden = !esAlbergue;
        });
    }

    formulario.tipo.addEventListener("change", actualizarCamposTipo);

    function cerrarFormularioCentro() {
        contenedorFormulario.hidden = true;
        centroEditando = null;
    }

    /* Buscar el lugar en el mapa (usa la búsqueda de direcciones del módulo de rutas) */

    const buscadorLugar = document.getElementById("buscar-lugar-centro");
    const sugerenciasLugar = document.getElementById("sugerencias-lugar-centro");
    let temporizadorLugar = null;
    let consultaLugar = 0;

    function mostrarSugerenciasLugar(resultados, aviso) {
        sugerenciasLugar.innerHTML = "";
        if (aviso) {
            const item = document.createElement("li");
            item.className = "admin_sugerencia_aviso";
            item.textContent = aviso;
            sugerenciasLugar.appendChild(item);
        }
        resultados.forEach(function (lugar) {
            const item = document.createElement("li");
            const boton = document.createElement("button");
            boton.type = "button";
            boton.setAttribute("role", "option");
            boton.innerHTML = '<i class="fa-solid fa-location-dot"></i>';
            boton.appendChild(document.createTextNode(" " + lugar.nombre));
            boton.addEventListener("click", function () {
                fijarUbicacionCentro(lugar.lat, lugar.lon);
                if (mapaCentro) mapaCentro.setView([lugar.lat, lugar.lon], 17);
                buscadorLugar.value = lugar.nombre.split(",").slice(0, 2).join(",");
                sugerenciasLugar.hidden = true;
                mostrarMensaje("mensaje-formulario-centro", "Ubicación marcada. Si no es exacta, arrastra la marca o toca el punto correcto en el mapa.", "exito");
            });
            item.appendChild(boton);
            sugerenciasLugar.appendChild(item);
        });
        sugerenciasLugar.hidden = !sugerenciasLugar.children.length;
    }

    async function buscarLugar(texto) {
        if (texto.length < 3) {
            mostrarSugerenciasLugar([], "Escribe al menos 3 letras.");
            return;
        }
        const numero = ++consultaLugar;
        mostrarSugerenciasLugar([], "Buscando...");
        try {
            const respuesta = await fetch(`${API_BASE}/api/rutas/buscar?q=${encodeURIComponent(texto)}`);
            const resultados = await respuesta.json();
            if (numero !== consultaLugar) return;
            if (!respuesta.ok) throw new Error(resultados.error || "No se pudo buscar el lugar.");
            mostrarSugerenciasLugar(resultados, resultados.length ? "" : "No se encontró en Montería. Prueba con otro nombre o toca el mapa.");
        } catch (error) {
            if (numero === consultaLugar) mostrarSugerenciasLugar([], textoError(error));
        }
    }

    buscadorLugar.addEventListener("input", function () {
        clearTimeout(temporizadorLugar);
        const texto = buscadorLugar.value.trim();
        if (texto.length < 3) {
            sugerenciasLugar.hidden = true;
            return;
        }
        // Espera a que termine de escribir: el buscador de OpenStreetMap pide pocas consultas.
        temporizadorLugar = setTimeout(function () { buscarLugar(texto); }, 700);
    });

    buscadorLugar.addEventListener("keydown", function (evento) {
        if (evento.key === "Escape") sugerenciasLugar.hidden = true;
        if (evento.key === "Enter") {
            evento.preventDefault();
            const primera = sugerenciasLugar.querySelector("button");
            if (primera) primera.click();
            else buscarLugar(buscadorLugar.value.trim());
        }
    });

    document.getElementById("buscar-direccion-escrita").addEventListener("click", function () {
        const direccion = formulario.direccion.value.trim();
        if (!direccion) {
            mostrarMensaje("mensaje-formulario-centro", "Primero escribe la dirección o el sector en el formulario.", "error");
            formulario.direccion.focus();
            return;
        }
        buscadorLugar.value = direccion;
        buscarLugar(direccion);
    });

    document.getElementById("mi-ubicacion-centro").addEventListener("click", function () {
        if (!("geolocation" in navigator)) {
            mostrarMensaje("mensaje-formulario-centro", "Tu navegador no permite obtener la ubicación.", "error");
            return;
        }
        mostrarMensaje("mensaje-formulario-centro", "Obteniendo tu ubicación...");
        navigator.geolocation.getCurrentPosition(
            function (posicion) {
                fijarUbicacionCentro(posicion.coords.latitude, posicion.coords.longitude);
                if (mapaCentro) mapaCentro.setView([posicion.coords.latitude, posicion.coords.longitude], 17);
                mostrarMensaje("mensaje-formulario-centro", "Ubicación marcada con tu GPS.", "exito");
            },
            function () {
                mostrarMensaje("mensaje-formulario-centro", "No se pudo obtener tu ubicación. Revisa los permisos o busca el lugar.", "error");
            },
            { enableHighAccuracy: true, timeout: 10000 }
        );
    });

    document.addEventListener("click", function (evento) {
        if (!sugerenciasLugar.contains(evento.target) && evento.target !== buscadorLugar
            && !evento.target.closest("#buscar-direccion-escrita")) {
            sugerenciasLugar.hidden = true;
        }
    });

    document.getElementById("boton-nuevo-centro").addEventListener("click", function () { abrirFormularioCentro(null); });
    document.getElementById("cancelar-centro").addEventListener("click", cerrarFormularioCentro);
    document.getElementById("quitar-ubicacion-centro").addEventListener("click", function () { fijarUbicacionCentro(null, null); });

    formulario.addEventListener("submit", async function (evento) {
        evento.preventDefault();
        const datos = {
            nombre: formulario.nombre.value.trim(),
            tipo: formulario.tipo.value,
            estado: formulario.estado.value,
            direccion: formulario.direccion.value.trim(),
            capacidad: formulario.capacidad.value === "" ? 0 : Number(formulario.capacidad.value),
            ocupados: formulario.ocupados.value === "" ? 0 : Number(formulario.ocupados.value),
            telefono: formulario.telefono.value.trim(),
            descripcion: formulario.descripcion.value.trim(),
            necesidades: formulario.necesidades.value.trim(),
            latitud: formulario.latitud.value || null,
            longitud: formulario.longitud.value || null
        };
        if (datos.tipo === "acopio") {
            datos.capacidad = 0;
            datos.ocupados = 0;
        }
        if (datos.nombre.length < 3) return mostrarMensaje("mensaje-formulario-centro", "Escribe el nombre del centro (mínimo 3 caracteres).", "error");
        if (datos.direccion.length < 3) return mostrarMensaje("mensaje-formulario-centro", "Escribe la dirección o el sector.", "error");
        if (!Number.isInteger(datos.capacidad) || !Number.isInteger(datos.ocupados) || datos.capacidad < 0 || datos.ocupados < 0) {
            return mostrarMensaje("mensaje-formulario-centro", "Los cupos deben ser números enteros positivos.", "error");
        }
        if (datos.ocupados > datos.capacidad) return mostrarMensaje("mensaje-formulario-centro", "Los cupos ocupados no pueden ser más que la capacidad.", "error");

        const boton = document.getElementById("guardar-centro");
        boton.disabled = true;
        mostrarMensaje("mensaje-formulario-centro", "Guardando...");
        try {
            await llamarApi(centroEditando ? `/api/admin/centros/${centroEditando.id}` : "/api/admin/centros", {
                method: "POST", body: JSON.stringify(datos)
            });
            mostrarMensaje("mensaje-centros", centroEditando ? "Centro actualizado." : "Centro creado. Ya aparece en Acopio y albergues.", "exito");
            cerrarFormularioCentro();
            await cargarCentros();
            listaCentros.scrollIntoView({ behavior: "smooth", block: "start" });
        } catch (error) {
            mostrarMensaje("mensaje-formulario-centro", textoError(error), "error");
        } finally {
            boton.disabled = false;
        }
    });

    listaCentros.addEventListener("click", async function (evento) {
        const editar = evento.target.closest("[data-editar]");
        const eliminar = evento.target.closest("[data-eliminar]");
        if (editar) {
            abrirFormularioCentro(centros.find(function (c) { return c.id === Number(editar.dataset.editar); }));
        }
        if (eliminar) {
            const centro = centros.find(function (c) { return c.id === Number(eliminar.dataset.eliminar); });
            if (!centro || !window.confirm(`¿Eliminar "${centro.nombre}"? Dejará de aparecer para la comunidad.`)) return;
            try {
                await llamarApi(`/api/admin/centros/${centro.id}/eliminar`, { method: "POST" });
                mostrarMensaje("mensaje-centros", "Centro eliminado.", "exito");
                cargarCentros();
            } catch (error) {
                mostrarMensaje("mensaje-centros", textoError(error), "error");
            }
        }
    });

    /* ---------- Desaparecidos ---------- */

    const listaDesaparecidos = document.getElementById("lista-desaparecidos-admin");
    const filtroEstado = document.getElementById("filtro-estado-desaparecidos");
    const filtroTipo = document.getElementById("filtro-tipo-desaparecidos");

    async function cargarDesaparecidos() {
        listaDesaparecidos.innerHTML = `<p class="admin_vacio">Cargando reportes...</p>`;
        const parametros = new URLSearchParams();
        if (filtroEstado.value) parametros.set("estado", filtroEstado.value);
        if (filtroTipo.value) parametros.set("tipo", filtroTipo.value);
        try {
            const reportes = await llamarApi("/api/desaparecidos?" + parametros.toString());
            mostrarMensaje("mensaje-desaparecidos", "");
            if (!reportes.length) {
                listaDesaparecidos.innerHTML = `<p class="admin_vacio">No hay reportes con esos filtros.</p>`;
                return;
            }
            listaDesaparecidos.innerHTML = reportes.map(function (r) {
                const encontrado = r.estado === "encontrado";
                return `<article class="admin_reporte ${encontrado ? "encontrado" : ""}">
                    <img src="${htmlSafe(API_BASE + r.foto_url)}" alt="Foto de ${htmlSafe(r.nombre)}" loading="lazy">
                    <div class="admin_reporte_datos">
                        <div class="admin_centro_cabecera">
                            <h4>${htmlSafe(r.nombre)}</h4>
                            <span class="admin_chip ${encontrado ? "abierto" : "activo"}">${encontrado ? "Encontrado" : "Activo"}</span>
                        </div>
                        <p><i class="fa-solid ${r.tipo === "animal" ? "fa-paw" : "fa-user"}"></i> ${r.tipo === "animal" ? "Animal" : "Persona"}${r.edad ? " · " + htmlSafe(r.edad) : ""}</p>
                        <p><i class="fa-solid fa-location-dot"></i> ${htmlSafe(r.sector || "Sin sector")}</p>
                        <p><i class="fa-solid fa-phone"></i> ${htmlSafe(r.telefono_contacto || "Sin teléfono")}</p>
                        <p class="admin_centro_meta">Reportado ${htmlSafe(fecha(r.creado_en, true))}</p>
                    </div>
                    <div class="admin_centro_acciones">
                        <button type="button" class="admin_boton_secundario" data-estado-reporte="${r.id}" data-nuevo="${encontrado ? "activo" : "encontrado"}">
                            <i class="fa-solid ${encontrado ? "fa-rotate-left" : "fa-circle-check"}"></i> ${encontrado ? "Marcar activo" : "Marcar encontrado"}
                        </button>
                        <button type="button" class="admin_boton_secundario peligro" data-retirar="${r.id}" data-nombre="${htmlSafe(r.nombre)}">
                            <i class="fa-solid fa-trash"></i> Retirar
                        </button>
                    </div>
                </article>`;
            }).join("");
        } catch (error) {
            listaDesaparecidos.innerHTML = "";
            mostrarMensaje("mensaje-desaparecidos", textoError(error), "error");
        }
    }

    [filtroEstado, filtroTipo].forEach(function (filtro) { filtro.addEventListener("change", cargarDesaparecidos); });

    listaDesaparecidos.addEventListener("click", async function (evento) {
        const cambiar = evento.target.closest("[data-estado-reporte]");
        const retirar = evento.target.closest("[data-retirar]");
        try {
            if (cambiar) {
                cambiar.disabled = true;
                await llamarApi(`/api/admin/desaparecidos/${cambiar.dataset.estadoReporte}/estado`, {
                    method: "POST", body: JSON.stringify({ estado: cambiar.dataset.nuevo })
                });
                mostrarMensaje("mensaje-desaparecidos", "Estado actualizado.", "exito");
                cargarDesaparecidos();
            }
            if (retirar) {
                if (!window.confirm(`¿Retirar el reporte de "${retirar.dataset.nombre}"? También se borran sus comentarios. No se puede deshacer.`)) return;
                await llamarApi(`/api/admin/desaparecidos/${retirar.dataset.retirar}/eliminar`, { method: "POST" });
                mostrarMensaje("mensaje-desaparecidos", "Reporte retirado.", "exito");
                cargarDesaparecidos();
            }
        } catch (error) {
            if (cambiar) cambiar.disabled = false;
            mostrarMensaje("mensaje-desaparecidos", textoError(error), "error");
        }
    });

    /* ---------- Utilidades compartidas con js/admin_contenidos.js ---------- */

    window.SigreAdmin = {
        API_BASE: API_BASE,
        llamarApi: llamarApi,
        htmlSafe: htmlSafe,
        fecha: fecha,
        leerToken: leerToken,
        mostrarMensaje: mostrarMensaje,
        textoError: textoError,
        abrirSeccion: function (nombre) { abrirSeccion(nombre); },
        registrarSeccion: function (nombre, cargador) { cargadoresExternos[nombre] = cargador; }
    };

    /* ---------- Inicio ---------- */

    async function iniciar() {
        if (!leerToken()) {
            mostrarAcceso("Inicia sesión con una cuenta de administrador o entidad para usar este panel.", true);
            return;
        }
        try {
            const resumen = await llamarApi("/api/admin/resumen");
            acceso.hidden = true;
            panel.hidden = false;
            renderizarResumen(resumen);
            abrirSeccion(window.location.hash.slice(1) || "resumen");
        } catch (error) {
            if (/sesión expiró/.test(error.message)) return;
            mostrarAcceso(/solo para cuentas/.test(error.message)
                ? "Tu cuenta no tiene permisos de administrador o entidad."
                : textoError(error), false);
        }
    }

    iniciar();
})();
