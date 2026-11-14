/* SIGRE · Panel de administración: SOS en vivo (lado del operador).
   Paso 1: cola de emergencias en tiempo real y botón "Atender".
   Usa Socket.IO (el mismo servidor que js/sos_vivo.js) y las utilidades
   de js/admin.js (window.SigreAdmin). */
(() => {
    const A = window.SigreAdmin;
    if (!A || !window.io) return;
    const { htmlSafe, fecha, mostrarMensaje } = A;

    const lista = document.getElementById("lista-sos-cola");
    const contador = document.getElementById("contador-sos");
    const atencion = document.getElementById("sos-atencion");
    const cierre = document.getElementById("sos-cierre");
    const chatLista = document.getElementById("sos-chat-lista");

    let socket = null;
    let cola = [];             // emergencias en espera, en orden de llegada
    const urgentes = new Set();   // emergencias con alerta de pánico
    let sesionAtendida = null; // la que está atendiendo este operador

    // Videollamada (Paso 2)
    let conexion = null;            // RTCPeerConnection con el ciudadano
    let medios = null;              // cámara y micrófono del operador
    let candidatosPendientes = [];  // candidatos ICE que llegan antes de poder usarlos
    let ofertaPendiente = null;     // offer que llegó antes de terminar de "Atender"
    let cronometro = null;          // reloj de la duración de la llamada

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

        const ordenada = cola.slice().sort((a, b) => Number(urgentes.has(b.sesion)) - Number(urgentes.has(a.sesion)));
        lista.innerHTML = ordenada.map((sos, indice) => {
            const ubicacion = sos.lat != null
                ? `<i class="fa-solid fa-location-dot"></i> ${sos.lat.toFixed(5)}, ${sos.lng.toFixed(5)}` +
                  (sos.precision ? ` (±${Math.round(sos.precision)} m)` : "")
                : `<i class="fa-solid fa-triangle-exclamation"></i> Sin ubicación`;
            const urgente = urgentes.has(sos.sesion);
            return `<article class="admin_centro${urgente ? " urgente" : ""}">
                <span class="admin_centro_icono rojo"><i class="fa-solid fa-tower-broadcast"></i></span>
                <div class="admin_centro_datos">
                    <div class="admin_centro_cabecera">
                        <h4>SOS #${sos.sesion}</h4>
                        <span class="admin_chip ${urgente ? "urgente" : "activo"}">${urgente ? "URGENTE · pánico" : indice === 0 ? "Siguiente" : `En espera · ${indice + 1}°`}</span>
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

    // Cuenta desde que se aceptó la emergencia (hora del servidor), así no se
    // reinicia si se recarga la página.
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

    // Cierra la atención en el panel (la colgó el operador o el ciudadano).
    function terminarAtencion(texto) {
        detenerVideo();
        detenerCronometro();
        sesionAtendida = null;
        atencion.hidden = true;
        cierre.hidden = true;
        chatLista.replaceChildren();
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
                ${c.contacto_emergencia_telefono ? ` · <a href="tel:${htmlSafe(c.contacto_emergencia_telefono)}">${htmlSafe(c.contacto_emergencia_telefono)}</a>` : ""}</p>` : ""}`;
        atencion.hidden = false;
        chatLista.replaceChildren();
        iniciarCronometro(respuesta.atendida_en);

        limpiarMapa();
        prepararMapa();

        setTimeout(() => {
            if (mapa) mapa.invalidateSize();
        }, 100);

        pintarUbicacion(respuesta.ubicacion);

        pintarCola();   // mientras atiende, los demás botones "Atender" quedan desactivados
        // Si la offer del ciudadano llegó antes, se responde ahora.
        if (ofertaPendiente && ofertaPendiente.sesion === respuesta.sesion) {
            responderOferta(ofertaPendiente);
            ofertaPendiente = null;
        }
    }

    /* ---------- Videollamada (WebRTC) ---------- */

    /* ---------- Mapa con ubicación en vivo ---------- */

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
            (punto.precision ? ` · ±${Math.round(punto.precision)} m` : "") +
            (hora ? ` · actualizada ${hora}` : "");

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
            "Esperando la ubicación…";

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
            // Sin cámara se intenta solo con el micrófono.
            try {
                return await navigator.mediaDevices.getUserMedia({ audio: true });
            } catch (otroError) {
                return null;   // sin cámara ni micrófono: igual ve y oye al ciudadano
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
            // Si falla, se usa solo el STUN público.
        }
        return [{ urls: "stun:stun.l.google.com:19302" }];
    }

    // El ciudadano envía la offer; el operador responde con la answer.
    async function responderOferta(datos) {
        const sesion = datos.sesion;
        if (conexion) {        // si quedaba una llamada anterior (el ciudadano recargó)
            conexion.close();
            conexion = null;
        }
        estadoVideo("Conectando la videollamada…");
        try {
            const iceServers = await servidoresIce();
            if (!medios) medios = await pedirCamara();
            if (sesion !== sesionAtendida) return;   // se cerró mientras tanto

            conexion = new RTCPeerConnection({ iceServers });

            // Lo que el operador envía (si dio permiso).
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
                    disconnected: "Se cortó el video. Intentando reconectar…",
                    failed: "No se pudo conectar el video. Llama al ciudadano por teléfono."
                };
                if (mensajes[conexion.connectionState]) estadoVideo(mensajes[conexion.connectionState]);
            };

            await conexion.setRemoteDescription(datos.sdp);
            // Los candidatos que llegaron mientras se preparaba la conexión se agregan ahora.
            for (const candidato of candidatosPendientes) await conexion.addIceCandidate(candidato);
            candidatosPendientes = [];

            const respuesta = await conexion.createAnswer();
            await conexion.setLocalDescription(respuesta);
            socket.emit("webrtc:answer", { sesion, sdp: { type: respuesta.type, sdp: respuesta.sdp } });
        } catch (error) {
            console.error("SOS en vivo: no se pudo responder la videollamada", error);
            estadoVideo("No se pudo conectar el video. Llama al ciudadano por teléfono.");
        }
    }

    // Se usará en el Paso 4 al cerrar el caso.
    function detenerVideo() {
        candidatosPendientes = [];
        ofertaPendiente = null;
        if (conexion) {
            conexion.close();
            conexion = null;
        }
        if (medios) {
            medios.getTracks().forEach(pista => pista.stop());   // apaga la luz de la cámara
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
            cola.forEach(item => { if (item.urgente) urgentes.add(item.sesion); });
            pintarCola();
        });
    }

    function conectar() {
        if (socket) return;
        cargarEstadisticas();
        socket = io(window.SIGRE_API, {
            auth: { token: A.leerToken() },
            transports: ["websocket"]
        });

        // También corre al reconectarse: vuelve a pedir la cola completa.
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
                        `El SOS #${sesionAtendida} ya no está en curso.`
                    );
                }
            });

            cargarCola();
        });

        socket.on("connect_error", () => {
            mostrarMensaje("mensaje-sos", "Sin conexión con el servidor de SOS. Reintentando...", "error");
        });

        // Llegó una emergencia nueva: se agrega al final de la cola.
        socket.on("sos:nueva", sos => {
            if (!cola.some(item => item.sesion === sos.sesion)) cola.push(sos);
            pintarCola();
        });

        // La canceló el ciudadano o la tomó otro operador: sale de la cola.
        socket.on("sos:retirada", datos => {
            cola = cola.filter(item => item.sesion !== datos.sesion);
            urgentes.delete(datos.sesion);
            pintarCola();
        });

        // El ciudadano pulsó el botón de pánico: avisa con sonido y pasa al frente.
        socket.on("sos:panico", datos => {
            urgentes.add(datos.sesion);
            const enCola = cola.find(item => item.sesion === datos.sesion);
            if (enCola && datos.ubicacion) {
                enCola.lat = datos.ubicacion.lat;
                enCola.lng = datos.ubicacion.lng;
                enCola.precision = datos.ubicacion.precision;
            }
            pintarCola();
            mostrarAvisoPanico(datos);
            sonarAlerta();
        });

        // Mensaje de texto de la videollamada.
        socket.on("chat:mensaje", datos => {
            if (datos.sesion !== sesionAtendida) return;
            agregarMensajeChat(datos.de === "operador" ? "mio" : "otro", datos.texto);
        });

        // El ciudadano envió su offer: el operador responde.
        socket.on("webrtc:offer", datos => {
            if (!datos.sdp) return;
            if (sesionAtendida === null) {
                ofertaPendiente = datos;   // llegó antes de terminar "Atender"
                return;
            }
            if (datos.sesion === sesionAtendida) responderOferta(datos);
        });

        // Candidatos ICE del ciudadano.
        socket.on("webrtc:ice", async datos => {
            if (!datos.candidato) return;
            if (!conexion || !conexion.remoteDescription) {
                candidatosPendientes.push(datos.candidato);   // todavía no se pueden usar
                return;
            }
            if (datos.sesion !== sesionAtendida) return;
            try {
                await conexion.addIceCandidate(datos.candidato);
            } catch (error) {
                console.error("SOS en vivo: candidato ICE no válido", error);
            }
        });

        // El ciudadano colgó.
        socket.on("sos:finalizada", datos => {
            if (datos.sesion !== sesionAtendida) return;
            terminarAtencion(`El ciudadano colgó la llamada. SOS #${datos.sesion} finalizado · duración ${formatoDuracion(datos.duracion)}.`);
        });

        // Recibir la ubicación GPS que envía el ciudadano.
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

    /* ---------- Pánico y chat ---------- */

    function sonarAlerta() {
        try {
            const audio = new (window.AudioContext || window.webkitAudioContext)();
            [0, 0.25, 0.5].forEach(retraso => {
                const tono = audio.createOscillator();
                const volumen = audio.createGain();
                tono.frequency.value = 880;
                volumen.gain.value = 0.15;
                tono.connect(volumen);
                volumen.connect(audio.destination);
                tono.start(audio.currentTime + retraso);
                tono.stop(audio.currentTime + retraso + 0.15);
            });
        } catch (error) { /* sin audio disponible */ }
    }

    function mostrarAvisoPanico(datos) {
        const propio = datos.sesion === sesionAtendida;
        document.getElementById("sos-panico-titulo").textContent = `PÁNICO · SOS #${datos.sesion}`;
        document.getElementById("sos-panico-detalle").textContent = propio
            ? " El ciudadano que atiendes pulsó el botón de pánico."
            : " El ciudadano no puede explicar por llamada. Atiéndelo primero.";
        const enlace = document.getElementById("sos-panico-enlace");
        enlace.hidden = !datos.ubicacion;
        if (datos.ubicacion) enlace.href = `https://www.google.com/maps?q=${datos.ubicacion.lat},${datos.ubicacion.lng}`;
        document.getElementById("sos-panico-aviso").hidden = false;
    }

    document.getElementById("sos-panico-cerrar").addEventListener("click", () => {
        document.getElementById("sos-panico-aviso").hidden = true;
    });

    function agregarMensajeChat(clase, texto) {
        const elemento = document.createElement("li");
        elemento.className = clase;
        elemento.textContent = texto;
        chatLista.appendChild(elemento);
        chatLista.scrollTop = chatLista.scrollHeight;
    }

    document.getElementById("sos-chat-form").addEventListener("submit", evento => {
        evento.preventDefault();
        const campo = document.getElementById("sos-chat-texto");
        const texto = campo.value.trim();
        if (!texto || !sesionAtendida || !socket) return;
        socket.emit("chat:enviar", { sesion: sesionAtendida, texto }, respuesta => {
            if (respuesta && respuesta.ok) campo.value = "";
            else mostrarMensaje("mensaje-sos", (respuesta && respuesta.error) || "No se pudo enviar el mensaje.", "error");
        });
    });

    /* ---------- Atender ---------- */

    lista.addEventListener("click", evento => {
        const boton = evento.target.closest("[data-atender]");
        if (!boton || sesionAtendida) return;
        boton.disabled = true;
        socket.emit("sos:aceptar", { sesion: Number(boton.dataset.atender) }, respuesta => {
            if (respuesta.error) {
                // Otro operador la tomó primero (asignación atómica del servidor).
                mostrarMensaje("mensaje-sos", respuesta.error, "error");
                boton.disabled = false;
                cargarCola();
                return;
            }
            mostrarMensaje("mensaje-sos", `Estás atendiendo el SOS #${respuesta.sesion}.`, "exito");
            mostrarAtencion(respuesta);
        });
    });

    /* ---------- Estadísticas ---------- */

    // 125 -> "02:05"; 5400 -> "1 h 30 min"; 200000 -> "2 d 7 h"
    function duracionLarga(segundos) {
        const s = Math.max(0, Math.floor(Number(segundos) || 0));
        if (s < 3600) return formatoDuracion(s);
        const h = Math.floor(s / 3600);
        if (h < 48) return `${h} h ${String(Math.floor((s % 3600) / 60)).padStart(2, "0")} min`;
        return `${Math.floor(h / 24)} d ${h % 24} h`;
    }

    const DIAS_SEMANA = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];

    function graficaEstados(e) {
        const partes = [
            ["Finalizadas", e.finalizadas, "#2e9b62"],
            ["Canceladas", e.canceladas, "#8d99ae"],
            ["Abiertas", e.abiertas, "#e4a900"]
        ];
        const total = partes.reduce((suma, p) => suma + p[1], 0);
        let acumulado = 0;
        const tramos = partes.map(p => {
            const desde = acumulado;
            acumulado += total ? p[1] * 100 / total : 0;
            return `${p[2]} ${desde}% ${acumulado}%`;
        });
        const fondo = total ? `conic-gradient(${tramos.join(", ")})` : "#e3eaf1";
        return `<div class="admin_sos_grafico">
            <h4>Estado de los SOS</h4>
            <div class="sos_donut_fila">
                <div class="sos_donut" style="background:${fondo}"><strong>${total}</strong></div>
                <ul class="sos_leyenda">${partes.map(p =>
                    `<li><i style="background:${p[2]}"></i>${p[0]} <b>${p[1]}</b></li>`).join("")}</ul>
            </div>
        </div>`;
    }

    function graficaPorDia(e) {
        const dias = e.por_dia || [];
        const maximo = Math.max(1, ...dias.map(d => d.cantidad));
        return `<div class="admin_sos_grafico">
            <h4>SOS por día (últimos 7 días)</h4>
            <div class="sos_columnas">${dias.map(d => {
                const fecha = new Date(d.dia + "T12:00:00");
                return `<div class="sos_columna"><b>${d.cantidad}</b>` +
                    `<i style="height:${Math.max(4, Math.round(d.cantidad * 100 / maximo))}%"></i>` +
                    `<span>${DIAS_SEMANA[fecha.getDay()]} ${fecha.getDate()}</span></div>`;
            }).join("")}</div>
        </div>`;
    }

    const ETIQUETAS_RESULTADO = {
        atendida: "Atendida", falsa_alarma: "Falsa alarma", derivada: "Derivada",
        sin_respuesta: "Sin respuesta", sin_clasificar: "Sin clasificar"
    };

    async function cargarEstadisticas() {
        const kpis = document.getElementById("sos-kpis");
        try {
            const e = await A.llamarApi("/api/admin/sos/estadisticas");
            kpis.innerHTML = [
                ["Total de SOS", e.total],
                ["Finalizadas", e.finalizadas],
                ["Canceladas", e.canceladas],
                ["Espera promedio", duracionLarga(e.espera_promedio)],
                ["Duración promedio", duracionLarga(e.duracion_promedio)]
            ].map(([titulo, valor]) =>
                `<div class="admin_sos_kpi"><strong>${htmlSafe(String(valor))}</strong><span>${titulo}</span></div>`
            ).join("");

            document.getElementById("sos-graficos").innerHTML = graficaEstados(e) + graficaPorDia(e);

            const maximo = Math.max(1, ...e.resultados.map(r => r.cantidad));
            document.getElementById("sos-resultados").innerHTML =
                "<h4>Resultado de las atenciones</h4>" +
                (e.resultados.length
                    ? e.resultados.map(r =>
                        `<div class="admin_sos_barra"><span>${htmlSafe(ETIQUETAS_RESULTADO[r.resultado] || r.resultado)}</span>` +
                        `<div><i style="width:${Math.round(r.cantidad * 100 / maximo)}%"></i></div><b>${r.cantidad}</b></div>`
                    ).join("")
                    : "<p>Aún no hay atenciones cerradas.</p>");

            document.getElementById("sos-recientes").innerHTML =
                "<h4>Últimas atenciones</h4>" +
                (e.recientes.length
                    ? `<table class="admin_sos_tabla"><thead><tr><th>SOS</th><th>Fecha</th><th>Espera</th><th>Duración</th><th>Resultado</th><th>Nota</th></tr></thead><tbody>` +
                      e.recientes.map(f =>
                        `<tr><td>#${f.id}</td><td>${htmlSafe(fecha(f.creada_en, true))}</td><td>${duracionLarga(f.espera)}</td>` +
                        `<td>${duracionLarga(f.duracion)}</td><td>${htmlSafe(ETIQUETAS_RESULTADO[f.resultado] || "Sin clasificar")}</td>` +
                        `<td>${htmlSafe(f.nota || "—")}</td></tr>`
                      ).join("") + "</tbody></table>"
                    : "<p>Todavía no hay atenciones registradas.</p>");
        } catch (error) {
            kpis.textContent = "No se pudieron cargar las estadísticas.";
        }
    }


    /* ---------- Finalizar llamada ---------- */

    document.getElementById("sos-finalizar").addEventListener("click", () => {
        if (!sesionAtendida) return;
        cierre.hidden = false;
        cierre.scrollIntoView({ behavior: "smooth", block: "center" });
    });

    document.getElementById("sos-cierre-cancelar").addEventListener("click", () => {
        cierre.hidden = true;
    });

    document.getElementById("sos-cierre-confirmar").addEventListener("click", () => {
        if (!sesionAtendida) return;
        const sesion = sesionAtendida;
        const resultado = document.getElementById("sos-cierre-resultado").value;
        const nota = document.getElementById("sos-cierre-nota").value.trim();
        socket.emit("sos:finalizar", { sesion, resultado, nota }, respuesta => {
            if (respuesta && respuesta.ok) {
                document.getElementById("sos-cierre-nota").value = "";
                terminarAtencion(`SOS #${sesion} finalizado · duración ${formatoDuracion(respuesta.duracion)}.`);
                cargarEstadisticas();
            } else {
                mostrarMensaje("mensaje-sos", (respuesta && respuesta.error) || "No se pudo finalizar.", "error");
            }
        });
    });


    // La conexión se abre la primera vez que el operador entra a la pestaña.
    A.registrarSeccion("sos", conectar);
})();
