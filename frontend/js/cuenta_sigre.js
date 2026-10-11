/* SIGRE · Cuenta en la cabecera (compartido por todas las páginas internas)
   - Muestra el avatar de la cuenta en la cabecera y permite elegirlo:
     un animalito de la galería o una foto propia (se guarda en Flask).
   - Cuando la navegación de escritorio está oculta (celular), agrega un
     botón de menú con los mismos enlaces, el avatar y "Cerrar sesión".
   Expone window.SigreCuenta para que los módulos reaccionen al avatar. */
(() => {
    const cabecera = document.querySelector(".cabecera_dashboard");
    if (!cabecera) return;

    const API_BASE = window.SIGRE_API;   // js/config.js
    const CLAVE_TOKEN = "sigre_token";
    const TIPOS_FOTO = ["image/jpeg", "image/png", "image/webp"];
    const LIMITE_FOTO_ORIGINAL = 5 * 1024 * 1024;
    const LADO_FOTO = 320;

    const ANIMALES = {
        perro: { emoji: "🐶", nombre: "Perro", fondo: "#ffe8cc" },
        gato: { emoji: "🐱", nombre: "Gato", fondo: "#fff3c4" },
        zorro: { emoji: "🦊", nombre: "Zorro", fondo: "#ffe0d1" },
        panda: { emoji: "🐼", nombre: "Panda", fondo: "#e8ecef" },
        koala: { emoji: "🐨", nombre: "Koala", fondo: "#e3e8f4" },
        leon: { emoji: "🦁", nombre: "León", fondo: "#ffefc2" },
        rana: { emoji: "🐸", nombre: "Rana", fondo: "#dff5d8" },
        mono: { emoji: "🐵", nombre: "Mono", fondo: "#f3e3d3" },
        conejo: { emoji: "🐰", nombre: "Conejo", fondo: "#fce8f0" },
        tigre: { emoji: "🐯", nombre: "Tigre", fondo: "#ffe6c7" },
        oso: { emoji: "🐻", nombre: "Oso", fondo: "#efe2d6" },
        buho: { emoji: "🦉", nombre: "Búho", fondo: "#ece9fb" }
    };

    // avatarActual: lo guardado en SIGRE. avatarSeleccion: lo elegido en la ventana sin guardar.
    let avatarActual = { tipo: null };
    let avatarSeleccion = null;
    let focoAntesDeVentana = null;
    const oyentesAvatar = [];

    /* ---------- Utilidades ---------- */

    function leerToken() {
        try {
            return localStorage.getItem(CLAVE_TOKEN);
        } catch (error) {
            return null;
        }
    }

    function leerUsuario() {
        try {
            return JSON.parse(localStorage.getItem("sigre_usuario") || "null") || {};
        } catch (error) {
            return {};
        }
    }

    function crear(etiqueta, clase, atributos) {
        const elemento = document.createElement(etiqueta);
        if (clase) elemento.className = clase;
        Object.keys(atributos || {}).forEach(function (nombre) {
            elemento.setAttribute(nombre, atributos[nombre]);
        });
        return elemento;
    }

    function mostrarMensaje(texto, tipo) {
        mensajeAvatar.textContent = texto;
        mensajeAvatar.classList.remove("error", "exito");
        if (tipo) mensajeAvatar.classList.add(tipo);
    }

    function formatearTamano(bytes) {
        return bytes < 1024 * 1024
            ? Math.max(1, Math.round(bytes / 1024)) + " KB"
            : (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    function pintarAvatar(elemento, avatar) {
        elemento.innerHTML = "";
        elemento.style.background = "";
        if (avatar && avatar.tipo === "animal" && ANIMALES[avatar.animal]) {
            elemento.textContent = ANIMALES[avatar.animal].emoji;
            elemento.style.background = ANIMALES[avatar.animal].fondo;
        } else if (avatar && avatar.tipo === "foto" && avatar.fotoUrl) {
            const imagen = crear("img", "", { alt: "" });
            imagen.src = avatar.fotoUrl;
            elemento.appendChild(imagen);
        } else {
            elemento.innerHTML = '<i class="fa-solid fa-user"></i>';
        }
    }

    function cerrarSesion() {
        try {
            localStorage.removeItem("sigre_usuario");
            localStorage.removeItem(CLAVE_TOKEN);
        } catch (error) { /* nada que limpiar */ }
        window.location.href = "index.html";
    }

    /* ---------- Avatar y menú en la cabecera ---------- */

    let derecha = cabecera.querySelector(".cabecera_derecha");
    if (!derecha) {
        derecha = crear("div", "cabecera_derecha");
        cabecera.appendChild(derecha);
    }
    derecha.classList.add("cuenta_derecha");

    const botonAvatar = crear("button", "cuenta_avatar_boton", {
        type: "button",
        "aria-label": "Elegir mi avatar",
        "aria-haspopup": "dialog"
    });
    const avatarCabecera = crear("span", "cuenta_avatar");
    botonAvatar.appendChild(avatarCabecera);

    const botonMenu = crear("button", "cuenta_menu_boton", {
        type: "button",
        "aria-label": "Abrir menú",
        "aria-expanded": "false",
        "aria-controls": "cuenta-menu"
    });
    botonMenu.innerHTML = '<i class="fa-solid fa-bars"></i>';

    derecha.appendChild(botonAvatar);
    derecha.appendChild(botonMenu);

    const menu = crear("div", "cuenta_menu", { id: "cuenta-menu" });
    menu.hidden = true;
    menu.innerHTML = `
        <div class="cuenta_menu_perfil">
            <span class="cuenta_avatar cuenta_avatar_grande"></span>
            <div class="cuenta_menu_datos">
                <strong></strong>
                <small></small>
            </div>
            <button type="button" class="cuenta_menu_cambiar">
                <i class="fa-solid fa-pen"></i> Avatar
            </button>
        </div>
        <nav class="cuenta_menu_enlaces" aria-label="Menú de navegación"></nav>
    `;
    cabecera.appendChild(menu);

    const avatarMenu = menu.querySelector(".cuenta_avatar");
    const nombreMenu = menu.querySelector(".cuenta_menu_datos strong");
    const correoMenu = menu.querySelector(".cuenta_menu_datos small");
    const enlacesMenu = menu.querySelector(".cuenta_menu_enlaces");

    // Navegación de escritorio de la página (se usa para saber si está oculta).
    const navEscritorio = cabecera.querySelector(".navegacion_escritorio");

    // Menú de las tres rayitas: opciones de la cuenta. La navegación entre
    // módulos está en la cabecera y en la barra de abajo (js/navegacion_movil.js).
    //   Administrador: Vista ciudadana, Panel, Mi perfil, Notificaciones, Cerrar sesión.
    //   Ciudadano:     Mi perfil, Notificaciones, Cerrar sesión.
    const paginaActual = window.location.pathname.split("/").pop() || "dashboard.html";

    function opcionMenu(etiqueta, atributos, icono, texto) {
        const opcion = crear(etiqueta, "cuenta_menu_enlace", atributos);
        opcion.innerHTML = `<i class="fa-solid ${icono}"></i><span>${texto}</span>`;
        enlacesMenu.appendChild(opcion);
        return opcion;
    }

    if (leerToken() && leerUsuario().rol === "autoridad") {
        const vistaCiudadana = opcionMenu("a", { href: "dashboard.html" }, "fa-house-user", "Vista ciudadana");
        const panelAdmin = opcionMenu("a", { href: "dashboard_admin.html" }, "fa-gauge-high", "Panel de administración");
        if (paginaActual === "dashboard_admin.html") panelAdmin.classList.add("activo");
        else if (paginaActual !== "perfil.html") vistaCiudadana.classList.add("activo");
    }

    if (leerToken()) {
        // Datos personales, médicos y contacto de emergencia (perfil.html).
        const miPerfil = opcionMenu("a", { href: "perfil.html" }, "fa-id-card", "Mi perfil");
        if (paginaActual === "perfil.html") miPerfil.classList.add("activo");
    }

    const opcionNotificaciones = opcionMenu("button", { type: "button" }, "fa-bell", "Notificaciones");
    const contadorMenu = crear("span", "cuenta_menu_contador");
    contadorMenu.hidden = true;
    opcionNotificaciones.appendChild(contadorMenu);
    opcionNotificaciones.addEventListener("click", function () {
        abrirMenu(false);
        // Se abre después de este clic para que no lo cierre el clic "afuera".
        setTimeout(function () {
            if (window.SigreNotificaciones) window.SigreNotificaciones.abrir();
        }, 0);
    });
    // js/notificaciones.js avisa cuántas hay sin leer.
    document.addEventListener("sigre:notificaciones", function (evento) {
        const cantidad = evento.detail.noLeidas;
        contadorMenu.hidden = !cantidad;
        contadorMenu.textContent = cantidad > 9 ? "9+" : String(cantidad);
    });

    if (leerToken()) {
        const salir = opcionMenu("a", { href: "#" }, "fa-right-from-bracket", "Cerrar sesión");
        salir.addEventListener("click", function (evento) {
            evento.preventDefault();
            cerrarSesion();
        });
    } else {
        opcionMenu("a", { href: "login.html" }, "fa-right-to-bracket", "Iniciar sesión");
    }

    function pintarDatosUsuario() {
        const usuario = leerUsuario();
        const conSesion = Boolean(leerToken());
        nombreMenu.textContent = conSesion ? (usuario.nombre || "Tu cuenta") : "Sin sesión";
        correoMenu.textContent = conSesion ? (usuario.email || "") : "Inicia sesión para elegir tu avatar";
        document.querySelectorAll("[data-sigre-nombre]").forEach(function (elemento) {
            elemento.textContent = usuario.nombre || "";
        });
    }

    function abrirMenu(abrir) {
        menu.hidden = !abrir;
        botonMenu.setAttribute("aria-expanded", abrir ? "true" : "false");
        botonMenu.setAttribute("aria-label", abrir ? "Cerrar menú" : "Abrir menú");
        botonMenu.innerHTML = abrir ? '<i class="fa-solid fa-xmark"></i>' : '<i class="fa-solid fa-bars"></i>';
    }

    botonMenu.addEventListener("click", function () {
        abrirMenu(menu.hidden);
    });

    document.addEventListener("click", function (evento) {
        if (!menu.hidden && !menu.contains(evento.target) && !botonMenu.contains(evento.target)) {
            abrirMenu(false);
        }
    });

    menu.querySelector(".cuenta_menu_cambiar").addEventListener("click", function () {
        abrirMenu(false);
        abrirVentanaAvatar();
    });

    // En celular la navegación de escritorio se oculta (la cabecera se compacta).
    // El botón ☰ está siempre: tiene las opciones de la cuenta.
    function revisarNavegacion() {
        const oculta = !navEscritorio || window.getComputedStyle(navEscritorio).display === "none";
        cabecera.classList.toggle("cuenta_nav_oculta", oculta);
    }
    window.addEventListener("resize", revisarNavegacion);

    /* ---------- Ventana para elegir avatar ---------- */

    const ventanaAvatar = crear("div", "cuenta_ventana_fondo");
    ventanaAvatar.hidden = true;
    ventanaAvatar.innerHTML = `
        <section class="cuenta_ventana" role="dialog" aria-modal="true" aria-labelledby="cuenta-titulo-avatar">
            <button type="button" class="cuenta_ventana_cerrar" aria-label="Cerrar">
                <i class="fa-solid fa-xmark"></i>
            </button>

            <h2 id="cuenta-titulo-avatar">Elige tu avatar</h2>

            <div class="cuenta_vista_previa">
                <span class="cuenta_avatar cuenta_avatar_xl"></span>
            </div>

            <div class="cuenta_sin_sesion" hidden>
                <p>Para elegir tu avatar necesitas iniciar sesión.</p>
                <a href="login.html" class="cuenta_boton_principal">
                    <i class="fa-solid fa-right-to-bracket"></i> Iniciar sesión
                </a>
            </div>

            <div class="cuenta_contenido_avatar">
                <h3>Animalitos de SIGRE</h3>
                <div class="cuenta_galeria" role="radiogroup" aria-label="Animalitos disponibles"></div>

                <h3>O usa una foto tuya</h3>
                <label class="cuenta_boton_secundario cuenta_subir_foto">
                    <i class="fa-solid fa-camera"></i> Elegir foto
                    <input type="file" accept="image/jpeg,image/png,image/webp" hidden>
                </label>
                <p class="cuenta_ayuda">
                    JPG, PNG o WEBP de máximo 5 MB. La recortamos en cuadrado y se guarda sin los datos internos de la foto (como la ubicación).
                </p>

                <p class="cuenta_mensaje" role="status" aria-live="polite"></p>

                <div class="cuenta_acciones">
                    <button type="button" class="cuenta_boton_secundario cuenta_quitar">
                        <i class="fa-solid fa-trash"></i> Quitar avatar
                    </button>
                    <button type="button" class="cuenta_boton_principal cuenta_guardar">
                        <i class="fa-solid fa-check"></i> Guardar avatar
                    </button>
                </div>
            </div>
        </section>
    `;
    document.body.appendChild(ventanaAvatar);

    const avatarPrevia = ventanaAvatar.querySelector(".cuenta_avatar_xl");
    const bloqueSinSesion = ventanaAvatar.querySelector(".cuenta_sin_sesion");
    const bloqueAvatar = ventanaAvatar.querySelector(".cuenta_contenido_avatar");
    const galeria = ventanaAvatar.querySelector(".cuenta_galeria");
    const inputFoto = ventanaAvatar.querySelector('input[type="file"]');
    const mensajeAvatar = ventanaAvatar.querySelector(".cuenta_mensaje");
    const botonGuardar = ventanaAvatar.querySelector(".cuenta_guardar");
    const botonQuitar = ventanaAvatar.querySelector(".cuenta_quitar");
    const botonCerrar = ventanaAvatar.querySelector(".cuenta_ventana_cerrar");

    Object.keys(ANIMALES).forEach(function (clave) {
        const boton = crear("button", "cuenta_animal", {
            type: "button",
            role: "radio",
            "aria-checked": "false",
            "aria-label": ANIMALES[clave].nombre,
            "data-animal": clave,
            title: ANIMALES[clave].nombre
        });
        boton.style.setProperty("--fondo-animal", ANIMALES[clave].fondo);
        boton.textContent = ANIMALES[clave].emoji;
        galeria.appendChild(boton);
    });

    function cambiarAvatarActual(avatar) {
        if (avatarActual.fotoUrl && avatarActual.fotoUrl !== avatar.fotoUrl) {
            URL.revokeObjectURL(avatarActual.fotoUrl);
        }
        avatarActual = avatar;
        pintarAvatar(avatarCabecera, avatarActual);
        pintarAvatar(avatarMenu, avatarActual);
        oyentesAvatar.forEach(function (oyente) { oyente(avatarActual); });
    }

    function descartarSeleccion() {
        if (avatarSeleccion && avatarSeleccion.fotoUrl && avatarSeleccion.fotoUrl !== avatarActual.fotoUrl) {
            URL.revokeObjectURL(avatarSeleccion.fotoUrl);
        }
        avatarSeleccion = null;
    }

    function marcarAnimalElegido(clave) {
        galeria.querySelectorAll("[data-animal]").forEach(function (boton) {
            boton.setAttribute("aria-checked", boton.getAttribute("data-animal") === clave ? "true" : "false");
        });
    }

    function seleccionarAvatar(seleccion) {
        descartarSeleccion();
        avatarSeleccion = seleccion;
        pintarAvatar(avatarPrevia, seleccion);
        marcarAnimalElegido(seleccion.tipo === "animal" ? seleccion.animal : null);
        mostrarMensaje("");
    }

    function mostrarSinSesion(sinSesion) {
        bloqueSinSesion.hidden = !sinSesion;
        bloqueAvatar.hidden = sinSesion;
    }

    function abrirVentanaAvatar() {
        focoAntesDeVentana = document.activeElement;
        descartarSeleccion();
        mostrarSinSesion(!leerToken());
        pintarAvatar(avatarPrevia, avatarActual);
        marcarAnimalElegido(avatarActual.tipo === "animal" ? avatarActual.animal : null);
        botonQuitar.hidden = !avatarActual.tipo;
        mostrarMensaje("");
        ventanaAvatar.hidden = false;
        botonCerrar.focus();
    }

    function cerrarVentanaAvatar() {
        if (ventanaAvatar.hidden) return;
        descartarSeleccion();
        ventanaAvatar.hidden = true;
        if (focoAntesDeVentana) focoAntesDeVentana.focus();
    }

    async function llamarApi(ruta, opciones) {
        const configuracion = Object.assign({}, opciones);
        configuracion.headers = { Authorization: "Bearer " + leerToken() };
        return fetch(API_BASE + ruta, configuracion);
    }

    async function cargarAvatar() {
        pintarDatosUsuario();
        if (!leerToken()) {
            cambiarAvatarActual({ tipo: null });
            return;
        }
        try {
            const respuesta = await llamarApi("/api/mi-cuenta/avatar");
            if (!respuesta.ok) return;
            const datos = await respuesta.json();
            if (datos.tipo === "foto") {
                const respuestaFoto = await llamarApi("/api/mi-cuenta/avatar/foto");
                cambiarAvatarActual(respuestaFoto.ok
                    ? { tipo: "foto", fotoUrl: URL.createObjectURL(await respuestaFoto.blob()) }
                    : { tipo: null });
            } else {
                cambiarAvatarActual({ tipo: datos.tipo, animal: datos.animal });
            }
        } catch (error) {
            // El avatar es opcional: si el servidor no responde, queda el ícono por defecto.
        }
    }

    // Recorta la foto en cuadrado y la vuelve a codificar como JPEG.
    // Así pesa poco y no conserva metadatos como la ubicación GPS.
    function recortarFoto(archivo) {
        return new Promise(function (resolver, rechazar) {
            const url = URL.createObjectURL(archivo);
            const imagen = new Image();
            imagen.onload = function () {
                const lado = Math.min(imagen.naturalWidth, imagen.naturalHeight);
                const lienzo = crear("canvas");
                lienzo.width = LADO_FOTO;
                lienzo.height = LADO_FOTO;
                const contexto = lienzo.getContext("2d");
                contexto.fillStyle = "#ffffff";
                contexto.fillRect(0, 0, LADO_FOTO, LADO_FOTO);
                contexto.drawImage(
                    imagen,
                    (imagen.naturalWidth - lado) / 2, (imagen.naturalHeight - lado) / 2, lado, lado,
                    0, 0, LADO_FOTO, LADO_FOTO
                );
                URL.revokeObjectURL(url);
                lienzo.toBlob(function (blob) {
                    if (blob) resolver(blob);
                    else rechazar(new Error("No se pudo procesar la foto"));
                }, "image/jpeg", 0.88);
            };
            imagen.onerror = function () {
                URL.revokeObjectURL(url);
                rechazar(new Error("No se pudo leer la foto"));
            };
            imagen.src = url;
        });
    }

    async function enviarAvatar(datos, botonActivo) {
        botonGuardar.disabled = true;
        botonQuitar.disabled = true;
        const contenidoBoton = botonActivo.innerHTML;
        botonActivo.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Guardando...';
        try {
            const respuesta = await llamarApi("/api/mi-cuenta/avatar", { method: "POST", body: datos });
            if (respuesta.status === 401 || respuesta.status === 422) {
                mostrarSinSesion(true);
                return false;
            }
            if (!respuesta.ok) {
                let texto = "No se pudo guardar el avatar. Revisa que la migración de avatares esté aplicada.";
                try {
                    texto = (await respuesta.json()).error || texto;
                } catch (error) { /* respuesta sin JSON */ }
                throw new Error(texto);
            }
            return true;
        } catch (error) {
            mostrarMensaje(error instanceof TypeError
                ? "No se pudo conectar con el servidor de SIGRE. Verifica que Flask esté en ejecución."
                : error.message, "error");
            return false;
        } finally {
            botonGuardar.disabled = false;
            botonQuitar.disabled = false;
            botonActivo.innerHTML = contenidoBoton;
        }
    }

    galeria.addEventListener("click", function (evento) {
        const boton = evento.target.closest("[data-animal]");
        if (boton) seleccionarAvatar({ tipo: "animal", animal: boton.getAttribute("data-animal") });
    });

    inputFoto.addEventListener("change", async function () {
        const archivo = inputFoto.files[0];
        inputFoto.value = "";
        if (!archivo) return;
        if (TIPOS_FOTO.indexOf(archivo.type) === -1) {
            mostrarMensaje("Usa una foto JPG, PNG o WEBP.", "error");
            return;
        }
        if (archivo.size > LIMITE_FOTO_ORIGINAL) {
            mostrarMensaje(`La foto pesa ${formatearTamano(archivo.size)}; el máximo es 5 MB.`, "error");
            return;
        }
        mostrarMensaje("Preparando tu foto...");
        try {
            const blob = await recortarFoto(archivo);
            seleccionarAvatar({ tipo: "foto", blob: blob, fotoUrl: URL.createObjectURL(blob) });
        } catch (error) {
            mostrarMensaje("No se pudo leer la imagen. Prueba con otra foto.", "error");
        }
    });

    botonGuardar.addEventListener("click", async function () {
        if (!avatarSeleccion) {
            mostrarMensaje("Elige un animalito o una foto antes de guardar.", "error");
            return;
        }
        const seleccion = avatarSeleccion;
        const datos = new FormData();
        datos.append("tipo", seleccion.tipo);
        if (seleccion.tipo === "animal") datos.append("animal", seleccion.animal);
        else datos.append("foto", seleccion.blob, "avatar.jpg");

        if (await enviarAvatar(datos, botonGuardar)) {
            avatarSeleccion = null;
            cambiarAvatarActual(seleccion.tipo === "animal"
                ? { tipo: "animal", animal: seleccion.animal }
                : { tipo: "foto", fotoUrl: seleccion.fotoUrl });
            cerrarVentanaAvatar();
        }
    });

    botonQuitar.addEventListener("click", async function () {
        const datos = new FormData();
        datos.append("tipo", "ninguno");
        if (await enviarAvatar(datos, botonQuitar)) {
            cambiarAvatarActual({ tipo: null });
            cerrarVentanaAvatar();
        }
    });

    botonAvatar.addEventListener("click", abrirVentanaAvatar);
    botonCerrar.addEventListener("click", cerrarVentanaAvatar);
    ventanaAvatar.addEventListener("click", function (evento) {
        if (evento.target === ventanaAvatar) cerrarVentanaAvatar();
    });
    document.addEventListener("keydown", function (evento) {
        if (evento.key !== "Escape") return;
        if (!ventanaAvatar.hidden) cerrarVentanaAvatar();
        else if (!menu.hidden) {
            abrirMenu(false);
            botonMenu.focus();
        }
    });

    /* ---------- API para los módulos ---------- */

    window.SigreCuenta = {
        abrirAvatar: abrirVentanaAvatar,
        recargar: cargarAvatar,
        pintarAvatar: pintarAvatar,
        limpiar: function () {
            cerrarVentanaAvatar();
            cambiarAvatarActual({ tipo: null });
            pintarDatosUsuario();
        },
        alCambiarAvatar: function (oyente) {
            oyentesAvatar.push(oyente);
            oyente(avatarActual);
        }
    };

    revisarNavegacion();
    cambiarAvatarActual({ tipo: null });
    cargarAvatar();
})();
