/* ============================================================
   SIGRE - Autenticación completa
   Maneja: login, registro, mostrar/ocultar contraseña,
   medidor de fuerza, código de autoridad, cerrar sesión.
   ============================================================ */

document.addEventListener('DOMContentLoaded', () => {

    /* ============================================================
       1. MOSTRAR / OCULTAR CONTRASEÑA
       ============================================================ */
    const togglePassword = document.getElementById('toggle-password');
    if (togglePassword) {
        togglePassword.addEventListener('click', () => {
            const input = document.getElementById('password');
            if (!input) return;

            if (input.type === 'password') {
                input.type = 'text';
                togglePassword.innerHTML = '<i data-lucide="eye-off"></i>';
            } else {
                input.type = 'password';
                togglePassword.innerHTML = '<i data-lucide="eye"></i>';
            }
            if (window.lucide) lucide.createIcons();
        });
    }

    /* ============================================================
       2. MOSTRAR / OCULTAR CAMPO DE CÓDIGO DE AUTORIDAD
       ============================================================ */
    const radiosRol = document.querySelectorAll('input[name="rol"]');
    const campoCodigo = document.getElementById('campo-codigo');

    if (radiosRol.length && campoCodigo) {
        radiosRol.forEach(radio => {
            radio.addEventListener('change', () => {
                if (radio.value === 'autoridad' && radio.checked) {
                    campoCodigo.style.display = 'block';
                } else if (radio.checked) {
                    campoCodigo.style.display = 'none';
                }
            });
        });
    }

    /* ============================================================
       3. MEDIDOR DE FUERZA DE CONTRASEÑA (solo en registro)
       ============================================================ */
    const inputPassword = document.getElementById('password');
    const fuerzaBarras = document.querySelectorAll('.fuerza_barra');
    const fuerzaTexto = document.getElementById('fuerza-texto');

    if (inputPassword && fuerzaBarras.length && fuerzaTexto) {
        inputPassword.addEventListener('input', () => {
            const valor = inputPassword.value;

            // Limpiar barras
            fuerzaBarras.forEach(barra => {
                barra.className = 'fuerza_barra';
            });

            // Si está vacío, mostrar mensaje inicial
            if (valor.length === 0) {
                fuerzaTexto.textContent = 'Ingresa una contraseña';
                fuerzaTexto.style.color = 'rgba(255, 255, 255, 0.75)';
                return;
            }

            // Calcular fuerza (0 a 4)
            let fuerza = 0;
            if (valor.length >= 12) fuerza++;
            if (/[A-Z]/.test(valor)) fuerza++;
            if (/[0-9]/.test(valor)) fuerza++;
            if (/[!@#$%^&*(),.?":{}|<>]/.test(valor)) fuerza++;

            // Activar barras
            for (let i = 0; i < fuerza; i++) {
                fuerzaBarras[i].classList.add('activa', `nivel-${fuerza}`);
            }

            // Texto y color
            const textos = { 0: 'Muy débil', 1: 'Débil', 2: 'Regular', 3: 'Buena', 4: 'Fuerte' };
            const colores = { 1: '#E53E3E', 2: '#ED8936', 3: '#F4C95D', 4: '#38A169' };

            fuerzaTexto.textContent = textos[fuerza];
            fuerzaTexto.style.color = colores[fuerza] || 'rgba(255, 255, 255, 0.75)';
        });
    }

    /* ============================================================
       CONEXIÓN CON LA API FLASK
       La cuenta vive en PostgreSQL. En el navegador solo se guardan
       el token de sesión y los datos que muestra el dashboard
       (nombre, email y rol); nunca la contraseña.
       ============================================================ */
    const API_SIGRE = window.SIGRE_API;   // js/config.js
    const CLAVE_TOKEN_SIGRE = 'sigre_token';
    const MENSAJE_SIN_SERVIDOR = 'No se pudo conectar con el servidor de SIGRE. Verifica que Flask esté en ejecución.';

    async function leerJsonSeguro(respuesta) {
        try {
            return await respuesta.json();
        } catch (error) {
            return {};
        }
    }

    /* ============================================================
       4. FORMULARIO DE LOGIN
       ============================================================ */
    const formLogin = document.getElementById('form_login');
    if (formLogin) {
        formLogin.addEventListener('submit', async (e) => {
            e.preventDefault();

            const email = document.getElementById('email').value.trim();
            const password = document.getElementById('password').value;
            const errorMsg = document.getElementById('error-msg');
            const exitoMsg = document.getElementById('exito-msg');
            const botonLogin = formLogin.querySelector('button[type="submit"]');

            errorMsg.style.display = 'none';
            exitoMsg.style.display = 'none';

            // Validaciones básicas
            if (!email || !password) {
                errorMsg.textContent = 'Por favor completa todos los campos.';
                errorMsg.style.display = 'block';
                return;
            }

            botonLogin.disabled = true;

            try {
                const respuesta = await fetch(`${API_SIGRE}/api/auth/login`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, password })
                });
                const datos = await leerJsonSeguro(respuesta);

                if (!respuesta.ok) {
                    // Correo sin verificar: se abre la ventana del código y, al verificar, entra solo.
                    if (datos.verificar && window.SigreVerificacion) {
                        window.SigreVerificacion.abrir(email.toLowerCase(), () => formLogin.requestSubmit());
                    }
                    throw new Error(datos.error || 'No se pudo iniciar sesión. Inténtalo de nuevo.');
                }

                localStorage.setItem(CLAVE_TOKEN_SIGRE, datos.access_token);

                const respuestaCuenta = await fetch(`${API_SIGRE}/api/mi-cuenta`, {
                    headers: { Authorization: `Bearer ${datos.access_token}` }
                });
                const cuenta = await leerJsonSeguro(respuestaCuenta);

                if (!respuestaCuenta.ok) {
                    throw new Error(cuenta.error || 'No se pudieron cargar los datos de tu cuenta.');
                }

                // Datos que usa el dashboard para el saludo
                localStorage.setItem('sigre_usuario', JSON.stringify({
                    nombre: cuenta.nombre || cuenta.email.split('@')[0],
                    email: cuenta.email,
                    rol: cuenta.rol
                }));

                // Login exitoso
                exitoMsg.textContent = `¡Bienvenido, ${cuenta.nombre || cuenta.email}! Redirigiendo...`;
                exitoMsg.style.display = 'block';

                setTimeout(() => {
                    redirigirSegunRol(cuenta.rol);
                }, 1200);
            } catch (error) {
                localStorage.removeItem(CLAVE_TOKEN_SIGRE);
                errorMsg.textContent = error instanceof TypeError ? MENSAJE_SIN_SERVIDOR : error.message;
                errorMsg.style.display = 'block';
                botonLogin.disabled = false;
            }
        });
    }
          
    /* ============================================================
       5. FORMULARIO DE REGISTRO
       ============================================================ */
    const formRegistro = document.getElementById('form-registro');
    if (formRegistro) {
        formRegistro.addEventListener('submit', async (e) => {
            e.preventDefault();

            // Leer campos
            const nombre = document.getElementById('nombre').value.trim();
            const email = document.getElementById('email').value.trim();
            const telefono = document.getElementById('telefono').value.trim();
            const password = document.getElementById('password').value;
            const password2 = document.getElementById('password2').value;
            const terminos = document.getElementById('terminos').checked;
            const errorMsg = document.getElementById('error-msg');
            const exitoMsg = document.getElementById('exito-msg');
            const botonRegistro = formRegistro.querySelector('button[type="submit"]');

            // Capturar rol
            const rolSeleccionado = document.querySelector('input[name="rol"]:checked');
            const rol = rolSeleccionado ? rolSeleccionado.value : null;

            errorMsg.style.display = 'none';
            exitoMsg.style.display = 'none';

            // Validaciones
            if (!nombre || !email || !password || !password2) {
                errorMsg.textContent = 'Por favor completa todos los campos obligatorios.';
                errorMsg.style.display = 'block';
                return;
            }

            if (!rol) {
                errorMsg.textContent = 'Debes seleccionar un tipo de usuario.';
                errorMsg.style.display = 'block';
                return;
            }

            // El servidor exige entre 12 y 128 caracteres
            if (password.length < 12 || password.length > 128) {
                errorMsg.textContent = 'La contraseña debe tener entre 12 y 128 caracteres.';
                errorMsg.style.display = 'block';
                return;
            }

            if (password !== password2) {
                errorMsg.textContent = 'Las contraseñas no coinciden.';
                errorMsg.style.display = 'block';
                return;
            }

            if (!terminos) {
                errorMsg.textContent = 'Debes aceptar los términos y condiciones.';
                errorMsg.style.display = 'block';
                return;
            }

            // Validar código de autoridad
            if (rol === 'autoridad') {
                const CODIGO_AUTORIDAD = 'SIGRE-AUT-2026';
                const codigoIngresado = document.getElementById('codigo_autoridad').value.trim();

                if (!codigoIngresado) {
                    errorMsg.textContent = 'Debes ingresar el código de autorización.';
                    errorMsg.style.display = 'block';
                    return;
                }

                if (codigoIngresado !== CODIGO_AUTORIDAD) {
                    errorMsg.textContent = 'El código de autorización no es válido.';
                    errorMsg.style.display = 'block';
                    return;
                }
            }

            // Evita crear la cuenta dos veces si se toca el botón mientras espera.
            const textoBoton = botonRegistro.textContent;
            botonRegistro.disabled = true;
            botonRegistro.textContent = 'Creando cuenta...';

            try {
                const respuesta = await fetch(`${API_SIGRE}/api/auth/registro`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ nombre, email, telefono, password })
                });
                const datos = await leerJsonSeguro(respuesta);

                if (!respuesta.ok) {
                    // La cuenta ya existía pero sin verificar: se retoma la verificación.
                    if (datos.verificar && window.SigreVerificacion) {
                        window.SigreVerificacion.abrir(email.toLowerCase(), () => {
                            window.location.href = 'login.html';
                        });
                    }
                    throw new Error(datos.error || 'No se pudo crear la cuenta. Inténtalo de nuevo.');
                }

                // El servidor crea las cuentas como ciudadano; los otros roles los asigna un administrador.
                // La cuenta queda pendiente hasta escribir el código que llegó al correo.
                exitoMsg.textContent = rol === 'ciudadano'
                    ? '¡Cuenta creada! Escribe el código que enviamos a tu correo.'
                    : '¡Cuenta creada como ciudadano! El rol de voluntario o autoridad lo asigna un administrador de SIGRE. Escribe el código que enviamos a tu correo.';
                exitoMsg.style.display = 'block';
                botonRegistro.disabled = false;
                botonRegistro.textContent = textoBoton;

                window.SigreVerificacion.abrir(email.toLowerCase(), () => {
                    exitoMsg.textContent = '¡Correo verificado! Redirigiendo al inicio de sesión...';
                    setTimeout(() => {
                        window.location.href = 'login.html';
                    }, 1500);
                });
            } catch (error) {
                errorMsg.textContent = error instanceof TypeError ? MENSAJE_SIN_SERVIDOR : error.message;
                errorMsg.style.display = 'block';
                botonRegistro.disabled = false;
                botonRegistro.textContent = textoBoton;
            }
        });
    }

    /* ============================================================
       6. CERRAR SESIÓN (para el dashboard)
       Solo cierra la sesión; la cuenta sigue en el servidor.
       ============================================================ */
    const btnCerrarSesion = document.getElementById('cerrar-sesion');
    if (btnCerrarSesion) {
        btnCerrarSesion.addEventListener('click', (e) => {
            e.preventDefault();
            localStorage.removeItem('sigre_usuario');
            localStorage.removeItem(CLAVE_TOKEN_SIGRE);
            window.location.href = 'index.html';
        });
    }

});

/* ============================================================
   FUNCIÓN AUXILIAR: REDIRIGIR SEGÚN EL ROL
   ============================================================ */
function redirigirSegunRol(rol) {
    switch (rol) {
        case 'autoridad':
            window.location.href = 'dashboard_admin.html';
            break;
        // Los voluntarios usan por ahora el mismo inicio que la ciudadanía.
        case 'ciudadano':
        default:
            window.location.href = 'dashboard.html';
            break;
    }
}
