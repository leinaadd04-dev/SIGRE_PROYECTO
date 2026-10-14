/* SIGRE · Asistente virtual (chatbot de preguntas frecuentes) */
(() => {
    // ---------- Paso 3: el botón y la ventana ----------
    const boton = document.createElement("button");
    boton.type = "button";
    boton.className = "chat_boton";
    boton.setAttribute("aria-label", "Abrir el asistente de SIGRE");
    boton.innerHTML = '<i class="fa-solid fa-comment-dots"></i>';

    const ventana = document.createElement("section");
    ventana.className = "chat_ventana";
    ventana.setAttribute("aria-label", "Asistente de SIGRE");
    ventana.hidden = true;
    ventana.innerHTML = `
        <header class="chat_cabecera">
            <span class="chat_logo"><i class="fa-solid fa-robot"></i></span>
            <div class="chat_titulo">
                <strong>Asistente SIGRE</strong>
                <span>En emergencias llama al 123</span>
            </div>
            <button type="button" class="chat_cerrar" aria-label="Cerrar el asistente">
                <i class="fa-solid fa-xmark"></i>
            </button>
        </header>
        <div class="chat_mensajes"></div>
        <form class="chat_formulario">
            <input type="text" placeholder="Escribe tu pregunta..." maxlength="300" aria-label="Escribe tu pregunta">
            <button type="submit" aria-label="Enviar"><i class="fa-solid fa-paper-plane"></i></button>
        </form>`;

    document.body.append(boton, ventana);

    boton.addEventListener("click", () => { ventana.hidden = !ventana.hidden; });
    ventana.querySelector(".chat_cerrar").addEventListener("click", () => { ventana.hidden = true; });

    // ---------- Paso 5: limpiar lo que escribe el usuario ----------
    // "¿Dónde hay ALBERGUES?" -> "donde hay albergues"
    function normalizar(texto) {
        return texto.toLowerCase()
            .normalize("NFD").replace(/[̀-ͯ]/g, "")
            .replace(/[^a-z0-9\s]/g, " ").trim();
    }

    // ---------- Paso 8: datos reales de SIGRE ----------
    const API = window.SIGRE_API;   // js/config.js

    // Consulta la API. Si conToken es true, envía la sesión del usuario.
    async function consultar(ruta, conToken) {
        const opciones = {};
        const token = localStorage.getItem("sigre_token");
        if (conToken && token) opciones.headers = { Authorization: "Bearer " + token };
        const respuesta = await fetch(API + ruta, opciones);
        if (!respuesta.ok) throw new Error(respuesta.status);
        return respuesta.json();
    }

    function fecha(iso) {
        return new Date(iso).toLocaleString("es-CO", {
            weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit"
        });
    }

    const ESTADOS = {
        pendiente: "Pendiente", en_revision: "En revisión", programada: "Visita programada",
        en_atencion: "Aceptada, en atención", atendida: "Atendida", cancelada: "Cancelada"
    };

    async function emergenciaActiva() {
        const e = await consultar("/api/emergencias/activa");
        if (!e.activa) return "✅ No hay emergencias activas en este momento. Si ves una situación de riesgo, llama al 123.";
        const lugar = [e.sector, e.municipio, e.departamento].filter(Boolean).join(", ");
        return `🚨 Emergencia activa: ${e.tipo} (riesgo ${e.nivel_riesgo}) en ${lugar}.\n${e.descripcion}`;
    }

    async function alberguesAbiertos() {
        const centros = (await consultar("/api/centros")).filter(c => c.estado === "abierto");
        if (!centros.length) return "Por ahora no hay albergues ni centros de acopio abiertos. Si necesitas alojamiento, pídelo en «Solicitar ayuda».";
        const lineas = centros.slice(0, 5).map(c => {
            const tipo = c.tipo === "albergue" ? "Albergue" : "Centro de acopio";
            const cupos = c.tipo === "albergue" ? ` (${Math.max(0, c.capacidad - c.ocupados)} cupos libres)` : "";
            return `• ${tipo}: ${c.nombre} — ${c.direccion}${cupos}`;
        });
        return `🏠 Centros abiertos (${centros.length}):\n${lineas.join("\n")}\n\nMíralos en el mapa en la página «Centros».`;
    }

    async function proximasJornadas() {
        const jornadas = await consultar("/api/jornadas", true);
        if (!jornadas.length) return "Por ahora no hay jornadas publicadas. Te llegará una notificación cuando haya una nueva.";
        const lineas = jornadas.slice(0, 4).map(j =>
            `• ${j.nombre} — ${fecha(j.fecha_inicio)} en ${j.lugar}` + (j.participo ? " ✅ ya estás inscrito" : ""));
        return `🤝 Próximas jornadas:\n${lineas.join("\n")}\n\nInscríbete con «Quiero participar» en la página «Jornadas».`;
    }

    async function misSolicitudes() {
        if (!localStorage.getItem("sigre_token")) return "Para ver tus solicitudes, primero inicia sesión.";
        const solicitudes = await consultar("/api/solicitudes-ayuda/mias", true);
        if (!solicitudes.length) return "Aún no has enviado solicitudes. Puedes hacerlo en «Solicitar ayuda».";
        const lineas = solicitudes.slice(0, 4).map(s =>
            `• SIGRE-${String(s.id).padStart(5, "0")}: ${ESTADOS[s.estado] || s.estado}`);
        return `📋 Tus solicitudes más recientes:\n${lineas.join("\n")}\n\nCuando cambien de estado te avisaremos en la campana 🔔.`;
    }

    // ---------- Paso 6: los temas y sus palabras clave ----------
    // respuesta puede ser un texto fijo o una función que consulta la API (paso 8).
    // prioridad: puntos extra para que ese tema gane a los demás.
    const TEMAS = [
        {
            claves: ["auxilio", "socorro", "atrapado", "atrapada", "herido", "herida", "ahogando", "no respira", "urgente"],
            prioridad: 10,
            respuesta: "⚠️ Si alguien está en peligro ahora mismo, llama YA al 123. Ponte a salvo y sigue las indicaciones de quien te atienda."
        },
        { claves: ["hola", "buenas"], respuesta: "¡Hola! Soy el asistente de SIGRE. Pregúntame por emergencias, albergues, jornadas o tus solicitudes." },
        { claves: ["gracias", "listo", "chao"], respuesta: "¡Con gusto! Recuerda: en una emergencia, llama al 123." },
        { claves: ["emergencia activa", "hay emergencia", "alerta", "que esta pasando"], respuesta: emergenciaActiva },
        { claves: ["albergue", "refugio", "donde dormir", "acopio", "donar", "donacion"], respuesta: alberguesAbiertos },
        { claves: ["jornada", "voluntari", "actividad", "participar"], respuesta: proximasJornadas },
        { claves: ["mi solicitud", "mis solicitudes", "estado de mi", "me aceptaron", "radicado"], respuesta: misSolicitudes },
        {
            claves: ["pedir ayuda", "solicitar ayuda", "necesito ayuda", "comida", "alimentos", "solicitud"],
            respuesta: "Puedes pedir ayuda (alimentos, salud, alojamiento, ropa, transporte o una visita a tu vivienda) en la página «Solicitar ayuda». Te avisaremos en la campana 🔔 cuando la revisen."
        },
        {
            claves: ["numero", "telefono", "123", "bomberos", "policia", "ambulancia", "cruz roja"],
            respuesta: "📞 Emergencias: 123 · Bomberos: 119 · Cruz Roja: 132 · Defensa Civil: 144"
        },
        {
            claves: ["inundacion", "lluvia", "creciente", "desbord"],
            respuesta: "🌊 En una inundación: sube a un lugar alto, no cruces calles con corriente, desconecta la luz si es seguro, aléjate de cables caídos y llama al 123."
        },
        {
            claves: ["incendio", "fuego", "humo"],
            respuesta: "🔥 En un incendio: sal de inmediato, avanza agachado si hay humo, no uses ascensores y llama a Bomberos (119) o al 123."
        },
        {
            claves: ["sismo", "temblor", "terremoto"],
            respuesta: "🌎 En un sismo: agáchate, cúbrete y sujétate lejos de ventanas. Al terminar, sal con calma y sin usar ascensores."
        },
        {
            claves: ["desaparecid", "perdido", "mascota", "reportar"],
            respuesta: "🔎 Para reportar a una persona o mascota desaparecida, entra a «Desaparecidos», sube una foto y completa los datos. Si es una persona, avisa también al 123."
        },
        {
            claves: ["ruta", "evacua", "como llego", "mapa"],
            respuesta: "🗺️ En la página «Rutas» puedes trazar el camino a pie hacia un albergue o un lugar seguro."
        }
    ];

    // ---------- Paso 6 (parte 2): elegir el tema ----------
    // Cada palabra clave encontrada suma puntos; las frases largas suman más,
    // así "mi solicitud" le gana a "solicitud".
    function buscarTema(pregunta) {
        const texto = normalizar(pregunta);
        let mejorTema = null;
        let mejorPuntaje = 0;

        TEMAS.forEach(tema => {
            let puntaje = 0;
            tema.claves.forEach(clave => {
                if (texto.includes(clave)) puntaje += clave.split(" ").length;
            });
            if (puntaje > 0) puntaje += tema.prioridad || 0;
            if (puntaje > mejorPuntaje) {
                mejorPuntaje = puntaje;
                mejorTema = tema;
            }
        });
        return mejorTema;
    }

    async function buscarRespuesta(pregunta) {
        const tema = buscarTema(pregunta);
        if (!tema) {
            return "No entendí 🤔. Prueba con «emergencia», «albergue», «jornadas», «mi solicitud» o «inundación».";
        }
        // Paso 8: si la respuesta es una función, se espera a que consulte la API.
        if (typeof tema.respuesta === "function") {
            try {
                return await tema.respuesta();
            } catch (error) {
                return "No pude consultar SIGRE en este momento (el servidor no responde). Si es una emergencia, llama al 123.";
            }
        }
        return tema.respuesta;
    }

    // ---------- Paso 7: mostrar los mensajes ----------
    const zonaMensajes = ventana.querySelector(".chat_mensajes");
    const formulario = ventana.querySelector(".chat_formulario");
    const entrada = formulario.querySelector("input");
    const CLAVE_HISTORIAL = "sigre_chat_historial";
    let historial = [];

    // quien: "usuario" o "bot". guardar: false para mensajes temporales.
    function agregarMensaje(texto, quien, guardar = true) {
        const burbuja = document.createElement("div");
        burbuja.className = quien === "usuario" ? "de_usuario" : "de_bot";
        burbuja.textContent = texto;   // textContent, no innerHTML: así nadie puede meter código
        zonaMensajes.appendChild(burbuja);
        zonaMensajes.scrollTop = zonaMensajes.scrollHeight;

        if (guardar) {
            historial.push({ texto, quien });
            historial = historial.slice(-30);      // guarda solo los últimos 30
            try {
                sessionStorage.setItem(CLAVE_HISTORIAL, JSON.stringify(historial));
            } catch (error) {
                // Si el navegador no deja guardar, el chat sigue funcionando igual.
            }
        }
        return burbuja;
    }

    const SUGERENCIAS =[
        "¿Hay una emergencia activa?",
        "Albergues abiertos",
        "Próximas jornadas",
        "Estado de mi solicitud",
        "Números de emergencia"
    ];

    function agregarSugerencias(){
        const caja =document.createElement("div");
        caja.className ="chat_sugerencias";

        SUGERENCIAS.forEach(texto => {
            const chip = document.createElement("button");
            chip.type = "button";
            chip.className = "chat_chip";
            chip.textContent = texto;
            chip.addEventListener("click", () => {
                caja.remove();              // quita los botones al elegir uno
                enviarPregunta(texto);
            });
            caja.appendChild(chip);
        });

        zonaMensajes.appendChild(caja);
        zonaMensajes.scrollTop = zonaMensajes.scrollHeight;
    }




    async function enviarPregunta(pregunta) {
        if (!pregunta) return;                 // no envía mensajes vacíos

        agregarMensaje(pregunta, "usuario");
        entrada.value = "";
        const escribiendo = agregarMensaje("Escribiendo...", "bot", false);

        escribiendo.classList.add("escribiendo");

        const respuesta = await buscarRespuesta(pregunta);
        escribiendo.remove();
        agregarMensaje(respuesta, "bot");

        // Si no entendió, vuelve a mostrar las opciones.
        if (respuesta.startsWith("No entendí")) agregarSugerencias();
        entrada.focus();
    }

    formulario.addEventListener("submit", evento => {
        evento.preventDefault();               // evita que la página se recargue
        enviarPregunta(entrada.value.trim());
    });


    let guardados = [];

    try {
        guardados = JSON.parse(sessionStorage.getItem(CLAVE_HISTORIAL) || "[]");
    } catch (error) {
        guardados = [];
    }

    if (guardados.length) {
        // Ya habíamos hablado: se vuelven a pintar los mensajes.
        guardados.forEach(m => agregarMensaje(m.texto, m.quien));
    } else {
        // Primera vez: bienvenida.
        agregarMensaje("¡Hola! Soy el asistente de SIGRE. Pregúntame por emergencias, albergues, jornadas, tus solicitudes o qué hacer en una inundación.", "bot");
    }
    agregarSugerencias();   // los botones salen siempre, al final de la conversación
})();
