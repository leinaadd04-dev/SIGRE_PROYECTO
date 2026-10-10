/* SIGRE · Resumen del dashboard
   - Total de usuarios registrados (desde Flask y PostgreSQL).
   - Directorio de entidades y líneas de atención (GET /api/directorio).
     Lo administran las cuentas de autoridad desde el panel.

   Datos iniciales del directorio (backend/migracion_administracion_contenidos.sql),
   revisados en octubre de 2026:
   - 123, 119, 132 y 144: líneas nacionales difundidas por la UNGRD y alcaldías.
   - DANE: línea gratuita nacional 01 8000 912002 (dane.gov.co).
   - Prosperidad Social: línea gratuita nacional 01 8000 951100 (prosperidadsocial.gov.co).
   - Clínicas de Montería: nombres y direcciones de directorios públicos.
     No incluimos sus teléfonos porque no se pudieron confirmar en una fuente oficial. */
(() => {
    const API_BASE = `http://${window.location.hostname}:5000`;

    const GRUPOS_DIRECTORIO = [
        { clave: "emergencias", grupo: "Emergencias", icono: "fa-tower-broadcast", color: "rojo", iconoEntidad: "fa-phone-volume" },
        { clave: "estado", grupo: "Entidades del Estado", icono: "fa-landmark", color: "azul", iconoEntidad: "fa-building-columns" },
        { clave: "salud", grupo: "Salud en Montería", icono: "fa-hospital", color: "verde", iconoEntidad: "fa-house-medical" },
        { clave: "comunidad", grupo: "Comunidad", icono: "fa-people-roof", color: "azul", iconoEntidad: "fa-user-group" }
    ];
    // Íconos más específicos según el nombre de la entidad.
    const ICONOS_POR_NOMBRE = [
        [/polic/i, "fa-shield-halved"], [/bomber/i, "fa-fire-extinguisher"], [/cruz roja/i, "fa-briefcase-medical"],
        [/defensa civil/i, "fa-helmet-safety"], [/hospital/i, "fa-hospital"], [/niñ|infantil/i, "fa-baby"],
        [/dane/i, "fa-chart-column"], [/prosperidad/i, "fa-hand-holding-heart"], [/riesgo|ungrd/i, "fa-house-flood-water"]
    ];
    let DIRECTORIO = [];

    function agruparDirectorio(entidades) {
        return GRUPOS_DIRECTORIO.map(function (grupo) {
            return {
                grupo: grupo.grupo,
                icono: grupo.icono,
                color: grupo.color,
                entidades: entidades.filter(function (e) { return e.grupo === grupo.clave; }).map(function (e) {
                    const icono = (ICONOS_POR_NOMBRE.find(function (par) { return par[0].test(e.nombre); }) || [null, grupo.iconoEntidad])[1];
                    return {
                        nombre: e.nombre,
                        detalle: e.detalle,
                        direccion: e.direccion,
                        web: e.web,
                        telefono: e.telefono ? e.telefono.replace(/[^0-9+]/g, "") : null,
                        telefonoTexto: e.telefono,
                        icono: icono
                    };
                })
            };
        }).filter(function (grupo) { return grupo.entidades.length; });
    }

    async function cargarDirectorio() {
        lista.innerHTML = '<p class="directorio_vacio">Cargando directorio...</p>';
        try {
            const respuesta = await fetch(API_BASE + "/api/directorio");
            if (!respuesta.ok) throw new Error();
            DIRECTORIO = agruparDirectorio(await respuesta.json());
            lista.innerHTML = "";
            if (!DIRECTORIO.length) {
                lista.innerHTML = '<p class="directorio_vacio">El directorio está vacío.</p>';
                return;
            }
            renderizarDirectorio();
            filtrarDirectorio();
        } catch (error) {
            lista.innerHTML = '<p class="directorio_vacio">No se pudo cargar el directorio. En una emergencia marca el <strong>123</strong>.</p>';
        }
    }

    /* ---------- Usuarios registrados ---------- */

    const totalUsuarios = document.getElementById("total-usuarios");
    const textoUsuarios = document.getElementById("texto-usuarios");

    async function cargarTotalUsuarios() {
        try {
            const respuesta = await fetch(API_BASE + "/api/estadisticas/usuarios");
            if (!respuesta.ok) throw new Error("Sin datos");
            const datos = await respuesta.json();
            totalUsuarios.textContent = Number(datos.usuarios_registrados).toLocaleString("es-CO");
            textoUsuarios.textContent = datos.usuarios_registrados === 1 ? "Usuario registrado" : "Usuarios registrados";
        } catch (error) {
            totalUsuarios.textContent = "—";
            textoUsuarios.textContent = "Usuarios: no disponible";
            totalUsuarios.parentElement.title = "No se pudo consultar el servidor de SIGRE.";
        }
    }

    /* ---------- Directorio ---------- */

    const ventana = document.getElementById("ventana-directorio");
    const lista = document.getElementById("lista-directorio");
    const buscador = document.getElementById("buscar-directorio");
    const vacio = document.getElementById("directorio-vacio");
    const botonAbrir = document.getElementById("boton-directorio");
    const botonCerrar = document.getElementById("cerrar-directorio");

    function crear(etiqueta, clase, texto) {
        const elemento = document.createElement(etiqueta);
        if (clase) elemento.className = clase;
        if (texto) elemento.textContent = texto;
        return elemento;
    }

    function crearEnlace(clase, href, icono, texto, externo) {
        const enlace = crear("a", clase);
        enlace.href = href;
        if (externo) {
            enlace.target = "_blank";
            enlace.rel = "noopener noreferrer";
        }
        enlace.innerHTML = `<i class="fa-solid ${icono}"></i>`;
        enlace.appendChild(document.createTextNode(" " + texto));
        return enlace;
    }

    function textoBusqueda(entidad, grupo) {
        return [grupo, entidad.nombre, entidad.detalle, entidad.direccion, entidad.telefonoTexto || entidad.telefono]
            .filter(Boolean).join(" ").toLowerCase();
    }

    function renderizarDirectorio() {
        DIRECTORIO.forEach(function (seccion) {
            const bloque = crear("section", "directorio_grupo directorio_" + seccion.color);
            const titulo = crear("h3", "directorio_grupo_titulo");
            titulo.innerHTML = `<i class="fa-solid ${seccion.icono}"></i>`;
            titulo.appendChild(document.createTextNode(" " + seccion.grupo));
            bloque.appendChild(titulo);

            seccion.entidades.forEach(function (entidad) {
                const item = crear("article", "directorio_item");
                item.dataset.busqueda = textoBusqueda(entidad, seccion.grupo);

                const icono = crear("span", "directorio_item_icono");
                icono.innerHTML = `<i class="fa-solid ${entidad.icono}"></i>`;
                item.appendChild(icono);

                const datos = crear("div", "directorio_item_datos");
                datos.appendChild(crear("strong", "", entidad.nombre));
                if (entidad.detalle) datos.appendChild(crear("p", "", entidad.detalle));
                if (entidad.direccion) datos.appendChild(crear("p", "", entidad.direccion + ", Montería"));

                const acciones = crear("div", "directorio_acciones");
                if (entidad.telefono) {
                    acciones.appendChild(crearEnlace(
                        "directorio_llamar", "tel:" + entidad.telefono, "fa-phone",
                        "Llamar " + (entidad.telefonoTexto || entidad.telefono)
                    ));
                }
                if (entidad.direccion) {
                    const consulta = encodeURIComponent(`${entidad.nombre}, ${entidad.direccion}, Montería, Córdoba`);
                    acciones.appendChild(crearEnlace(
                        "directorio_secundario", "https://www.google.com/maps/search/?api=1&query=" + consulta,
                        "fa-map-location-dot", "Ver en mapa", true
                    ));
                }
                if (entidad.web) {
                    acciones.appendChild(crearEnlace(
                        "directorio_secundario", entidad.web, "fa-globe", "Sitio web", true
                    ));
                }
                datos.appendChild(acciones);
                item.appendChild(datos);
                bloque.appendChild(item);
            });

            lista.appendChild(bloque);
        });
    }

    function filtrarDirectorio() {
        const texto = buscador.value.trim().toLowerCase();
        let visibles = 0;
        lista.querySelectorAll(".directorio_grupo").forEach(function (grupo) {
            let visiblesGrupo = 0;
            grupo.querySelectorAll(".directorio_item").forEach(function (item) {
                const coincide = !texto || item.dataset.busqueda.indexOf(texto) !== -1;
                item.hidden = !coincide;
                if (coincide) visiblesGrupo++;
            });
            grupo.hidden = visiblesGrupo === 0;
            visibles += visiblesGrupo;
        });
        vacio.hidden = visibles > 0;
    }

    function abrirDirectorio() {
        ventana.hidden = false;
        document.body.classList.add("directorio_abierto");
        botonCerrar.focus();
    }

    function cerrarDirectorio() {
        if (ventana.hidden) return;
        ventana.hidden = true;
        document.body.classList.remove("directorio_abierto");
        botonAbrir.focus();
    }

    if (ventana && botonAbrir) {
        cargarDirectorio();
        botonAbrir.addEventListener("click", abrirDirectorio);
        botonCerrar.addEventListener("click", cerrarDirectorio);
        buscador.addEventListener("input", filtrarDirectorio);
        ventana.addEventListener("click", function (evento) {
            if (evento.target === ventana) cerrarDirectorio();
        });
        document.addEventListener("keydown", function (evento) {
            if (evento.key === "Escape") cerrarDirectorio();
        });
    }

    /* ---------- Tus guardados: rutas de evacuación de la cuenta ---------- */

    const contenedorMapa = document.getElementById("mapa-guardados");
    const avisoMapa = document.getElementById("aviso-mapa-guardados");
    const listaRutas = document.getElementById("lista-rutas-dashboard");

    function leerToken() {
        try {
            return localStorage.getItem("sigre_token");
        } catch (error) {
            return null;
        }
    }

    function formatearDistancia(metros) {
        return metros >= 1000
            ? `${(metros / 1000).toLocaleString("es-CO", { maximumFractionDigits: 1 })} km`
            : `${metros} m`;
    }

    const MEDIOS = { pie: "A pie", carro: "En carro", moto: "En moto" };

    function mostrarVacio(texto) {
        listaRutas.innerHTML = "";
        listaRutas.appendChild(crear("p", "guardados_vacio", texto));
    }

    function crearMapaGuardados() {
        if (!window.L || !contenedorMapa) return null;
        const mapa = L.map(contenedorMapa, { scrollWheelZoom: false }).setView([8.757, -75.884], 12);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            attribution: "&copy; OpenStreetMap",
            maxZoom: 19
        }).addTo(mapa);
        return mapa;
    }

    function punto(color) {
        return { radius: 7, color: "#ffffff", weight: 2, fillColor: color, fillOpacity: 1 };
    }

    function dibujarRutas(mapa, rutas) {
        if (!mapa) return;
        const limites = [];
        rutas.forEach(function (ruta, indice) {
            const reciente = indice === 0;
            L.polyline(ruta.geometria, {
                color: reciente ? "#2e7d32" : "#8d99ae",
                weight: reciente ? 5 : 3,
                opacity: reciente ? 0.95 : 0.6
            }).bindTooltip(ruta.nombre).addTo(mapa);
            L.circleMarker([ruta.origen.lat, ruta.origen.lon], punto("#2e7d32"))
                .bindTooltip(`Partida: ${ruta.nombre}`).addTo(mapa);
            L.circleMarker([ruta.destino.lat, ruta.destino.lon], punto("#d62839"))
                .bindTooltip(`Destino: ${ruta.nombre}`).addTo(mapa);
            limites.push(...ruta.geometria);
        });
        mapa.fitBounds(L.latLngBounds(limites), { padding: [20, 20] });
    }

    function listarRutas(rutas) {
        listaRutas.innerHTML = "";
        rutas.slice(0, 4).forEach(function (ruta) {
            const enlace = crear("a", "guardado_item guardado_ruta");
            enlace.href = `rutas.html?ruta=${encodeURIComponent(ruta.id)}`;
            const icono = crear("div", "guardado_icono");
            icono.innerHTML = '<i class="fa-solid fa-route"></i>';
            const texto = crear("div", "guardado_texto");
            texto.appendChild(crear("p", "guardado_titulo", ruta.nombre));
            texto.appendChild(crear("p", "guardado_tiempo",
                `${MEDIOS[ruta.modo] || MEDIOS.pie} · ${formatearDistancia(ruta.distancia_m)} · ${ruta.tiempo_min} min`));
            enlace.append(icono, texto);
            listaRutas.appendChild(enlace);
        });
    }

    async function cargarRutasGuardadas() {
        const mapa = crearMapaGuardados();
        const aviso = function (texto) {
            avisoMapa.textContent = texto;
            avisoMapa.hidden = false;
        };

        if (!leerToken()) {
            aviso("Inicia sesión para ver tus rutas guardadas.");
            mostrarVacio("Inicia sesión para ver tus rutas guardadas.");
            return;
        }
        try {
            const respuesta = await fetch(API_BASE + "/api/rutas/guardadas", {
                headers: { Authorization: "Bearer " + leerToken() }
            });
            if (respuesta.status === 401 || respuesta.status === 422) {
                aviso("Tu sesión expiró. Inicia sesión de nuevo.");
                mostrarVacio("Tu sesión expiró. Inicia sesión de nuevo para ver tus rutas.");
                return;
            }
            if (!respuesta.ok) throw new Error("Sin datos");
            const rutas = await respuesta.json();
            if (!rutas.length) {
                aviso("Aún no tienes rutas guardadas.");
                mostrarVacio("Calcula una ruta de evacuación y guárdala para verla aquí.");
                return;
            }
            dibujarRutas(mapa, rutas);
            listarRutas(rutas);
        } catch (error) {
            aviso("No se pudieron cargar tus rutas.");
            mostrarVacio("No se pudieron cargar tus rutas. Revisa que Flask esté en ejecución.");
        }
    }

    // El SOS de la tarjeta de emergencia reutiliza el del celular (js/dashboard.js).
    const botonSosTarjeta = document.getElementById("boton-sos-tarjeta");
    const botonSosMovil = document.getElementById("boton-sos");
    if (botonSosTarjeta && botonSosMovil) {
        botonSosTarjeta.addEventListener("click", function () {
            botonSosMovil.click();
        });
    }

    if (totalUsuarios) cargarTotalUsuarios();
    if (listaRutas) cargarRutasGuardadas();
})();
