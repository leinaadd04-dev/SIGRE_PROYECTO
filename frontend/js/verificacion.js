/* SIGRE · Ventana para verificar el correo con un código de 6 números.
   La usan registro.html y login.html: window.SigreVerificacion.abrir(correo, alVerificar).
   Recuerda la verificación pendiente: si el celular recarga la página (por
   ejemplo, al ir a Gmail a copiar el código), la ventana vuelve a abrirse. */
(() => {
    const ventana = document.getElementById("ventana-verificacion");
    if (!ventana) return;

    const API = window.SIGRE_API;
    const casillas = [...ventana.querySelectorAll(".codigo_casilla")];
    const mensaje = document.getElementById("verificacion-mensaje");
    const botonVerificar = document.getElementById("verificacion-enviar");
    const botonReenviar = document.getElementById("verificacion-reenviar");
    let correo = "";
    let alVerificar = null;
    let verificando = false;
    let temporizador = null;

    const CLAVE_PENDIENTE = "sigre_verificacion_pendiente";
    const VIGENCIA_PENDIENTE = 30 * 60 * 1000;   // 30 minutos

    function guardarPendiente(email) {
        try {
            localStorage.setItem(CLAVE_PENDIENTE, JSON.stringify({ email: email, hasta: Date.now() + VIGENCIA_PENDIENTE }));
        } catch (error) { /* sin almacenamiento: solo no se recordará */ }
    }

    function leerPendiente() {
        try {
            const pendiente = JSON.parse(localStorage.getItem(CLAVE_PENDIENTE) || "null");
            return pendiente && pendiente.email && pendiente.hasta > Date.now() ? pendiente.email : null;
        } catch (error) {
            return null;
        }
    }

    function borrarPendiente() {
        try {
            localStorage.removeItem(CLAVE_PENDIENTE);
        } catch (error) { /* nada que borrar */ }
    }

    // Qué hacer al verificar si la página se recargó y se perdió lo que pidió auth.js.
    function despuesPorDefecto() {
        if (/registro\.html$/.test(window.location.pathname)) window.location.href = "login.html";
    }

    function mostrar(texto, tipo) {
        mensaje.textContent = texto;
        mensaje.className = "verificacion_mensaje" + (tipo ? " " + tipo : "");
    }

    function codigo() {
        return casillas.map(casilla => casilla.value).join("");
    }

    function limpiar() {
        casillas.forEach(casilla => { casilla.value = ""; });
        casillas[0].focus();
    }

    // "Reenviar código" se puede usar una vez por minuto.
    function esperarReenvio(segundos) {
        clearInterval(temporizador);
        let restantes = segundos;
        botonReenviar.disabled = true;
        botonReenviar.textContent = `Reenviar código (${restantes} s)`;
        temporizador = setInterval(() => {
            restantes -= 1;
            if (restantes <= 0) {
                clearInterval(temporizador);
                botonReenviar.disabled = false;
                botonReenviar.textContent = "Reenviar código";
            } else {
                botonReenviar.textContent = `Reenviar código (${restantes} s)`;
            }
        }, 1000);
    }

    async function pedir(ruta, cuerpo) {
        const respuesta = await fetch(API + ruta, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(cuerpo)
        });
        const datos = await respuesta.json().catch(() => ({}));
        if (!respuesta.ok) throw new Error(datos.error || "No se pudo completar la acción.");
        return datos;
    }

    async function verificar() {
        if (verificando) return;
        if (codigo().length !== casillas.length) {
            mostrar("Escribe los 6 números del código.", "error");
            return;
        }
        verificando = true;
        botonVerificar.disabled = true;
        mostrar("Verificando...");
        try {
            const datos = await pedir("/api/auth/verificar", { email: correo, codigo: codigo() });
            mostrar(datos.mensaje || "¡Correo verificado!", "exito");
            borrarPendiente();
            setTimeout(() => {
                cerrar();
                if (alVerificar) alVerificar();
            }, 1200);
        } catch (error) {
            mostrar(error instanceof TypeError ? "No hay conexión con el servidor de SIGRE." : error.message, "error");
            limpiar();
        } finally {
            verificando = false;
            botonVerificar.disabled = false;
        }
    }

    async function reenviar() {
        botonReenviar.disabled = true;
        try {
            const datos = await pedir("/api/auth/reenviar-codigo", { email: correo });
            mostrar(datos.mensaje, "exito");
            limpiar();
        } catch (error) {
            mostrar(error instanceof TypeError ? "No hay conexión con el servidor de SIGRE." : error.message, "error");
        }
        esperarReenvio(60);
    }

    casillas.forEach((casilla, i) => {
        // Solo números; al escribir uno pasa a la siguiente casilla.
        casilla.addEventListener("input", () => {
            casilla.value = casilla.value.replace(/\D/g, "").slice(-1);
            if (casilla.value && i < casillas.length - 1) casillas[i + 1].focus();
            if (codigo().length === casillas.length) verificar();
        });
        casilla.addEventListener("keydown", evento => {
            if (evento.key === "Backspace" && !casilla.value && i > 0) casillas[i - 1].focus();
            if (evento.key === "ArrowLeft" && i > 0) casillas[i - 1].focus();
            if (evento.key === "ArrowRight" && i < casillas.length - 1) casillas[i + 1].focus();
            if (evento.key === "Enter") verificar();
        });
       
        casilla.addEventListener("paste", evento => {
            const numeros = (evento.clipboardData.getData("text") || "").replace(/\D/g, "").slice(0, casillas.length);
            if (!numeros) return;
            evento.preventDefault();
            casillas.forEach((c, j) => { c.value = numeros[j] || ""; });
            (casillas[numeros.length] || casillas[casillas.length - 1]).focus();
            if (numeros.length === casillas.length) verificar();
        });
    });

    function abrir(email, despues) {
        correo = email;
        alVerificar = despues || despuesPorDefecto;
        guardarPendiente(email);
        document.getElementById("verificacion-correo").textContent = email;
        mostrar("");
        ventana.hidden = false;
        limpiar();
        esperarReenvio(60);
    }

    function cerrar() {
        ventana.hidden = true;
        clearInterval(temporizador);
    }

    botonVerificar.addEventListener("click", verificar);
    botonReenviar.addEventListener("click", reenviar);
    // Cerrar con la ✕ es una decisión de la persona: ya no se vuelve a abrir sola.
    document.getElementById("verificacion-cerrar").addEventListener("click", () => {
        borrarPendiente();
        cerrar();
    });

    window.SigreVerificacion = { abrir: abrir };

    // Si quedó una verificación a medias (el celular recargó la página), se retoma.
    const pendiente = leerPendiente();
    if (pendiente) {
        abrir(pendiente, despuesPorDefecto);
        mostrar("Retomamos la verificación de tu correo. Escribe el código que te enviamos.");
    }
})();
