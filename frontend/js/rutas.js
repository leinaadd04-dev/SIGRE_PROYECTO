/* SIGRE · Rutas de evacuación
   - Elegir partida y destino: GPS, tocando el mapa o buscando una dirección.
   - Calcular en Flask la ruta más corta y la más segura (backend/rutas.py).
   - Guardar rutas en la cuenta y compartirlas.
   Medios de transporte: a pie (red peatonal) o carro y moto (red vial).
   Parámetros de URL: ?o=lat,lon&d=lat,lon&modo=pie|carro|moto (abre y calcula)
   o ?ruta=ID (ruta guardada). */
(() => {
    const API_BASE = window.SIGRE_API;   // js/config.js
    const CENTRO_MONTERIA = [8.757, -75.884];
    const COLOR_SEGURA = "#2e7d32";
    const COLOR_CORTA = "#e76f51";
    const MODOS = {
        pie: { texto: "A pie", tiempo: "caminando", icono: "fa-person-walking", google: "walking" },
        carro: { texto: "Carro", tiempo: "en carro", icono: "fa-car-side", google: "driving" },
        moto: { texto: "Moto", tiempo: "en moto", icono: "fa-motorcycle", google: "driving" }
    };

    const elementos = {
        estadoRed: document.getElementById("estado-red"),
        mensaje: document.getElementById("mensaje_ruta"),
        botonCalcular: document.getElementById("calcular_ruta"),
        incluirDemo: document.getElementById("incluir-demo"),
        botonUbicacion: document.getElementById("boton-mi-ubicacion"),
        botonIntercambiar: document.getElementById("boton-intercambiar"),
        resultados: document.getElementById("resultados-rutas"),
        resumen: document.getElementById("resumen-rutas"),
        tarjetas: document.getElementById("tarjetas-rutas"),
        nombreRuta: document.getElementById("nombre-ruta"),
        botonGuardar: document.getElementById("boton-guardar-ruta"),
        botonCompartir: document.getElementById("boton-compartir-ruta"),
        mensajeGuardar: document.getElementById("mensaje-guardar"),
        estadoGuardadas: document.getElementById("estado-guardadas"),
        listaGuardadas: document.getElementById("lista-rutas-guardadas")
    };

    const puntos = {
        origen: { input: document.getElementById("punto_origen"), lista: document.getElementById("sugerencias-origen"), valor: null, marcador: null, letra: "A" },
        destino: { input: document.getElementById("punto_destino"), lista: document.getElementById("sugerencias-destino"), valor: null, marcador: null, letra: "B" }
    };

    let mapa = null;
    let capaRutas = null;
    let modoEleccion = null;
    let redLista = false;
    let ultimoResultado = null;
    let rutasGuardadas = [];
    let calcularAlEstarLista = false;
    let consultaRed = 0;

    /* ---------- Medio de transporte ---------- */

    const opcionesModo = document.querySelectorAll('input[name="modo_ruta"]');
    const notaModo = document.getElementById("nota-modo-ruta");

    function modoActual() {
        const elegido = document.querySelector('input[name="modo_ruta"]:checked');
        return elegido && MODOS[elegido.value] ? elegido.value : "pie";
    }

    function elegirModo(modo) {
        const opcion = document.querySelector(`input[name="modo_ruta"][value="${MODOS[modo] ? modo : "pie"}"]`);
        if (opcion) opcion.checked = true;
        alCambiarModo();
    }

    function alCambiarModo() {
        notaModo.hidden = modoActual() === "pie";
        limpiarResultado();
        redLista = false;
        revisarRed();
    }

    opcionesModo.forEach(function (opcion) {
        opcion.addEventListener("change", alCambiarModo);
    });

    /* ---------- Utilidades ---------- */

    function leerToken() {
        try {
            return localStorage.getItem("sigre_token");
        } catch (error) {
            return null;
        }
    }

    function mostrarMensaje(elemento, texto, tipo) {
        elemento.textContent = texto;
        elemento.classList.remove("error", "exito");
        if (tipo) elemento.classList.add(tipo);
    }

    function formatearDistancia(metros) {
        return metros >= 1000
            ? `${(metros / 1000).toLocaleString("es-CO", { maximumFractionDigits: 1 })} km`
            : `${metros} m`;
    }

    function textoCorto(texto) {
        const completo = String(texto || "");
        if (completo.indexOf("Punto en el mapa") === 0) return "Punto en el mapa";
        return completo.split(",").slice(0, 2).join(",").trim();
    }

    function textoCoordenadas(punto) {
        return `Punto en el mapa (${punto.lat.toFixed(5)}, ${punto.lon.toFixed(5)})`;
    }

    async function leerError(respuesta, porDefecto) {
        try {
            return (await respuesta.json()).error || porDefecto;
        } catch (error) {
            return porDefecto;
        }
    }

    function errorConexion(error, porDefecto) {
        return error instanceof TypeError
            ? "No se pudo conectar con el servidor de SIGRE. Verifica que Flask esté en ejecución."
            : error.message || porDefecto;
    }

    /* ---------- Mapa ---------- */

    function iconoPunto(letra, clase) {
        return L.divIcon({
            className: "marcador_ruta " + clase,
            html: `<span>${letra}</span>`,
            iconSize: [34, 34],
            iconAnchor: [17, 34]
        });
    }

    function iniciarMapa() {
        if (!window.L) {
            document.getElementById("mapa-rutas").textContent =
                "No se pudo cargar el mapa. Revisa tu conexión a internet y recarga la página.";
            return;
        }
        mapa = L.map("mapa-rutas").setView(CENTRO_MONTERIA, 13);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            attribution: "&copy; OpenStreetMap contributors",
            maxZoom: 19
        }).addTo(mapa);
        capaRutas = L.layerGroup().addTo(mapa);

        mapa.on("click", function (evento) {
            const tipo = modoEleccion
                || (!puntos.origen.valor ? "origen" : "destino");
            fijarPunto(tipo, {
                lat: evento.latlng.lat,
                lon: evento.latlng.lng,
                texto: null
            });
            terminarEleccion();
        });
    }

    async function cargarZonas() {
        if (!mapa) return;
        try {
            const respuesta = await fetch(API_BASE + "/api/rutas/zonas");
            if (!respuesta.ok) return;
            (await respuesta.json()).forEach(function (zona) {
                L.polygon(zona.coordenadas, zona.demo
                    ? { color: "#d9682b", weight: 2, dashArray: "6 6", fillColor: "#f4a261", fillOpacity: 0.18 }
                    : { color: "#d62839", weight: 2, fillColor: "#e63946", fillOpacity: 0.22 })
                    .bindPopup(`<strong>${zona.nombre}</strong><br>${zona.descripcion}`
                        + (zona.demo ? "" : "<br><em>Zona aproximada, no oficial.</em>"))
                    .addTo(mapa);
            });
        } catch (error) {
            // Sin zonas el mapa sigue sirviendo para elegir puntos.
        }
    }

    /* ---------- Puntos ---------- */

    function fijarPunto(tipo, valor) {
        const punto = puntos[tipo];
        punto.valor = {
            lat: Number(valor.lat),
            lon: Number(valor.lon),
            texto: valor.texto || textoCoordenadas({ lat: Number(valor.lat), lon: Number(valor.lon) })
        };
        punto.input.value = valor.texto ? textoCorto(valor.texto) : punto.valor.texto;
        ocultarSugerencias(punto);

        if (mapa) {
            const posicion = [punto.valor.lat, punto.valor.lon];
            if (punto.marcador) {
                punto.marcador.setLatLng(posicion);
            } else {
                punto.marcador = L.marker(posicion, {
                    draggable: true,
                    icon: iconoPunto(punto.letra, tipo === "origen" ? "marcador_origen" : "marcador_destino")
                }).addTo(mapa);
                punto.marcador.on("dragend", function () {
                    const nueva = punto.marcador.getLatLng();
                    fijarPunto(tipo, { lat: nueva.lat, lon: nueva.lng, texto: null });
                });
            }
        }
        limpiarResultado();
    }

    function quitarPunto(tipo) {
        const punto = puntos[tipo];
        punto.valor = null;
        if (punto.marcador && mapa) mapa.removeLayer(punto.marcador);
        punto.marcador = null;
    }

    function empezarEleccion(tipo) {
        modoEleccion = tipo;
        document.getElementById("mapa-rutas").classList.add("eligiendo");
        mostrarMensaje(elementos.mensaje, `Toca el mapa para marcar ${tipo === "origen" ? "la partida (A)" : "el destino (B)"}.`);
        document.getElementById("mapa-rutas").scrollIntoView({ behavior: "smooth", block: "center" });
    }

    function terminarEleccion() {
        modoEleccion = null;
        document.getElementById("mapa-rutas").classList.remove("eligiendo");
        if (!elementos.mensaje.classList.contains("error")) mostrarMensaje(elementos.mensaje, "");
    }

    document.querySelectorAll("[data-elegir]").forEach(function (boton) {
        boton.addEventListener("click", function () {
            empezarEleccion(boton.getAttribute("data-elegir"));
        });
    });

    elementos.botonUbicacion.addEventListener("click", function () {
        if (!("geolocation" in navigator)) {
            mostrarMensaje(elementos.mensaje, "Tu navegador no permite obtener la ubicación. Elige la partida en el mapa.", "error");
            return;
        }
        elementos.botonUbicacion.disabled = true;
        mostrarMensaje(elementos.mensaje, "Obteniendo tu ubicación...");
        navigator.geolocation.getCurrentPosition(
            function (posicion) {
                elementos.botonUbicacion.disabled = false;
                fijarPunto("origen", {
                    lat: posicion.coords.latitude,
                    lon: posicion.coords.longitude,
                    texto: "Mi ubicación"
                });
                if (mapa) mapa.setView([posicion.coords.latitude, posicion.coords.longitude], 15);
                mostrarMensaje(elementos.mensaje, "");
            },
            function () {
                elementos.botonUbicacion.disabled = false;
                mostrarMensaje(elementos.mensaje, "No se pudo obtener tu ubicación. Revisa los permisos o elige la partida en el mapa.", "error");
            },
            { enableHighAccuracy: true, timeout: 10000 }
        );
    });

    elementos.botonIntercambiar.addEventListener("click", function () {
        const origen = puntos.origen.valor;
        const destino = puntos.destino.valor;
        quitarPunto("origen");
        quitarPunto("destino");
        puntos.origen.input.value = "";
        puntos.destino.input.value = "";
        if (destino) fijarPunto("origen", destino);
        if (origen) fijarPunto("destino", origen);
    });

    /* ---------- Búsqueda de direcciones ---------- */

    function ocultarSugerencias(punto) {
        punto.lista.hidden = true;
        punto.lista.innerHTML = "";
        punto.input.removeAttribute("aria-expanded");
    }

    function mostrarSugerencias(tipo, resultados, aviso) {
        const punto = puntos[tipo];
        punto.lista.innerHTML = "";
        if (aviso) {
            const item = document.createElement("li");
            item.className = "sugerencia_aviso";
            item.textContent = aviso;
            punto.lista.appendChild(item);
        }
        resultados.forEach(function (lugar) {
            const item = document.createElement("li");
            const boton = document.createElement("button");
            boton.type = "button";
            boton.setAttribute("role", "option");
            boton.innerHTML = '<i class="fa-solid fa-location-dot"></i>';
            boton.appendChild(document.createTextNode(" " + lugar.nombre));
            boton.addEventListener("click", function () {
                fijarPunto(tipo, { lat: lugar.lat, lon: lugar.lon, texto: lugar.nombre });
                if (mapa) mapa.setView([lugar.lat, lugar.lon], 16);
            });
            item.appendChild(boton);
            punto.lista.appendChild(item);
        });
        punto.lista.hidden = !punto.lista.children.length;
        punto.input.setAttribute("aria-expanded", punto.lista.hidden ? "false" : "true");
    }

    Object.keys(puntos).forEach(function (tipo) {
        const punto = puntos[tipo];
        let temporizador = null;
        let consulta = 0;

        punto.input.addEventListener("input", function () {
            clearTimeout(temporizador);
            const texto = punto.input.value.trim();
            if (punto.valor) quitarPunto(tipo);
            limpiarResultado();
            if (texto.length < 3) {
                ocultarSugerencias(punto);
                return;
            }
            // Espera a que la persona deje de escribir (Nominatim pide pocas consultas).
            temporizador = setTimeout(async function () {
                const numero = ++consulta;
                mostrarSugerencias(tipo, [], "Buscando...");
                try {
                    const respuesta = await fetch(`${API_BASE}/api/rutas/buscar?q=${encodeURIComponent(texto)}`);
                    if (numero !== consulta) return;
                    if (!respuesta.ok) throw new Error(await leerError(respuesta, "No se pudo buscar la dirección."));
                    const resultados = await respuesta.json();
                    mostrarSugerencias(tipo, resultados, resultados.length ? "" : "Sin resultados en Montería. Prueba otra dirección o elige en el mapa.");
                } catch (error) {
                    if (numero === consulta) mostrarSugerencias(tipo, [], errorConexion(error, "No se pudo buscar la dirección."));
                }
            }, 700);
        });

        punto.input.addEventListener("keydown", function (evento) {
            if (evento.key === "Escape") ocultarSugerencias(punto);
            if (evento.key === "Enter") {
                evento.preventDefault();
                const primera = punto.lista.querySelector("button");
                if (primera) primera.click();
            }
        });
    });

    document.addEventListener("click", function (evento) {
        Object.keys(puntos).forEach(function (tipo) {
            const punto = puntos[tipo];
            if (!punto.lista.contains(evento.target) && evento.target !== punto.input) ocultarSugerencias(punto);
        });
    });

    /* ---------- Estado de la red de calles ---------- */

    function pintarEstadoRed(texto, clase, icono) {
        elementos.estadoRed.className = "estado_red " + clase;
        elementos.estadoRed.innerHTML = `<i class="fa-solid ${icono}"></i>`;
        elementos.estadoRed.appendChild(document.createTextNode(" " + texto));
    }

    async function revisarRed() {
        const numero = ++consultaRed;
        const modo = modoActual();
        try {
            const respuesta = await fetch(`${API_BASE}/api/rutas/estado?modo=${encodeURIComponent(modo)}`);
            const estado = await respuesta.json();
            if (numero !== consultaRed) return;
            if (estado.listo) {
                redLista = true;
                pintarEstadoRed(modo === "pie" ? "Mapa de calles listo" : "Mapa de vías para vehículos listo", "listo", "fa-circle-check");
                if (calcularAlEstarLista) {
                    calcularAlEstarLista = false;
                    calcularRuta();
                }
                return;
            }
            if (estado.error) {
                pintarEstadoRed(estado.error, "error", "fa-triangle-exclamation");
                return;
            }
            pintarEstadoRed(
                modo === "pie"
                    ? "Preparando el mapa de calles de Montería (la primera vez tarda 1 o 2 minutos)..."
                    : "Preparando el mapa de vías para carro y moto (la primera vez tarda 2 o 3 minutos)...",
                "cargando", "fa-spinner fa-spin"
            );
            setTimeout(function () { if (numero === consultaRed) revisarRed(); }, 4000);
        } catch (error) {
            if (numero !== consultaRed) return;
            pintarEstadoRed("Sin conexión con el servidor de SIGRE. ¿Está Flask en ejecución?", "error", "fa-plug-circle-xmark");
            setTimeout(function () { if (numero === consultaRed) revisarRed(); }, 8000);
        }
    }

    /* ---------- Cálculo ---------- */

    function limpiarResultado() {
        ultimoResultado = null;
        if (capaRutas) capaRutas.clearLayers();
        elementos.resultados.hidden = true;
    }

    function tarjetaRuta(ruta, clase, titulo, icono, descripcion, textoTiempo) {
        const riesgo = ruta.metros_riesgo > 0
            ? `<span class="dato_riesgo alto"><i class="fa-solid fa-triangle-exclamation"></i> ${formatearDistancia(ruta.metros_riesgo)} en zona de riesgo</span>`
            : `<span class="dato_riesgo bajo"><i class="fa-solid fa-shield-halved"></i> No cruza zonas de riesgo${ruta.metros_demo > 0 ? " reales" : ""}</span>`;
        const demo = ruta.metros_demo > 0
            ? `<span class="dato_riesgo demo"><i class="fa-solid fa-flask"></i> ${formatearDistancia(ruta.metros_demo)} en la zona de demostración</span>`
            : "";
        return `
            <article class="tarjeta_ruta ${clase}">
                <h4><i class="muestra_linea"></i><i class="fa-solid ${icono}"></i> ${titulo}</h4>
                <p class="descripcion_ruta">${descripcion}</p>
                <div class="datos_ruta">
                    <span><strong>${formatearDistancia(ruta.distancia_m)}</strong>distancia</span>
                    <span><strong>${ruta.tiempo_min} min</strong>${textoTiempo}</span>
                </div>
                ${riesgo}
                ${demo}
            </article>
        `;
    }

    function dibujarResultado(resultado) {
        if (!mapa) return;
        capaRutas.clearLayers();
        // La segura va debajo y más gruesa; la corta encima y punteada:
        // así se ven las dos aunque compartan calles.
        const segura = L.polyline(resultado.segura.coordenadas, {
            color: COLOR_SEGURA, weight: 9, opacity: 0.85
        }).bindTooltip(`Ruta más segura: ${formatearDistancia(resultado.segura.distancia_m)}`).addTo(capaRutas);
        let limites = segura.getBounds();
        if (!resultado.misma_ruta) {
            const corta = L.polyline(resultado.corta.coordenadas, {
                color: COLOR_CORTA, weight: 5, opacity: 0.95, dashArray: "10 8"
            }).bindTooltip(`Ruta más corta: ${formatearDistancia(resultado.corta.distancia_m)}`).addTo(capaRutas);
            limites = limites.extend(corta.getBounds());
        }
        mapa.fitBounds(limites, { padding: [40, 40] });
    }

    function mostrarResultado(resultado) {
        ultimoResultado = resultado;
        dibujarResultado(resultado);

        const extra = resultado.segura.distancia_m - resultado.corta.distancia_m;
        elementos.resumen.textContent = resultado.misma_ruta
            ? "La ruta más corta ya evita las zonas de riesgo, así que es la ruta recomendada."
            : `La ruta más segura es ${formatearDistancia(extra)} más larga (unos ${Math.max(1, resultado.segura.tiempo_min - resultado.corta.tiempo_min)} min más), pero evita las zonas marcadas en el mapa.`;

        const modo = MODOS[resultado.modo] || MODOS.pie;
        elementos.tarjetas.innerHTML = tarjetaRuta(
            resultado.segura, "ruta_segura", "Ruta más segura (recomendada)", "fa-shield-halved",
            "Combina distancia y riesgo: busca el camino más corto, pero cada metro dentro de una zona de riesgo cuenta como 100, así que solo la cruza si no hay otra opción razonable.",
            modo.tiempo
        ) + (resultado.misma_ruta ? "" : tarjetaRuta(
            resultado.corta, "ruta_corta", "Ruta más corta", modo.icono,
            "Solo mide distancia: el camino más corto aunque cruce zonas de riesgo.",
            modo.tiempo
        ));

        if (!elementos.nombreRuta.value) {
            elementos.nombreRuta.value = `${textoCorto(puntos.origen.valor.texto)} → ${textoCorto(puntos.destino.valor.texto)}`.slice(0, 80);
        }
        mostrarMensaje(elementos.mensajeGuardar, "");
        elementos.resultados.hidden = false;
    }

    async function calcularRuta() {
        if (!puntos.origen.valor || !puntos.destino.valor) {
            mostrarMensaje(elementos.mensaje,
                !puntos.origen.valor ? "Elige el punto de partida (A)." : "Elige el punto de destino (B).", "error");
            return;
        }
        if (!redLista) {
            calcularAlEstarLista = true;
            mostrarMensaje(elementos.mensaje, "El mapa de calles se está preparando; calcularemos la ruta apenas esté listo.");
            return;
        }

        const contenido = elementos.botonCalcular.innerHTML;
        elementos.botonCalcular.disabled = true;
        elementos.botonCalcular.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Calculando...';
        mostrarMensaje(elementos.mensaje, "Calculando la ruta por las calles de Montería...");

        try {
            const respuesta = await fetch(API_BASE + "/api/rutas/calcular", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    origen: { lat: puntos.origen.valor.lat, lon: puntos.origen.valor.lon },
                    destino: { lat: puntos.destino.valor.lat, lon: puntos.destino.valor.lon },
                    incluir_demo: elementos.incluirDemo.checked,
                    modo: modoActual()
                })
            });
            if (!respuesta.ok) throw new Error(await leerError(respuesta, "No se pudo calcular la ruta."));
            mostrarResultado(await respuesta.json());
            mostrarMensaje(elementos.mensaje, "");
            elementos.resultados.scrollIntoView({ behavior: "smooth", block: "nearest" });
        } catch (error) {
            mostrarMensaje(elementos.mensaje, errorConexion(error, "No se pudo calcular la ruta."), "error");
        } finally {
            elementos.botonCalcular.disabled = false;
            elementos.botonCalcular.innerHTML = contenido;
        }
    }

    elementos.botonCalcular.addEventListener("click", calcularRuta);
    elementos.incluirDemo.addEventListener("change", function () {
        if (ultimoResultado) calcularRuta();
    });

    /* ---------- Compartir ---------- */

    function enlaceSigre(origen, destino, incluyeDemo, modo) {
        const url = new URL(window.location.href);
        url.search = "";
        url.searchParams.set("o", `${origen.lat.toFixed(6)},${origen.lon.toFixed(6)}`);
        url.searchParams.set("d", `${destino.lat.toFixed(6)},${destino.lon.toFixed(6)}`);
        if (incluyeDemo) url.searchParams.set("demo", "1");
        url.searchParams.set("modo", modo);
        return url.toString();
    }

    async function compartirRuta(nombre, origen, destino, distancia, tiempo, incluyeDemo, modoRuta) {
        const modo = MODOS[modoRuta] ? modoRuta : "pie";
        const texto = [
            `Ruta de evacuación SIGRE (${MODOS[modo].texto.toLowerCase()}): ${nombre}`,
            `Desde: ${textoCorto(origen.texto)}`,
            `Hasta: ${textoCorto(destino.texto)}`,
            `Distancia: ${formatearDistancia(distancia)} (unos ${tiempo} min ${MODOS[modo].tiempo})`,
            `Ver en SIGRE: ${enlaceSigre(origen, destino, incluyeDemo, modo)}`,
            `Abrir en Google Maps: https://www.google.com/maps/dir/?api=1&origin=${origen.lat},${origen.lon}&destination=${destino.lat},${destino.lon}&travelmode=${MODOS[modo].google}`
        ].join("\n");

        if (navigator.share) {
            try {
                await navigator.share({ title: "Ruta de evacuación SIGRE", text: texto });
                return;
            } catch (error) {
                if (error.name === "AbortError") return;
            }
        }
        window.open("https://wa.me/?text=" + encodeURIComponent(texto), "_blank", "noopener");
    }

    elementos.botonCompartir.addEventListener("click", function () {
        if (!ultimoResultado) return;
        compartirRuta(
            elementos.nombreRuta.value.trim() || "Ruta",
            puntos.origen.valor, puntos.destino.valor,
            ultimoResultado.segura.distancia_m, ultimoResultado.segura.tiempo_min,
            ultimoResultado.incluye_demo, ultimoResultado.modo
        );
    });

    /* ---------- Rutas guardadas ---------- */

    async function llamarApi(ruta, opciones) {
        const configuracion = Object.assign({}, opciones);
        configuracion.headers = Object.assign({}, configuracion.headers, {
            Authorization: "Bearer " + leerToken()
        });
        return fetch(API_BASE + ruta, configuracion);
    }

    elementos.botonGuardar.addEventListener("click", async function () {
        if (!ultimoResultado) return;
        if (!leerToken()) {
            mostrarMensaje(elementos.mensajeGuardar, "Inicia sesión para guardar rutas en tu cuenta.", "error");
            return;
        }
        const nombre = elementos.nombreRuta.value.trim();
        if (nombre.length < 2) {
            mostrarMensaje(elementos.mensajeGuardar, "Ponle un nombre a la ruta (mínimo 2 caracteres).", "error");
            elementos.nombreRuta.focus();
            return;
        }

        elementos.botonGuardar.disabled = true;
        mostrarMensaje(elementos.mensajeGuardar, "Guardando...");
        try {
            const segura = ultimoResultado.segura;
            const respuesta = await llamarApi("/api/rutas/guardadas", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    nombre: nombre,
                    origen: puntos.origen.valor,
                    destino: puntos.destino.valor,
                    incluye_demo: ultimoResultado.incluye_demo,
                    modo: ultimoResultado.modo,
                    distancia_m: segura.distancia_m,
                    tiempo_min: segura.tiempo_min,
                    metros_riesgo: segura.metros_riesgo,
                    geometria: segura.coordenadas
                })
            });
            if (respuesta.status === 401 || respuesta.status === 422) {
                throw new Error("Tu sesión expiró. Inicia sesión de nuevo para guardar rutas.");
            }
            if (!respuesta.ok) throw new Error(await leerError(respuesta, "No se pudo guardar la ruta. Revisa que la migración de rutas esté aplicada."));
            mostrarMensaje(elementos.mensajeGuardar, "Ruta guardada. También aparece en \"Tus guardados\" del inicio.", "exito");
            cargarGuardadas();
        } catch (error) {
            mostrarMensaje(elementos.mensajeGuardar, errorConexion(error, "No se pudo guardar la ruta."), "error");
        } finally {
            elementos.botonGuardar.disabled = false;
        }
    });

    function verRutaGuardada(ruta) {
        elegirModo(ruta.modo || "pie");
        quitarPunto("origen");
        quitarPunto("destino");
        fijarPunto("origen", ruta.origen);
        fijarPunto("destino", ruta.destino);
        elementos.incluirDemo.checked = ruta.incluye_demo;
        elementos.nombreRuta.value = ruta.nombre;
        if (mapa) {
            capaRutas.clearLayers();
            const linea = L.polyline(ruta.geometria, { color: COLOR_SEGURA, weight: 8, opacity: 0.9 })
                .bindTooltip(ruta.nombre).addTo(capaRutas);
            mapa.fitBounds(linea.getBounds(), { padding: [40, 40] });
            document.getElementById("mapa-rutas").scrollIntoView({ behavior: "smooth", block: "center" });
        }
        mostrarMensaje(elementos.mensaje, `Mostrando "${ruta.nombre}". Pulsa "Calcular ruta" para recalcularla y compararla.`);
    }

    function renderizarGuardadas() {
        elementos.listaGuardadas.innerHTML = "";
        if (!rutasGuardadas.length) {
            elementos.estadoGuardadas.hidden = false;
            elementos.estadoGuardadas.textContent = "Aún no tienes rutas guardadas. Calcula una y pulsa \"Guardar\".";
            return;
        }
        elementos.estadoGuardadas.hidden = true;

        rutasGuardadas.forEach(function (ruta) {
            const item = document.createElement("li");
            item.className = "ruta_guardada";

            const datos = document.createElement("div");
            datos.className = "ruta_guardada_datos";
            const titulo = document.createElement("strong");
            titulo.textContent = ruta.nombre;
            const detalle = document.createElement("span");
            const modo = MODOS[ruta.modo] || MODOS.pie;
            detalle.textContent = `${modo.texto} · ${formatearDistancia(ruta.distancia_m)} · ${ruta.tiempo_min} min ${modo.tiempo} · `
                + new Date(ruta.creada_en).toLocaleDateString("es-CO", { day: "numeric", month: "short" });
            datos.append(titulo, detalle);

            const acciones = document.createElement("div");
            acciones.className = "ruta_guardada_acciones";
            const botones = [
                ["fa-eye", "Ver", function () { verRutaGuardada(ruta); }],
                ["fa-share-nodes", "Compartir", function () {
                    compartirRuta(ruta.nombre, ruta.origen, ruta.destino, ruta.distancia_m, ruta.tiempo_min, ruta.incluye_demo, ruta.modo);
                }],
                ["fa-trash", "Eliminar", function () { eliminarGuardada(ruta); }]
            ];
            botones.forEach(function (datosBoton) {
                const boton = document.createElement("button");
                boton.type = "button";
                boton.className = "boton_punto" + (datosBoton[1] === "Eliminar" ? " boton_peligro" : "");
                boton.innerHTML = `<i class="fa-solid ${datosBoton[0]}"></i>`;
                boton.appendChild(document.createTextNode(" " + datosBoton[1]));
                boton.addEventListener("click", datosBoton[2]);
                acciones.appendChild(boton);
            });

            item.append(datos, acciones);
            elementos.listaGuardadas.appendChild(item);
        });
    }

    async function eliminarGuardada(ruta) {
        if (!window.confirm(`¿Eliminar la ruta "${ruta.nombre}"?`)) return;
        try {
            const respuesta = await llamarApi(`/api/rutas/guardadas/${ruta.id}/eliminar`, { method: "POST" });
            if (!respuesta.ok) throw new Error(await leerError(respuesta, "No se pudo eliminar la ruta."));
            rutasGuardadas = rutasGuardadas.filter(function (otra) { return otra.id !== ruta.id; });
            renderizarGuardadas();
        } catch (error) {
            window.alert(errorConexion(error, "No se pudo eliminar la ruta."));
        }
    }

    async function cargarGuardadas() {
        if (!leerToken()) {
            elementos.estadoGuardadas.textContent = "Inicia sesión para guardar tus rutas y verlas aquí.";
            return null;
        }
        try {
            const respuesta = await llamarApi("/api/rutas/guardadas");
            if (respuesta.status === 401 || respuesta.status === 422) {
                elementos.estadoGuardadas.textContent = "Tu sesión expiró. Inicia sesión de nuevo para ver tus rutas.";
                return null;
            }
            if (!respuesta.ok) throw new Error(await leerError(respuesta, "No se pudieron cargar tus rutas. Revisa que la migración de rutas esté aplicada."));
            rutasGuardadas = await respuesta.json();
            renderizarGuardadas();
            return rutasGuardadas;
        } catch (error) {
            elementos.estadoGuardadas.textContent = errorConexion(error, "No se pudieron cargar tus rutas.");
            return null;
        }
    }

    /* ---------- Inicio ---------- */

    function leerCoordenadas(texto) {
        const partes = String(texto || "").split(",").map(Number);
        return partes.length === 2 && partes.every(Number.isFinite)
            ? { lat: partes[0], lon: partes[1], texto: null }
            : null;
    }

    async function iniciar() {
        iniciarMapa();
        cargarZonas();

        const parametros = new URLSearchParams(window.location.search);
        elegirModo(parametros.get("modo") || "pie");
        const origen = leerCoordenadas(parametros.get("o"));
        const destino = leerCoordenadas(parametros.get("d"));
        if (origen && destino) {
            elementos.incluirDemo.checked = parametros.get("demo") === "1";
            fijarPunto("origen", origen);
            fijarPunto("destino", destino);
            calcularRuta();
        }

        const guardadas = await cargarGuardadas();
        const idRuta = Number(parametros.get("ruta"));
        if (guardadas && idRuta) {
            const ruta = guardadas.find(function (otra) { return otra.id === idRuta; });
            if (ruta) verRutaGuardada(ruta);
        }
    }

    iniciar();
})();
