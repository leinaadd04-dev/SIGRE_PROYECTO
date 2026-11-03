/* SIGRE · Intro animada (escena de Spline) al abrir la app instalada.
   - Solo en la app instalada, una vez por sesión y nunca con "reducir movimiento".
   - Se cierra sola a los 3 s aunque la escena no cargue: el botón SOS no puede esperar.
   - Para probarla en el navegador del computador: agrega ?intro a la dirección. */
(function () {
    const DURACION = 3000;
    const DESVANECIDO = 500;
    const VISOR = "https://cdn.spline.design/@splinetool/viewer@2.0.131/build/spline-viewer.webgl.js";
    const ESCENA = "https://prod.spline.design/oaVv79r-QKIQ3FE8/scene.splinecode";
    const CLAVE = "sigre_intro_vista";

    const forzada = new URLSearchParams(window.location.search).has("intro");
    const instalada = window.matchMedia("(display-mode: standalone)").matches
        || window.navigator.standalone === true;
    const reducirMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (reducirMovimiento || !(instalada || forzada)) return;

    // El panel manda al login a quien no tiene sesión: la intro se muestra allá.
    if (document.currentScript && document.currentScript.hasAttribute("data-requiere-sesion")) {
        try {
            if (!localStorage.getItem("sigre_usuario")) return;
        } catch (error) { return; }
    }

    try {
        if (!forzada && sessionStorage.getItem(CLAVE)) return;
        sessionStorage.setItem(CLAVE, "1");
    } catch (error) { /* sin sessionStorage la intro igual se muestra */ }

    const capa = document.createElement("div");
    capa.className = "intro_sigre";
    capa.innerHTML =
        `<spline-viewer url="${ESCENA}" aria-hidden="true"></spline-viewer>` +
        '<button type="button" class="intro_saltar">Saltar</button>';
    document.body.appendChild(capa);

    const visor = document.createElement("script");
    visor.type = "module";
    visor.src = VISOR;
    document.head.appendChild(visor);

    let cerrada = false;
    function cerrar() {
        if (cerrada) return;
        cerrada = true;
        clearTimeout(temporizador);
        capa.classList.add("saliendo");
        setTimeout(() => capa.remove(), DESVANECIDO);
    }

    const temporizador = setTimeout(cerrar, DURACION);
    capa.querySelector(".intro_saltar").addEventListener("click", cerrar);

    sonar();

    // Campanita corta hecha con Web Audio (no necesita archivo de sonido).
    // Android la deja sonar en la app instalada; si el navegador la bloquea, no suena y ya.
    function sonar() {
        const Contexto = window.AudioContext || window.webkitAudioContext;
        if (!Contexto) return;
        try {
            const audio = new Contexto();
            const tocar = () => {
                const inicio = audio.currentTime + 0.05;
                [[659.25, 0], [987.77, 0.18]].forEach(([frecuencia, retraso]) => {
                    const oscilador = audio.createOscillator();
                    const volumen = audio.createGain();
                    oscilador.type = "sine";
                    oscilador.frequency.value = frecuencia;
                    volumen.gain.setValueAtTime(0, inicio + retraso);
                    volumen.gain.linearRampToValueAtTime(0.18, inicio + retraso + 0.02);
                    volumen.gain.exponentialRampToValueAtTime(0.001, inicio + retraso + 0.9);
                    oscilador.connect(volumen).connect(audio.destination);
                    oscilador.start(inicio + retraso);
                    oscilador.stop(inicio + retraso + 1);
                });
                setTimeout(() => audio.close().catch(() => {}), 1500);
            };
            if (audio.state === "running") {
                tocar();
                return;
            }
            // Si sigue bloqueado, no debe sonar después, al primer toque del usuario.
            const cerrarAudio = () => audio.close().catch(() => {});
            audio.resume()
                .then(() => { if (!cerrada && audio.state === "running") tocar(); else cerrarAudio(); })
                .catch(cerrarAudio);
            setTimeout(() => { if (audio.state === "suspended") cerrarAudio(); }, DESVANECIDO);
        } catch (error) { /* sin sonido */ }
    }
})();
