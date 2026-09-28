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
            if (valor.length >= 8) fuerza++;
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
       4. FORMULARIO DE LOGIN
       ============================================================ */
    const formLogin = document.getElementById('form_login');
    if (formLogin) {
        formLogin.addEventListener('submit', (e) => {
            e.preventDefault();

            const email = document.getElementById('email').value.trim();
            const password = document.getElementById('password').value;
            const errorMsg = document.getElementById('error-msg');
            const exitoMsg = document.getElementById('exito-msg');

            errorMsg.style.display = 'none';
            exitoMsg.style.display = 'none';

            // Validaciones básicas
            if (!email || !password) {
                errorMsg.textContent = 'Por favor completa todos los campos.';
                errorMsg.style.display = 'block';
                return;
            }

            if (password.length < 8) {
                errorMsg.textContent = 'La contraseña debe tener al menos 8 caracteres.';
                errorMsg.style.display = 'block';
                return;
            }

            // Buscar usuario en localStorage
            const usuarioGuardado = localStorage.getItem('sigre_usuario');

            if (!usuarioGuardado) {
                errorMsg.textContent = 'No hay ninguna cuenta registrada. Regístrate primero.';
                errorMsg.style.display = 'block';
                return;
            }

            const usuario = JSON.parse(usuarioGuardado);

            // Verificar credenciales
            if (usuario.email !== email) {
                errorMsg.textContent = 'Correo o contraseña incorrectos.';
                errorMsg.style.display = 'block';
                return;
            }

            // Verificar contraseña (simulado)
            if (usuario.password && usuario.password !== password) {
                errorMsg.textContent = 'Correo o contraseña incorrectos.';
                errorMsg.style.display = 'block';
                return;
            }

            // Login exitoso
            exitoMsg.textContent = `¡Bienvenido, ${usuario.nombre}! Redirigiendo...`;
            exitoMsg.style.display = 'block';

            setTimeout(() => {
                redirigirSegunRol(usuario.rol);
            }, 1500);
        });
    }

    /* ============================================================
       5. FORMULARIO DE REGISTRO
       ============================================================ */
    const formRegistro = document.getElementById('form-registro');
    if (formRegistro) {
        formRegistro.addEventListener('submit', (e) => {
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

            if (password.length < 8) {
                errorMsg.textContent = 'La contraseña debe tener al menos 8 caracteres.';
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

            // Guardar usuario en localStorage
            const nuevoUsuario = {
                nombre,
                email,
                telefono,
                password,
                rol
            };

            localStorage.setItem('sigre_usuario', JSON.stringify(nuevoUsuario));

            // Mostrar éxito
            exitoMsg.textContent = `¡Cuenta creada como ${rol}! Redirigiendo al login...`;
            exitoMsg.style.display = 'block';

            setTimeout(() => {
                window.location.href = 'login.html';
            }, 2000);
        });
    }

    /* ============================================================
       6. CERRAR SESIÓN (para el dashboard)
       ============================================================ */
    const btnCerrarSesion = document.getElementById('cerrar-sesion');
    if (btnCerrarSesion) {
        btnCerrarSesion.addEventListener('click', (e) => {
            e.preventDefault();
            localStorage.removeItem('sigre_usuario');
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
        case 'voluntario':
            window.location.href = 'dashboard_voluntario.html';
            break;
        case 'ciudadano':
        default:
            window.location.href = 'dashboard.html';
            break;
    }
}