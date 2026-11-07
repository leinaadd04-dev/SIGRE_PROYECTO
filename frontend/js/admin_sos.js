/* SIGRE Â· Panel de administraciÃ³n: SOS en vivo (lado del operador).
   Paso 1: cola de emergencias en tiempo real y botÃ³n "Atender".
   Usa Socket.IO (el mismo servidor que js/sos_vivo.js) y las utilidades
   de js/admin.js (window.SigreAdmin). */
(() => {
    const A = window.SigreAdmin;
    if (!A || !window.io) return;
    const { htmlSafe, fecha, mostrarMensaje } = A;

    const lista = document.getElementById("lista-sos-cola");
    const contador = document.getElementById("contador-sos");
    const atencion = document.getElementById("sos-atencion");

    let socket = null;
    let cola = [];             // emergencias en espera, en orden de llegada
    let sesionAtendida = null; // la que estÃ¡ atendiendo este operador

    // Videollamada (Paso 2)
    let conexion = null;            // RTCPeerConnection con el ciudadano
    let medios = null;              // cÃ¡mara y micrÃ³fono del operador
    let candidatosPendientes = [];  // candidatos ICE que llegan antes de poder usarlos
    let ofertaPendiente = null;     // offer que llegÃ³ antes de terminar de "Atender"
    let cronometro = null;          // reloj de la duraciÃ³n de la llamada

    let mapa = null;
    let marcador = null;
    let circulo = null;
    let recorrido = null;

    /* ---------- Pintar ---------- */

    function pintarCola() {
        contador.textContent = cola.length;
        contador.hidden = cola.length === 0;
        if (!cola.length) {
            lista.innerHTML = `<p class="admin_vacio">No hay emergencias en espera.</p>`;
            return;
        }

        lista.innerHTML = cola.map((sos, indice) => {
            const ubicacion = sos.lat != null
                ? `<i class="fa-solid fa-location-dot"></i> ${sos.lat.toFixed(5)}, ${sos.lng.toFixed(5)}` +
                  (sos.precision ? ` (Â±${Math.round(sos.precision)} m)` : "")
                : `<i class="fa-solid fa-triangle-exclamation"></i> Sin ubicaciÃ³n`;
            return `<article class="admin_centro">
                <span class="admin_centro_icono rojo"><i class="fa-solid fa-tower-broadcast"></i></span>
                <div class="admin_centro_datos">
                    <div class="admin_centro_cabecera">
                        <h4>SOS #${sos.sesion}</h4>
                        <span class="admin_chip activo">${indice === 0 ? "Siguiente" : `En espera Â· ${indice + 1}Â°`}</span>
                    </div>
                    <p class="admin_centro_tipo">Recibida ${htmlSafe(fecha(sos.creada_en, true))}</p>
                    <p class="admin_centro_meta">${ubicacion}</p>
                </div>
                <div class="admin_centro_acciones">
                    <button type="button" class="admin_boton" data-atender="${sos.sesion}" ${sesionAtendida ? "disabled" : ""}>
                        <i class="fa-solid fa-headset"></i> Atender
                    </button>
                </div>
            </article>`;
        }).join("");
    }

    // "125" segundos -> "02:05"
    function formatoDuracion(segundos) {
        const s = Math.max(0, Math.floor(segundos));
        return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
    }

    // Cuenta desde que se aceptÃ³ la emergencia (hora del servidor), asÃ­ no se
    // reinicia si se recarga la pÃ¡gina.
    function iniciarCronometro(desde) {
        detenerCronometro();
        limpiarMapa();
        const inicio = desde ? new Date(desde).getTime() : Date.now();
        const pintar = () => {
            document.getElementById("sos-duracion").textContent = formatoDuracion((Date.now() - inicio) / 1000);
        };
        pintar();
        cronometro = setInterval(pintar, 1000);
    }

    function detenerCronometro() {
        clearInterval(cronometro);
        cronometro = null;
    }

    // Cierra la atenciÃ³n en el panel (la colgÃ³ el operador o el ciudadano).
    function terminarAtencion(texto) {
        detenerVideo();
        detenerCronometro();
        sesionAtendida = null;
        atencion.hidden = true;
        mostrarMensaje("mensaje-sos", texto, "exito");
        pintarCola();   // los botones "Atender" se vuelven a activar
    }

    function mostrarAtencion(respuesta) {
        sesionAtendida = respuesta.sesion;
        const c = respuesta.contacto || {};
        document.getElementById("sos-atencion-titulo").textContent = `SOS #${respuesta.sesion}`;
        document.getElementById("sos-contacto").innerHTML = `
            <p><strong>${htmlSafe(c.nombre || "Ciudadano sin nombre")}</strong></p>
            ${c.telefono ? `<p><a href="tel:${htmlSafe(c.telefono)}"><i class="fa-solid fa-phone"></i> ${htmlSafe(c.telefono)}</a></p>` : ""}
            ${c.contacto_emergencia_nombre ? `<p>Contacto de emergencia: ${htmlSafe(c.contacto_emergencia_nombre)}
                ${c.contacto_emergencia_telefono ? ` Â· <a href="tel:${htmlSafe(c.contacto_emergencia_telefono)}">${htmlSafe(c.contacto_emergencia_telefono)}</a>` : ""}</p>` : ""}`;
        atencion.hidden = false;
        iniciarCronometro(respuesta.atendida_en);

        limpiarMapa();
        prepararMapa();

        setTimeout(() => {
            if (mapa) mapa.invalidateSize();
        }, 100);

        pintarUbicacion(respuesta.ubicacion);

        pintarCola();   // mientras atiende, los demÃ¡s botones "Atender" quedan desactivados
        // Si la offer del ciudadano llegÃ³ antes, se responde ahora.
        if (ofertaPendiente && ofertaPendiente.sesion === respuesta.sesion) {
            responderOferta(ofertaPendiente);
            ofertaPendiente = null;
        }
    }

    /* ---------- Videollamada (WebRTC) ---------- */

    /* ---------- Mapa con ubicaciÃ³n en vivo ---------- */

    function prepararMapa() {
        if (mapa || !window.L) return;

        mapa = L.map("sos-mapa").setView([8.757, -75.884], 13);

        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            attribution: "&copy; OpenStreetMap",
            maxZoom: 19
        }).addTo(mapa);
    }

    function pintarUbicacion(punto) {
        if (!punto || punto.lat == null || punto.lng == null) return;

        prepararMapa();
        if (!mapa) return;

        const posicion = [punto.lat, punto.lng];

        if (!marcador) {
            marcador = L.marker(posicion).addTo(mapa);
            circulo = L.circle(posicion, {
                radius: punto.precision || 0,
                color: "#e53e3e",
                weight: 1,
                fillOpacity: 0.12
            }).addTo(mapa);

            recorrido = L.polyline([posicion], {
                color: "#e53e3e",
                weight: 3,
                opacity: 0.6
            }).addTo(mapa);

            mapa.setView(posicion, 17);
        } else {
            marcador.setLatLng(posicion);
            circulo.setLatLng(posicion).setRadius(punto.precision || 0);
            recorrido.addLatLng(posicion);
            mapa.panTo(posicion);
        }

        const hora = punto.registrada_en
            ? new Date(punto.registrada_en).toLocaleTimeString("es-CO")
            : "";

        document.getElementById("sos-ubicacion-texto").textContent =
            `${punto.lat.toFixed(5)}, ${punto.lng.toFixed(5)}` +
            (punto.precision ? ` Â· Â±${Math.round(punto.precision)} m` : "") +
            (hora ? ` Â· actualizada ${hora}` : "");

        const enlace = document.getElementById("sos-ubicacion-enlace");
        enlace.href = `https://www.google.com/maps?q=${punto.lat},${punto.lng}`;
        enlace.hidden = false;
    }

    function limpiarMapa() {
        [marcador, circulo, recorrido].forEach(capa => {
            if (capa) capa.remove();
        });

        marcador = circulo = recorrido = null;

        document.getElementById("sos-ubicacion-texto").textContent =
            "Esperando la ubicaciÃ³nâ€¦";

        document.getElementById("sos-ubicacion-enlace").hidden = true;
    }

    function estadoVideo(texto) {
        document.getElementById("sos-estado-video").textContent = texto;
    }

    async function pedirCamara() {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return null;
        try {
            return await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        } catch (error) {
            // Sin cÃ¡mara se intenta solo con el micrÃ³fono.
            try {
                return await navigator.mediaDevices.getUserMedia({ audio: true });
            } catch (otroError) {
                return null;   // sin cÃ¡mara ni micrÃ³fono: igual ve y oye al ciudadano
            }
        }
    }

    async function servidoresIce() {
        try {
            const respuesta = await fetch(`${window.SIGRE_API}/api/sos/ice`, {
                headers: { Authorization: `Bearer ${A.leerToken()}` }
            });
            if (respuesta.ok) return (await respuesta.json()).iceServers;
        } catch (error) {
            // Si falla, se usa solo el STUN pÃºblico.
        }
        return [{ urls: "stun:stun.l.google.com:19302" }];
    }

    // El ciudadano envÃ­a la offer; el operador responde con la answer.
    async function responderOferta(datos) {
        const sesion = datos.sesion;
        if (conexion) {        // si quedaba una llamada anterior (el ciudadano recargÃ³)
            conexion.close();
            conexion = null;
        }
        estadoVideo("Conectando la videollamadaâ€¦");
        try {
            const iceServers = await servidoresIce();
            if (!medios) medios = await pedirCamara();
            if (sesion !== sesionAtendida) return;   // se cerrÃ³ mientras tanto

            conexion = new RTCPeerConnection({ iceServers });

            // Lo que el operador envÃ­a (si dio permiso).
            if (medios) {
                medios.getTracks().forEach(pista => conexion.addTrack(pista, medios));
                document.getElementById("sos-op-local").srcObject = medios;
            }

            conexion.onicecandidate = evento => {
                if (evento.candidate) socket.emit("webrtc:ice", { sesion, candidato: evento.candidate.toJSON() });
            };
            conexion.ontrack = evento => {
                document.getElementById("sos-op-remoto").srcObject = evento.streams[0];
            };
            conexion.onconnectionstatechange = () => {
                if (!conexion) return;
                const mensajes = {
                    connected: "En videollamada con el ciudadano.",
                    disconnected: "Se cortÃ³ el video. Intentando reconectarâ€¦",
                    failed: "No se pudo conectar el video. Llama al ciudadano por telÃ©fono."
                };
                if (mensajes[conexion.connectionState]) estadoVideo(mensajes[conexion.connectionState]);
            };

            await conexion.setRemoteDescription(datos.sdp);
            // Los candidatos que llegaron mientras se preparaba la conexiÃ³n se agregan ahora.
            for (const candidato of candidatosPendientes) await conexion.addIceCandidate(candidato);
            candidatosPendientes = [];

            const respuesta = await conexion.createAnswer();
            await conexion.setLocalDescription(respuesta);
            socket.emit("webrtc:answer", { sesion, sdp: { type: respuesta.type, sdp: respuesta.sdp } });
        } catch (error) {
            console.error("SOS en vivo: no se pudo responder la videollamada", error);
            estadoVideo("No se pudo conectar el video. Llama al ciudadano por telÃ©fono.");
        }
    }

    // Se usarÃ¡ en el Paso 4 al cerrar el caso.
    function detenerVideo() {
        candidatosPendientes = [];
        ofertaPendiente = null;
        if (conexion) {
            conexion.close();
            conexion = null;
        }
        if (medios) {
            medios.getTracks().forEach(pista => pista.stop());   // apaga la luz de la cÃ¡mara
            medios = null;
        }
        document.getElementById("sos-op-local").srcObject = null;
        document.getElementById("sos-op-remoto").srcObject = null;
    }

    /* ---------- Servidor ---------- */

    function cargarCola() {
        socket.emit("sos:cola", respuesta => {
            if (respuesta.error) return mostrarMensaje("mensaje-sos", respuesta.error, "error");
            cola = respuesta.cola;
            pintarCola();
        });
    }

    function conectar() {
        if (socket) return;
        socket = io(window.SIGRE_API, {
            auth: { token: A.leerToken() },
            transports: ["websocket"]
        });

        // TambiÃ©n corre al reconectarse: vuelve a pedir la cola completa.
        socket.on("connect", () => {
            mostrarMensaje("mensaje-sos", "");

            socket.emit("sos:retomar", {}, respuesta => {
                console.log("Respuesta de sos:retomar:", respuesta);

                if (respuesta && respuesta.error) {
                    mostrarMensaje("mensaje-sos", respuesta.error, "error");
                    return;
                }

                if (respuesta && respuesta.sesion) {
                    mostrarAtencion(respuesta);

                    socket.emit("webrtc:pedir_oferta", {
                        sesion: respuesta.sesion
                    });
                } else if (sesionAtendida) {
                    terminarAtencion(
                        `El SOS #${sesionAtendida} ya no estÃ¡ en curso.`
                    );
                }
            });

            cargarCola();
        });

        socket.on("connect_error", () => {
            mostrarMensaje("mensaje-sos", "Sin conexiÃ³n con el servidor de SOS. Reintentando...", "error");
        });

        // LlegÃ³ una emergencia nueva: se agrega al final de la cola.
        socket.on("sos:nueva", sos => {
            if (!cola.some(item => item.sesion === sos.sesion)) cola.push(sos);
            pintarCola();
        });

        // La cancelÃ³ el ciudadano o la tomÃ³ otro operador: sale de la cola.
        socket.on("sos:retirada", datos => {
            cola = cola.filter(item => item.sesion !== datos.sesion);
            pintarCola();
        });

        // El ciudadano enviÃ³ su offer: el operador responde.
        socket.on("webrtc:offer", datos => {
            if (!datos.sdp) return;
            if (sesionAtendida === null) {
                ofertaPendiente = datos;   // llegÃ³ antes de terminar "Atender"
                return;
            }
            if (datos.sesion === sesionAtendida) responderOferta(datos);
        });

        // Candidatos ICE del ciudadano.
        socket.on("webrtc:ice", async datos => {
            if (!datos.candidato) return;
            if (!conexion || !conexion.remoteDescription) {
                candidatosPendientes.push(datos.candidato);   // todavÃ­a no se pueden usar
                return;
            }
            if (datos.sesion !== sesionAtendida) return;
            try {
                await conexion.addIceCandidate(datos.candidato);
            } catch (error) {
                console.error("SOS en vivo: candidato ICE no vÃ¡lido", error);
            }
        });

        // El ciudadano colgÃ³.
        socket.on("sos:finalizada", datos => {
            if (datos.sesion !== sesionAtendida) return;
            terminarAtencion(`El ciudadano colgÃ³ la llamada. SOS #${datos.sesion} finalizado Â· duraciÃ³n ${formatoDuracion(datos.duracion)}.`);
        });

        // Recibir la ubicaciÃ³n GPS que envÃ­a el ciudadano.
        socket.on("sos:ubicacion", punto => {
            if (punto.sesion === sesionAtendida) {
                pintarUbicacion(punto);
            }

          const enCola = cola.find(item => item.sesion === punto.sesion);

            if (enCola) {
                enCola.lat = punto.lat;
                enCola.lng = punto.lng;
                enCola.precision = punto.precision;
                pintarCola();
            }
        });
    }

    /* ---------- Atender ---------- */

    lista.addEventListener("click", evento => {
        const boton = evento.target.closest("[data-atender]");
        if (!boton || sesionAtendida) return;
        boton.disabled = true;
        socket.emit("sos:aceptar", { sesion: Number(boton.dataset.atender) }, respuesta => {
            if (respuesta.error) {
                // Otro operador la tomÃ³ primero (asignaciÃ³n atÃ³mica del servidor).
                mostrarMensaje("mensaje-sos", respuesta.error, "error");
                boton.disabled = false;
                cargarCola();
                return;
            }
            mostrarMensaje("mensaje-sos", `EstÃ¡s atendiendo el SOS #${respuesta.sesion}.`, "exito");
            mostrarAtencion(respuesta);
        });
    });

    /* ---------- Finalizar llamada ---------- */

    document.getElementById("sos-finalizar").addEventListener("click", () => {
        if (!sesionAtendida) return;
        if (!window.confirm(`Â¿Desea finalizar la llamada y cerrar el SOS #${sesionAtendida}?`)) return;
        const sesion = sesionAtendida;
        socket.emit("sos:finalizar", { sesion }, respuesta => {
            if (respuesta && respuesta.ok) {
                terminarAtencion(`SOS #${sesion} finalizado Â· duraciÃ³n ${formatoDuracion(respuesta.duracion)}.`);
            } else {
                mostrarMensaje("mensaje-sos", (respuesta && respuesta.error) || "No se pudo finalizar.", "error");
            }
        });
    });

    // La conexiÃ³n se abre la primera vez que el operador entra a la pestaÃ±a.
    A.registrarSeccion("sos", conectar);
})();
