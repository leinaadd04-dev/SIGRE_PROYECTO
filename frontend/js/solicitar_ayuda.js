/* SIGRE · Módulo Solicitar ayuda
   Envía solicitudes de ayuda (para una comunidad, un grupo de familias o un
   hogar) y solicitudes de visita a vivienda. Usa el token JWT de la cuenta y
   muestra únicamente las solicitudes creadas por esa misma cuenta. */
(() => {
    const API_BASE = window.SIGRE_API;   // js/config.js
    const ENDPOINT = API_BASE + "/api/solicitudes-ayuda";
    const CLAVE_TOKEN = "sigre_token";
    const LIMITE_ADJUNTO = 5 * 1024 * 1024;
    const TIPOS_ADJUNTO = {
        "image/jpeg": ["jpg", "jpeg"],
        "image/png": ["png"],
        "image/webp": ["webp"],
        "application/pdf": ["pdf"]
    };
    const CENTRO_MONTERIA = [8.757, -75.884];

    const CATEGORIAS = {
        alimentos: { texto: "Alimentos", icono: "fa-bowl-food" },
        atencion_medica: { texto: "Atención médica", icono: "fa-kit-medical" },
        alojamiento: { texto: "Alojamiento", icono: "fa-house-chimney" },
        transporte: { texto: "Transporte", icono: "fa-truck" },
        ropa: { texto: "Ropa", icono: "fa-shirt" },
        otra: { texto: "Otra", icono: "fa-ellipsis" }
    };
    const URGENCIAS = { baja: "Baja", media: "Media", alta: "Alta", critica: "Crítica" };
    const ALCANCES = {
        comunidad: { texto: "Comunidad o barrio", icono: "fa-people-roof" },
        familias: { texto: "Grupo de familias", icono: "fa-people-group" },
        hogar: { texto: "Mi hogar", icono: "fa-house-user" }
    };
    const MOTIVOS_VISITA = {
        evaluar_danos: "Evaluar daños",
        condiciones_vivienda: "Revisar condiciones de la vivienda",
        riesgo_estructural: "Riesgo estructural",
        encuesta_social: "Encuesta o caracterización del hogar",
        otra: "Otro motivo"
    };
    const FRANJAS = {
        manana: "en la mañana",
        tarde: "en la tarde",
        cualquiera: "en cualquier horario"
    };
    const DIAS_MAXIMOS_VISITA = 60;

    // Textos que cambian entre "Solicitar ayuda" y "Gestionar visita".
    const TEXTOS_MODO = {
        ayuda: {
            icono: "fa-solid fa-hand-holding-heart",
            titulo: "Nueva solicitud de ayuda",
            intro: "Pide apoyo pensando en todas las personas afectadas: tu barrio, tus vecinos o tu hogar. Los campos marcados con * son obligatorios.",
            descripcion: "¿Qué necesitan? *",
            ejemploDescripcion: "Ej. Unas 15 familias del sector quedaron sin agua potable tras la inundación; necesitamos agua y alimentos no perecederos.",
            personas: "Personas beneficiadas (aproximado) *",
            direccion: "Dirección o sector *",
            ejemploDireccion: "Ej. Barrio La Granja, calle 20 #5-30",
            ubicacion: "Toca el mapa para marcar dónde se necesita la ayuda.",
            consentimiento: "Autorizo que esta información y mis datos de contacto se compartan con el equipo responsable de atender la solicitud.",
            boton: "Enviar solicitud",
            enviando: "Enviando tu solicitud..."
        },
        visita: {
            icono: "fa-solid fa-house-circle-check",
            titulo: "Gestionar visita a vivienda",
            intro: "Pide que el equipo visite la vivienda para revisar sus condiciones, evaluar daños o hacer una encuesta. Si varias viviendas del sector están afectadas, indícalo. Los campos marcados con * son obligatorios.",
            descripcion: "Describe la situación de la vivienda *",
            ejemploDescripcion: "Ej. Después de las lluvias aparecieron grietas en una pared y el piso de la cocina se está hundiendo.",
            personas: "Personas que viven en la vivienda o viviendas *",
            direccion: "Dirección de la vivienda *",
            ejemploDireccion: "Ej. Calle 20 #5-30, barrio La Granja (casa esquinera, puerta azul)",
            ubicacion: "Toca el mapa para marcar la vivienda; así el equipo la encuentra más fácil.",
            consentimiento: "Autorizo que esta información y mis datos de contacto se compartan con el equipo responsable, y que me contacten para coordinar la visita.",
            boton: "Solicitar visita",
            enviando: "Enviando tu solicitud de visita..."
        }
    };

    const ESTADOS = {
        pendiente: "Pendiente",
        en_revision: "En revisión",
        programada: "Visita programada",
        en_atencion: "En atención",
        atendida: "Atendida",
        cancelada: "Cancelada"
    };

    const seccionSesion = document.getElementById("seccion-sesion");
    const textoSesion = document.getElementById("texto-sesion");
    const formSesion = document.getElementById("formulario-sesion");
    const botonSesion = document.getElementById("boton-sesion");
    const mensajeSesion = document.getElementById("mensaje-sesion");
    const seccionMisSolicitudes = document.getElementById("seccion-mis-solicitudes");

    const form = document.getElementById("formulario-ayuda");
    const botonEnviar = document.getElementById("boton-enviar");
    const mensaje = document.getElementById("mensaje-formulario");
    const descripcion = document.getElementById("descripcion-ayuda");
    const contadorDescripcion = document.getElementById("contador-descripcion");
    const inputTipo = document.getElementById("tipo-solicitud");
    const botonesModo = document.querySelectorAll(".boton_modo");
    const bloqueComunidad = document.getElementById("bloque-comunidad");
    const inputComunidad = document.getElementById("comunidad-ayuda");
    const inputFechaVisita = document.getElementById("fecha-visita");
    const textoBotonEnviar = document.getElementById("texto-boton-enviar");

    const zonaAdjunto = document.getElementById("zona-adjunto");
    const inputAdjunto = document.getElementById("input-adjunto");
    const contenidoAdjunto = document.getElementById("contenido-adjunto");
    const adjuntoSeleccionado = document.getElementById("adjunto-seleccionado");
    const nombreAdjunto = document.getElementById("nombre-adjunto");
    const iconoAdjunto = document.getElementById("icono-adjunto");
    const botonQuitarAdjunto = document.getElementById("boton-quitar-adjunto");

    const contenedorMapa = document.getElementById("mapa-ayuda");
    const inputLatitud = document.getElementById("latitud-ayuda");
    const inputLongitud = document.getElementById("longitud-ayuda");
    const textoUbicacion = document.getElementById("texto-ubicacion");
    const botonMiUbicacion = document.getElementById("boton-mi-ubicacion");
    const botonQuitarUbicacion = document.getElementById("boton-quitar-ubicacion");

    const estadoLista = document.getElementById("estado-solicitudes");
    const lista = document.getElementById("lista-solicitudes");
    const botonActualizar = document.getElementById("boton-actualizar");

    let archivoAdjunto = null;
    let mapa = null;
    let marcador = null;
    let modoActual = "ayuda";

    /* ---------- Utilidades ---------- */

    function htmlSafe(valor) {
        return String(valor == null ? "" : valor).replace(/[&<>"']/g, function (caracter) {
            return {
                "&": "&amp;", "<": "&lt;", ">": "&gt;",
                '"': "&quot;", "'": "&#39;"
            }[caracter];
        });
    }

    function leerToken() {
        try {
            return localStorage.getItem(CLAVE_TOKEN);
        } catch (error) {
            return null;
        }
    }

    function guardarToken(token) {
        try {
            localStorage.setItem(CLAVE_TOKEN, token);
        } catch (error) {
            /* Sin almacenamiento la sesión dura solo mientras la página esté abierta. */
        }
        tokenEnMemoria = token;
    }

    function borrarToken() {
        try {
            localStorage.removeItem(CLAVE_TOKEN);
        } catch (error) { /* nada que limpiar */ }
        tokenEnMemoria = null;
    }

    let tokenEnMemoria = leerToken();

    function mostrarMensaje(elemento, texto, tipo) {
        elemento.textContent = texto;
        elemento.classList.remove("error", "exito");
        if (tipo) elemento.classList.add(tipo);
    }

    function formatearFecha(iso) {
        const fecha = new Date(iso);
        if (Number.isNaN(fecha.getTime())) return "";
        return fecha.toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short" });
    }

    // "2026-10-12" se interpreta como fecha local (no UTC) para no correr el día.
    function formatearDia(texto) {
        const partes = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto || "");
        if (!partes) return "";
        const fecha = new Date(+partes[1], +partes[2] - 1, +partes[3]);
        return fecha.toLocaleDateString("es-CO", { weekday: "long", day: "numeric", month: "long" });
    }

    function diaLocalIso(desplazamientoDias) {
        const fecha = new Date();
        fecha.setDate(fecha.getDate() + desplazamientoDias);
        const mes = String(fecha.getMonth() + 1).padStart(2, "0");
        const dia = String(fecha.getDate()).padStart(2, "0");
        return `${fecha.getFullYear()}-${mes}-${dia}`;
    }

    function formatearTamano(bytes) {
        return bytes < 1024 * 1024
            ? Math.max(1, Math.round(bytes / 1024)) + " KB"
            : (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    class SesionVencida extends Error {}

    async function leerError(respuesta, textoPorDefecto) {
        if (respuesta.status === 413) {
            return "El archivo supera el tamaño permitido (máximo 5 MB).";
        }
        try {
            const datos = await respuesta.json();
            return datos.error || textoPorDefecto;
        } catch (error) {
            return textoPorDefecto;
        }
    }

    // Llama a la API con el token. Si el token ya no sirve, pide confirmar la cuenta.
    async function llamarApi(ruta, opciones) {
        const configuracion = Object.assign({}, opciones);
        configuracion.headers = Object.assign({}, configuracion.headers, {
            Authorization: "Bearer " + tokenEnMemoria
        });

        const respuesta = await fetch(ruta, configuracion);
        if (respuesta.status === 401 || respuesta.status === 422) {
            borrarToken();
            mostrarSesion("Tu sesión expiró o no es válida. Confirma tu cuenta para continuar.");
            throw new SesionVencida();
        }
        return respuesta;
    }

    /* ---------- Sesión ---------- */

    // Sin sesión el formulario sigue visible; solo se pide confirmar la cuenta
    // en la columna derecha, donde luego aparecen "Mis solicitudes".
    function mostrarSesion(texto) {
        seccionMisSolicitudes.hidden = true;
        tarjetaPerfil.hidden = true;
        seccionSesion.hidden = false;
        if (window.SigreCuenta) window.SigreCuenta.limpiar();
        if (texto) mostrarMensaje(mensajeSesion, texto, "error");
    }

    function mostrarModulo() {
        seccionSesion.hidden = true;
        seccionMisSolicitudes.hidden = false;
        tarjetaPerfil.hidden = false;
        cargarCuenta();
        cargarMisSolicitudes();
    }

    function pedirSesionParaEnviar() {
        mostrarSesion();
        mostrarMensaje(mensaje, "Confirma tu cuenta SIGRE para enviar la solicitud. Lo que escribiste no se pierde.", "error");
        seccionSesion.scrollIntoView({ behavior: "smooth", block: "start" });
        document.getElementById("sesion-email").focus({ preventScroll: true });
    }

    formSesion.addEventListener("submit", async function (evento) {
        evento.preventDefault();
        const email = document.getElementById("sesion-email").value.trim();
        const password = document.getElementById("sesion-password").value;

        if (!email || !password) {
            mostrarMensaje(mensajeSesion, "Escribe tu correo y tu contraseña.", "error");
            return;
        }

        botonSesion.disabled = true;
        mostrarMensaje(mensajeSesion, "Verificando tu cuenta...");

        try {
            const respuesta = await fetch(API_BASE + "/api/auth/login", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ email: email, password: password })
            });
            if (!respuesta.ok) {
                throw new Error(await leerError(respuesta, "No se pudo verificar tu cuenta."));
            }
            const datos = await respuesta.json();
            guardarToken(datos.access_token);
            formSesion.reset();
            mostrarMensaje(mensajeSesion, "");
            if (mensaje.classList.contains("error")) {
                mostrarMensaje(mensaje, "Cuenta confirmada. Ya puedes enviar tu solicitud.", "exito");
            }
            mostrarModulo();
        } catch (error) {
            const texto = error instanceof TypeError
                ? "No se pudo conectar con el servidor de SIGRE. Verifica que Flask esté en ejecución."
                : error.message;
            mostrarMensaje(mensajeSesion, texto, "error");
        } finally {
            botonSesion.disabled = false;
        }
    });

    const enlaceCerrarSesion = document.getElementById("cerrar-sesion");
    if (enlaceCerrarSesion) {
        enlaceCerrarSesion.addEventListener("click", borrarToken);
    }

    /* ---------- Mapa (Leaflet, igual que jornadas y centros) ---------- */

    function fijarUbicacion(lat, lon, centrar) {
        const latitud = Number(lat.toFixed(6));
        const longitud = Number(lon.toFixed(6));
        inputLatitud.value = String(latitud);
        inputLongitud.value = String(longitud);
        textoUbicacion.textContent = `Ubicación marcada: ${latitud}, ${longitud}. Puedes arrastrar el marcador para ajustarla.`;
        botonQuitarUbicacion.hidden = false;

        if (!mapa) return;
        if (marcador) {
            marcador.setLatLng([latitud, longitud]);
        } else {
            marcador = L.marker([latitud, longitud], {
                draggable: true,
                icon: L.divIcon({
                    className: "marcador_ayuda",
                    html: '<i class="fa-solid fa-location-dot"></i>',
                    iconSize: [30, 30],
                    iconAnchor: [15, 30]
                })
            }).addTo(mapa);
            marcador.on("dragend", function () {
                const posicion = marcador.getLatLng();
                fijarUbicacion(posicion.lat, posicion.lng, false);
            });
        }
        if (centrar) mapa.setView([latitud, longitud], 16);
    }

    function quitarUbicacion() {
        inputLatitud.value = "";
        inputLongitud.value = "";
        textoUbicacion.textContent = TEXTOS_MODO[modoActual].ubicacion;
        botonQuitarUbicacion.hidden = true;
        if (marcador && mapa) {
            mapa.removeLayer(marcador);
        }
        marcador = null;
    }

    function iniciarMapa() {
        if (mapa) {
            window.setTimeout(function () { mapa.invalidateSize(); }, 100);
            return;
        }
        if (!window.L) {
            contenedorMapa.classList.add("sin_mapa");
            contenedorMapa.textContent = "No se pudo cargar el mapa. Revisa tu conexión; puedes enviar la solicitud solo con la dirección.";
            textoUbicacion.hidden = true;
            botonMiUbicacion.hidden = true;
            return;
        }

        mapa = L.map(contenedorMapa).setView(CENTRO_MONTERIA, 13);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            attribution: "&copy; OpenStreetMap contributors",
            maxZoom: 19
        }).addTo(mapa);

        mapa.on("click", function (evento) {
            fijarUbicacion(evento.latlng.lat, evento.latlng.lng, false);
        });

        window.setTimeout(function () { mapa.invalidateSize(); }, 100);
    }

    botonMiUbicacion.addEventListener("click", function () {
        if (!("geolocation" in navigator)) {
            textoUbicacion.textContent = "Tu navegador no permite obtener la ubicación. Marca el punto en el mapa.";
            return;
        }
        botonMiUbicacion.disabled = true;
        textoUbicacion.textContent = "Obteniendo tu ubicación...";
        navigator.geolocation.getCurrentPosition(
            function (posicion) {
                botonMiUbicacion.disabled = false;
                fijarUbicacion(posicion.coords.latitude, posicion.coords.longitude, true);
            },
            function () {
                botonMiUbicacion.disabled = false;
                textoUbicacion.textContent = "No se pudo obtener tu ubicación. Revisa los permisos o marca el punto en el mapa.";
            },
            { enableHighAccuracy: true, timeout: 10000 }
        );
    });

    botonQuitarUbicacion.addEventListener("click", quitarUbicacion);

    /* ---------- Adjunto ---------- */

    function validarArchivo(archivo) {
        const extension = (archivo.name.split(".").pop() || "").toLowerCase();
        const extensiones = TIPOS_ADJUNTO[archivo.type];
        if (!extensiones || extensiones.indexOf(extension) === -1) {
            return "Solo se permiten imágenes JPG, PNG o WEBP, o documentos PDF.";
        }
        if (archivo.size === 0) {
            return "El archivo está vacío.";
        }
        if (archivo.size > LIMITE_ADJUNTO) {
            return `El archivo pesa ${formatearTamano(archivo.size)}; el máximo es 5 MB.`;
        }
        return null;
    }

    function seleccionarArchivo(archivo) {
        if (!archivo) return;
        const error = validarArchivo(archivo);
        if (error) {
            quitarArchivo();
            mostrarMensaje(mensaje, error, "error");
            return;
        }
        archivoAdjunto = archivo;
        nombreAdjunto.textContent = `${archivo.name} (${formatearTamano(archivo.size)})`;
        iconoAdjunto.className = archivo.type === "application/pdf"
            ? "fa-solid fa-file-pdf"
            : "fa-solid fa-file-image";
        contenidoAdjunto.hidden = true;
        adjuntoSeleccionado.hidden = false;
        zonaAdjunto.classList.add("con_archivo");
        if (mensaje.classList.contains("error")) mostrarMensaje(mensaje, "");
    }

    function quitarArchivo() {
        archivoAdjunto = null;
        inputAdjunto.value = "";
        nombreAdjunto.textContent = "";
        contenidoAdjunto.hidden = false;
        adjuntoSeleccionado.hidden = true;
        zonaAdjunto.classList.remove("con_archivo");
    }

    inputAdjunto.addEventListener("change", function () {
        seleccionarArchivo(inputAdjunto.files[0]);
    });

    botonQuitarAdjunto.addEventListener("click", quitarArchivo);

    ["dragenter", "dragover"].forEach(function (tipo) {
        zonaAdjunto.addEventListener(tipo, function (evento) {
            evento.preventDefault();
            zonaAdjunto.classList.add("arrastrando");
        });
    });
    ["dragleave", "drop"].forEach(function (tipo) {
        zonaAdjunto.addEventListener(tipo, function () {
            zonaAdjunto.classList.remove("arrastrando");
        });
    });
    zonaAdjunto.addEventListener("drop", function (evento) {
        evento.preventDefault();
        seleccionarArchivo(evento.dataTransfer.files[0]);
    });

    /* ---------- Modo (ayuda / visita) y alcance ---------- */

    function activarBloque(elemento, activo) {
        elemento.hidden = !activo;
        elemento.querySelectorAll("input, select, textarea").forEach(function (campo) {
            campo.disabled = !activo;
        });
        if (!activo) {
            elemento.classList.remove("campo_invalido");
            elemento.querySelectorAll(".campo_invalido").forEach(function (campo) {
                marcar(campo, false);
            });
        }
    }

    function actualizarAlcance() {
        const alcance = (form.querySelector('input[name="alcance"]:checked') || {}).value;
        activarBloque(bloqueComunidad, alcance === "comunidad" || alcance === "familias");
    }

    function cambiarModo(modo) {
        modoActual = modo;
        const textos = TEXTOS_MODO[modo];
        inputTipo.value = modo;
        form.closest(".seccion_formulario_ayuda").classList.toggle("modo_visita", modo === "visita");

        botonesModo.forEach(function (boton) {
            const activo = boton.getAttribute("data-modo") === modo;
            boton.classList.toggle("activo", activo);
            boton.setAttribute("aria-pressed", activo ? "true" : "false");
        });
        form.querySelectorAll("[data-modo-solo]").forEach(function (bloque) {
            activarBloque(bloque, bloque.getAttribute("data-modo-solo") === modo);
        });

        document.getElementById("icono-titulo").className = textos.icono;
        document.getElementById("texto-titulo").textContent = textos.titulo;
        document.getElementById("texto-intro").textContent = textos.intro;
        document.getElementById("etiqueta-descripcion").textContent = textos.descripcion;
        descripcion.placeholder = textos.ejemploDescripcion;
        document.getElementById("etiqueta-personas").textContent = textos.personas;
        document.getElementById("etiqueta-direccion").textContent = textos.direccion;
        document.getElementById("direccion-ayuda").placeholder = textos.ejemploDireccion;
        document.getElementById("texto-consentimiento").textContent = textos.consentimiento;
        textoBotonEnviar.textContent = textos.boton;
        if (!inputLatitud.value) textoUbicacion.textContent = textos.ubicacion;
        if (!mensaje.classList.contains("exito")) mostrarMensaje(mensaje, "");
    }

    botonesModo.forEach(function (boton) {
        boton.addEventListener("click", function () {
            cambiarModo(boton.getAttribute("data-modo"));
        });
    });

    form.querySelectorAll('input[name="alcance"]').forEach(function (opcion) {
        opcion.addEventListener("change", actualizarAlcance);
    });

    inputFechaVisita.min = diaLocalIso(1);
    inputFechaVisita.max = diaLocalIso(DIAS_MAXIMOS_VISITA);

    /* ---------- Validación del formulario ---------- */

    function marcar(elemento, invalido) {
        elemento.classList.toggle("campo_invalido", invalido);
        if (elemento.matches("input, textarea, select")) {
            elemento.setAttribute("aria-invalid", invalido ? "true" : "false");
        }
    }

    function validarFormulario() {
        const errores = [];
        const datos = new FormData(form);

        const grupoAlcance = document.getElementById("grupo-alcance");
        const grupoCategoria = document.getElementById("grupo-categoria");
        const grupoMotivo = document.getElementById("grupo-motivo");
        const franja = document.getElementById("franja-visita");
        const esVisita = modoActual === "visita";
        const pideComunidad = !bloqueComunidad.hidden;
        const fechaVisita = inputFechaVisita.value;
        const grupoUrgencia = form.querySelector(".opciones_urgencia").closest("fieldset");
        const personas = document.getElementById("personas-ayuda");
        const direccion = document.getElementById("direccion-ayuda");
        const nombre = document.getElementById("nombre-ayuda");
        const telefono = document.getElementById("telefono-ayuda");
        const consentimiento = document.getElementById("autoriza-compartir").closest("label");

        const reglas = [
            [grupoAlcance, !datos.get("alcance"), "Indica a quiénes beneficia la solicitud."],
            [inputComunidad, pideComunidad && inputComunidad.value.trim().length < 3,
                "Escribe el nombre del barrio, comunidad u organización beneficiada."],
            [grupoCategoria, !esVisita && !datos.get("categoria"), "Selecciona la categoría de ayuda."],
            [grupoMotivo, esVisita && !datos.get("motivo_visita"), "Selecciona el motivo de la visita."],
            [inputFechaVisita, esVisita && (!fechaVisita || fechaVisita < inputFechaVisita.min || fechaVisita > inputFechaVisita.max),
                `Elige una fecha para la visita entre mañana y los próximos ${DIAS_MAXIMOS_VISITA} días.`],
            [franja, esVisita && !franja.value, "Selecciona la franja horaria para la visita."],
            [grupoUrgencia, !datos.get("urgencia"), "Selecciona el nivel de urgencia."],
            [descripcion, descripcion.value.trim().length < 10, "Describe la situación (mínimo 10 caracteres)."],
            [personas, !/^\d+$/.test(personas.value) || +personas.value < 1 || +personas.value > 10000,
                "Indica cuántas personas se benefician (entre 1 y 10000)."],
            [direccion, direccion.value.trim().length < 5, "Escribe la dirección o el sector (mínimo 5 caracteres)."],
            [nombre, nombre.value.trim().length < 2, "Escribe el nombre de contacto."],
            [telefono, !/^\+?[0-9 ()-]{7,20}$/.test(telefono.value.trim())
                || telefono.value.replace(/\D/g, "").length < 7,
                "Escribe un teléfono de contacto válido (mínimo 7 dígitos)."],
            [consentimiento, !document.getElementById("autoriza-compartir").checked,
                "Debes autorizar que la información se comparta con el equipo responsable."]
        ];

        reglas.forEach(function (regla) {
            marcar(regla[0], regla[1]);
            if (regla[1]) errores.push(regla[2]);
        });

        return errores;
    }

    descripcion.addEventListener("input", function () {
        contadorDescripcion.textContent = `${descripcion.value.length} / 1200`;
    });

    form.addEventListener("change", function (evento) {
        const contenedor = evento.target.closest(".campo_invalido");
        if (contenedor) marcar(contenedor, false);
    });
    form.addEventListener("input", function (evento) {
        if (evento.target.classList.contains("campo_invalido")) marcar(evento.target, false);
    });

    /* ---------- Envío ---------- */

    form.addEventListener("submit", async function (evento) {
        evento.preventDefault();
        mostrarMensaje(mensaje, "");

        const errores = validarFormulario();
        if (errores.length) {
            mostrarMensaje(mensaje, errores[0], "error");
            const primerInvalido = form.querySelector(".campo_invalido");
            if (primerInvalido) primerInvalido.scrollIntoView({ behavior: "smooth", block: "center" });
            return;
        }

        if (!tokenEnMemoria) {
            pedirSesionParaEnviar();
            return;
        }

        const datos = new FormData(form);
        datos.set("autoriza_compartir", "true");
        if (archivoAdjunto) datos.append("adjunto", archivoAdjunto);

        const contenidoBoton = botonEnviar.innerHTML;
        botonEnviar.disabled = true;
        botonEnviar.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Enviando...';
        mostrarMensaje(mensaje, TEXTOS_MODO[modoActual].enviando);

        try {
            const respuesta = await llamarApi(ENDPOINT, { method: "POST", body: datos });
            if (!respuesta.ok) {
                throw new Error(await leerError(respuesta, "No se pudo enviar la solicitud. Inténtalo de nuevo."));
            }
            const creada = await respuesta.json();

            form.reset();
            contadorDescripcion.textContent = "0 / 1200";
            quitarArchivo();
            quitarUbicacion();
            cambiarModo(modoActual);
            actualizarAlcance();
            mostrarMensaje(
                mensaje,
                creada.tipo === "visita"
                    ? `Visita solicitada (#${creada.id}). El equipo te llamará para confirmar la fecha. Puedes seguirla en "Mis solicitudes".`
                    : `Solicitud #${creada.id} enviada. Estado: ${ESTADOS[creada.estado] || creada.estado}. Puedes seguirla en "Mis solicitudes".`,
                "exito"
            );
            cargarMisSolicitudes();
        } catch (error) {
            if (error instanceof SesionVencida) {
                pedirSesionParaEnviar();
                return;
            }
            const texto = error instanceof TypeError
                ? "No se pudo conectar con el servidor de SIGRE. Verifica que Flask esté en ejecución e inténtalo de nuevo."
                : error.message;
            mostrarMensaje(mensaje, texto, "error");
        } finally {
            botonEnviar.disabled = false;
            botonEnviar.innerHTML = contenidoBoton;
        }
    });

    /* ---------- Mis solicitudes ---------- */

    function mostrarEstadoLista(texto, esError) {
        lista.innerHTML = "";
        estadoLista.hidden = false;
        estadoLista.textContent = texto;
        estadoLista.classList.toggle("error", Boolean(esError));
    }

    function renderizarSolicitudes(solicitudes) {
        if (!solicitudes.length) {
            mostrarEstadoLista("Aún no has enviado solicitudes de ayuda ni de visita.");
            return;
        }

        estadoLista.hidden = true;
        lista.innerHTML = solicitudes.map(function (solicitud) {
            const esVisita = solicitud.tipo === "visita";
            const categoria = esVisita
                ? { texto: MOTIVOS_VISITA[solicitud.motivo_visita] || "Visita a vivienda", icono: "fa-house-circle-check" }
                : CATEGORIAS[solicitud.categoria] || { texto: solicitud.categoria, icono: "fa-circle-question" };
            const estado = ESTADOS[solicitud.estado] || solicitud.estado;
            const urgencia = URGENCIAS[solicitud.urgencia] || solicitud.urgencia;
            const alcance = ALCANCES[solicitud.alcance] || { texto: solicitud.alcance, icono: "fa-users" };
            const textoAlcance = solicitud.nombre_comunidad
                ? `${alcance.texto}: ${solicitud.nombre_comunidad}`
                : alcance.texto;
            const personas = solicitud.personas_afectadas === 1
                ? (esVisita ? "1 persona en la vivienda" : "1 persona beneficiada")
                : `${solicitud.personas_afectadas} ${esVisita ? "personas en la vivienda" : "personas beneficiadas"}`;
            const visita = esVisita
                ? `<span><i class="fa-solid fa-calendar-day"></i>Fecha preferida: ${htmlSafe(formatearDia(solicitud.fecha_visita_preferida))} ${htmlSafe(FRANJAS[solicitud.franja_horaria] || "")}</span>`
                : "";
            const ubicacion = solicitud.latitud != null
                ? `<span><i class="fa-solid fa-map-pin"></i>Ubicación marcada en el mapa</span>`
                : "";
            const adjunto = solicitud.tiene_adjunto
                ? `<button type="button" class="boton_secundario" data-adjunto="${htmlSafe(solicitud.id)}">
                       <i class="fa-solid fa-paperclip"></i> Descargar adjunto
                   </button>`
                : "";

            return `
                <li class="solicitud_item tipo_${esVisita ? "visita" : "ayuda"}">
                    <div class="solicitud_cabecera">
                        <h3 class="solicitud_categoria">
                            <i class="fa-solid ${htmlSafe(categoria.icono)}"></i>
                            ${htmlSafe(categoria.texto)}
                        </h3>
                        <span class="etiqueta estado_${htmlSafe(solicitud.estado)}">${htmlSafe(estado)}</span>
                    </div>
                    <div class="solicitud_etiquetas">
                        <span class="etiqueta etiqueta_tipo_${esVisita ? "visita" : "ayuda"}">
                            ${esVisita ? "Visita a vivienda" : "Ayuda"}
                        </span>
                        <span class="etiqueta etiqueta_alcance">
                            <i class="fa-solid ${htmlSafe(alcance.icono)}"></i> ${htmlSafe(textoAlcance)}
                        </span>
                        <span class="etiqueta urgencia_etiqueta_${htmlSafe(solicitud.urgencia)}">
                            Urgencia ${htmlSafe(urgencia.toLowerCase())}
                        </span>
                        <span class="etiqueta estado_cancelada">#${htmlSafe(solicitud.id)}</span>
                    </div>
                    <p class="solicitud_descripcion">${htmlSafe(solicitud.descripcion)}</p>
                    <p class="solicitud_datos">
                        <span><i class="fa-solid fa-location-dot"></i>${htmlSafe(solicitud.direccion)}</span>
                        ${ubicacion}
                        ${visita}
                        <span><i class="fa-solid fa-users"></i>${htmlSafe(personas)}</span>
                        <span><i class="fa-solid fa-phone"></i>${htmlSafe(solicitud.nombre_contacto)} · ${htmlSafe(solicitud.telefono_contacto)}</span>
                        <span><i class="fa-solid fa-clock"></i>Enviada el ${htmlSafe(formatearFecha(solicitud.creada_en))}</span>
                    </p>
                    ${adjunto}
                </li>
            `;
        }).join("");
    }

    async function cargarMisSolicitudes() {
        mostrarEstadoLista("Cargando tus solicitudes...");
        botonActualizar.disabled = true;

        try {
            const respuesta = await llamarApi(ENDPOINT + "/mias");
            if (!respuesta.ok) {
                throw new Error(await leerError(respuesta, "No se pudieron cargar tus solicitudes."));
            }
            renderizarSolicitudes(await respuesta.json());
        } catch (error) {
            if (error instanceof SesionVencida) return;
            mostrarEstadoLista(
                error instanceof TypeError
                    ? "No se pudieron cargar tus solicitudes. Revisa que Flask, la base de datos y la migración estén listos."
                    : error.message,
                true
            );
        } finally {
            botonActualizar.disabled = false;
        }
    }

    botonActualizar.addEventListener("click", cargarMisSolicitudes);

    lista.addEventListener("click", async function (evento) {
        const boton = evento.target.closest("[data-adjunto]");
        if (!boton) return;

        const id = boton.getAttribute("data-adjunto");
        boton.disabled = true;
        try {
            const respuesta = await llamarApi(`${ENDPOINT}/${encodeURIComponent(id)}/adjunto`);
            if (!respuesta.ok) {
                throw new Error(await leerError(respuesta, "No se pudo descargar el adjunto."));
            }
            const blob = await respuesta.blob();
            const extension = {
                "image/jpeg": "jpg", "image/png": "png",
                "image/webp": "webp", "application/pdf": "pdf"
            }[blob.type] || "bin";
            const url = URL.createObjectURL(blob);
            const enlace = document.createElement("a");
            enlace.href = url;
            enlace.download = `solicitud-${id}.${extension}`;
            document.body.appendChild(enlace);
            enlace.click();
            enlace.remove();
            window.setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
        } catch (error) {
            if (error instanceof SesionVencida) return;
            alert(error instanceof TypeError
                ? "No se pudo conectar con el servidor de SIGRE."
                : error.message);
        } finally {
            boton.disabled = false;
        }
    });

    /* ---------- Perfil (el avatar lo maneja js/cuenta_sigre.js) ---------- */

    const tarjetaPerfil = document.getElementById("tarjeta-perfil");
    const avatarPerfil = document.getElementById("avatar-perfil");
    const perfilEmail = document.getElementById("perfil-email");
    const cuenta = window.SigreCuenta;

    async function cargarCuenta() {
        if (cuenta) cuenta.recargar();
        try {
            const respuesta = await llamarApi(API_BASE + "/api/mi-cuenta");
            if (respuesta.ok) perfilEmail.textContent = (await respuesta.json()).email;
        } catch (error) {
            // El correo es informativo; si falla, la tarjeta se queda sin él.
        }
    }

    if (cuenta) {
        cuenta.alCambiarAvatar(function (avatar) {
            cuenta.pintarAvatar(avatarPerfil, avatar);
        });
        document.getElementById("boton-cambiar-avatar").addEventListener("click", cuenta.abrirAvatar);
    } else {
        document.getElementById("boton-cambiar-avatar").hidden = true;
    }

    /* ---------- Inicio ---------- */

    cambiarModo("ayuda");
    iniciarMapa();

    if (tokenEnMemoria) {
        mostrarModulo();
    } else {
        mostrarSesion();
    }
})();
