/* SIGRE · SOS en vivo para la ciudadanía.
   - Todos los botones SOS abren un selector: videollamada con un operador
     (SOS en vivo) o llamada directa al 123.
   - SOS en vivo toma la ubicación, entra a la cola de emergencias
     (backend/sos.py) y muestra la posición hasta que un operador acepta.
   - Si se recarga la página, retoma la emergencia abierta en vez de crear otra.
   - La videollamada se agrega en el paso B3. */
(() => {
    // Las autoridades atienden el SOS desde su panel, no lo piden.
    if (document.body.classList.contains("pagina_admin")) return;

    const CLAVE_SESION = "sigre_sos_sesion";

    /* ---------- Selector: SOS en vivo o 123 ---------- */
    const selector = document.createElement("div");
    selector.className = "sos_fondo";
    selector.hidden = true;
    selector.innerHTML = `
        <section class="sos_ventana" role="dialog" aria-modal="true" aria-labelledby="sos-titulo">
            <h2 id="sos-titulo"><i class="fa-solid fa-tower-broadcast" aria-hidden="true"></i> ¿Qué necesitas?</h2>
            <p class="sos_ayuda">Si tu vida corre peligro inmediato, llama al 123.</p>

            <button type="button" class="sos_opcion sos_opcion_vivo" id="sos-en-vivo">
                <i class="fa-solid fa-video" aria-hidden="true"></i>
                <span><strong>SOS en vivo</strong>Videollamada con un operador de emergencias. Compartes tu ubicación.</span>
            </button>

            <a class="sos_opcion sos_opcion_123" href="tel:123">
                <i class="fa-solid fa-phone" aria-hidden="true"></i>
                <span><strong>Llamar al 123</strong>Línea única de emergencias.</span>
            </a>

            <button type="button" class="sos_cancelar" id="sos-cerrar-selector">Cancelar</button>
        </section>`;
    document.body.appendChild(selector);

    /* ---------- Ventana de espera ---------- */
    const espera = document.createElement("div");
    espera.className = "sos_fondo";
    espera.hidden = true;
    espera.innerHTML = `
        <section class="sos_ventana sos_espera" role="dialog" aria-modal="true" aria-labelledby="sos-estado-titulo">
            <div class="sos_estado_icono" id="sos-estado-icono" aria-hidden="true"></div>
            <h2 id="sos-estado-titulo"></h2>
            <p class="sos_ayuda" id="sos-estado-texto" aria-live="polite"></p>

            <div class="sos_posicion" id="sos-posicion" hidden>
                <span>Tu lugar en la cola</span>
                <strong id="sos-posicion-numero"></strong>
            </div>

            <button type="button" class="sos_opcion sos_opcion_123 sos_boton_estado" id="sos-boton-estado"></button>
            <a class="sos_enlace_123" href="tel:123"><i class="fa-solid fa-phone" aria-hidden="true"></i> Llamar al 123</a>
        </section>`;
    document.body.appendChild(espera);

    let botonQueAbrio = null;
    let socket = null;
    let sesionActual = null;
    let estado = null;      // ubicando, enviando, en_espera, en_curso o error
    let intento = 0;        // invalida la ubicación que llegue después de cerrar

    function abrirSelector() {
        // Si ya hay un SOS abierto, se muestra ese en vez de pedir otro.
        if (estado) {
            espera.hidden = false;
            return;
        }
        botonQueAbrio = document.activeElement;
        selector.hidden = false;
        document.getElementById("sos-en-vivo").focus();
    }

    function cerrarSelector() {
        if (selector.hidden) return;
        selector.hidden = true;
        if (botonQueAbrio && botonQueAbrio.focus) botonQueAbrio.focus();
    }

    function mostrarEstado(nuevoEstado, icono, titulo, texto, posicion) {
        estado = nuevoEstado;
        document.getElementById("sos-estado-icono").innerHTML = `<i class="fa-solid ${icono}"></i>`;
        document.getElementById("sos-estado-titulo").textContent = titulo;
        document.getElementById("sos-estado-texto").textContent = texto;

        const caja = document.getElementById("sos-posicion");
        caja.hidden = !posicion;
        if (posicion) document.getElementById("sos-posicion-numero").textContent = posicion;

        // Mientras se envía o ya lo atienden, no se puede cancelar desde aquí.
        const boton = document.getElementById("sos-boton-estado");
        boton.hidden = nuevoEstado === "enviando" || nuevoEstado === "en_curso";
        boton.textContent = nuevoEstado === "en_espera" ? "Cancelar SOS" : "Cerrar";

        espera.hidden = false;
    }

    function guardarSesion(sesion) {
        try {
            if (sesion) sessionStorage.setItem(CLAVE_SESION, sesion);
            else sessionStorage.removeItem(CLAVE_SESION);
        } catch (error) { /* sin sessionStorage no se retoma al recargar */ }
    }

    function terminar() {
        intento++;
        sesionActual = null;
        estado = null;
        guardarSesion(null);
        espera.hidden = true;
        if (socket) {
            socket.disconnect();
            socket = null;
        }
    }

    /* ---------- Conexión con el servidor ---------- */
    function conectar() {
        if (socket) return socket;
        socket = io(window.SIGRE_API, {
            auth: { token: localStorage.getItem("sigre_token") },
            transports: ["websocket"]
        });

        // También corre al reconectarse: vuelve a unir la cuenta a su emergencia.
        socket.on("connect", () => {
            if (sesionActual) retomar();
        });
        socket.on("connect_error", () => {
            if (!socket.active) {
                mostrarEstado("error", "fa-user-lock", "Inicia sesión de nuevo",
                    "Tu sesión venció. Vuelve a iniciar sesión o llama al 123.");
            } else if (estado !== "en_espera" && estado !== "en_curso") {
                mostrarEstado("error", "fa-plug-circle-xmark", "Sin conexión con SIGRE",
                    "Seguimos intentando conectar. Si estás en peligro, llama al 123.");
            }
        });
        socket.on("cola:actualizar", pedirPosicion);
        socket.on("sos:aceptada", datos => {
            if (datos.sesion === sesionActual) mostrarAtendido();
        });
        return socket;
    }

    function ponerEnCola(respuesta) {
        sesionActual = respuesta.sesion;
        guardarSesion(sesionActual);
        if (respuesta.estado === "en_curso") {
            mostrarAtendido();
            return;
        }
        mostrarEstado("en_espera", "fa-hourglass-half", "Buscando un operador",
            "Tu emergencia está en la cola. No cierres SIGRE: te atenderán en orden de llegada.",
            respuesta.posicion);
    }

    function mostrarAtendido() {
        mostrarEstado("en_curso", "fa-user-shield", "Un operador te está atendiendo",
            "Ya vio tu ubicación. En un momento se abrirá la videollamada.");
    }

    function pedirPosicion() {
        if (estado !== "en_espera") return;
        socket.emit("cola:posicion", { sesion: sesionActual }, respuesta => {
            if (estado === "en_espera" && respuesta && respuesta.posicion) {
                document.getElementById("sos-posicion-numero").textContent = respuesta.posicion;
            }
        });
    }

    function retomar() {
        socket.emit("sos:retomar", {}, respuesta => {
            if (respuesta && respuesta.sesion) ponerEnCola(respuesta);
            else terminar();
        });
    }

    /* ---------- Pedir SOS en vivo ---------- */
    function iniciarSosVivo() {
        cerrarSelector();
        if (typeof io === "undefined" || !("geolocation" in navigator)) {
            mostrarEstado("error", "fa-triangle-exclamation", "SOS en vivo no está disponible",
                "Este navegador no permite usarlo. Llama al 123.");
            return;
        }

        const esteIntento = ++intento;
        mostrarEstado("ubicando", "fa-location-crosshairs", "Obteniendo tu ubicación",
            "Permite el acceso a tu ubicación para que el operador sepa dónde estás.");

        navigator.geolocation.getCurrentPosition(posicion => {
            if (esteIntento !== intento) return;   // cerró la ventana mientras tanto
            mostrarEstado("enviando", "fa-tower-broadcast", "Enviando tu SOS",
                "Conectando con la central de emergencias…");
            conectar().emit("sos:crear", {
                lat: posicion.coords.latitude,
                lng: posicion.coords.longitude,
                precision: posicion.coords.accuracy
            }, respuesta => {
                if (respuesta && respuesta.sesion) ponerEnCola(respuesta);
                else mostrarEstado("error", "fa-triangle-exclamation", "No se pudo enviar tu SOS",
                    (respuesta && respuesta.error) || "Inténtalo de nuevo o llama al 123.");
            });
        }, error => {
            if (esteIntento !== intento) return;
            const texto = error.code === error.PERMISSION_DENIED
                ? "SOS en vivo necesita tu ubicación. Actívala en los permisos del navegador o llama al 123."
                : "No pudimos obtener tu ubicación. Revisa que el GPS esté encendido o llama al 123.";
            mostrarEstado("error", "fa-location-dot", "Sin ubicación", texto);
        }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
    }

    function botonEstado() {
        if (estado !== "en_espera") {
            terminar();
            return;
        }
        if (!window.confirm("¿Cancelar tu SOS? Saldrás de la cola de emergencias.")) return;
        socket.emit("sos:cancelar", { sesion: sesionActual }, respuesta => {
            if (respuesta && respuesta.ok) terminar();
            else mostrarAtendido();   // un operador la tomó justo antes
        });
    }

    /* ---------- Eventos ---------- */
    document.getElementById("sos-en-vivo").addEventListener("click", iniciarSosVivo);
    document.getElementById("sos-cerrar-selector").addEventListener("click", cerrarSelector);
    document.getElementById("sos-boton-estado").addEventListener("click", botonEstado);
    selector.addEventListener("click", evento => {
        if (evento.target === selector) cerrarSelector();
    });
    document.addEventListener("keydown", evento => {
        if (evento.key === "Escape") cerrarSelector();
    });

    // Al recargar con un SOS abierto, se retoma (el "connect" llama a retomar).
    try {
        const guardada = Number(sessionStorage.getItem(CLAVE_SESION));
        if (guardada && typeof io !== "undefined") {
            sesionActual = guardada;
            mostrarEstado("enviando", "fa-rotate", "Recuperando tu SOS", "Reconectando con la central…");
            conectar();
        }
    } catch (error) { /* sin sessionStorage no se retoma */ }

    // Desde aquí, todos los botones SOS abren este selector.
    window.SigreSOS = abrirSelector;
})();

