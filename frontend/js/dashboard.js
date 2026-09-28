/* ============================================================
   SIGRE - Dashboard del Ciudadano
   Maneja: nombre del usuario, emergencia activa, notificaciones
   y la lista de recientes. Todo se carga desde localStorage y
   desde un objeto de datos simulado.
   ============================================================ */

/* ============================================================
   DATOS SIMULADOS
   Cuando tengamos backend Flask, esto vendrá de la API.
   ============================================================ */
const DATOS_SIGRE = {
    notificaciones: 1,

    emergenciaActiva: {
        activa: true,
        titulo: 'Emergencia Activa',
        descripcion: 'Inundación en Sector Centro',
        ubicacion: 'Montería, Córdoba'
    },

    recientes: [
        {
            icono: 'fa-solid fa-cloud-rain',
            titulo: 'Inundación Sector Centro',
            tiempo: 'Hace 15 min'
        },
        {
            icono: 'fa-solid fa-triangle-exclamation',
            titulo: 'Deslizamiento Vía Planeta Rica',
            tiempo: 'Hace 1h'
        },
        {
            icono: 'fa-solid fa-cloud-bolt',
            titulo: 'Lluvias intensas en varias zonas',
            tiempo: 'Hace 2h'
        }
    ]
};

/* ============================================================
   LÓGICA DEL DASHBOARD
   ============================================================ */
document.addEventListener('DOMContentLoaded', () => {

    /* ============================================================
       1. VERIFICAR SESIÓN Y MOSTRAR NOMBRE DEL USUARIO
       ============================================================ */
    const usuarioGuardado = localStorage.getItem('sigre_usuario');

    // Si no hay usuario logueado, redirigir al login
    if (!usuarioGuardado) {
        window.location.href = 'login.html';
        return;
    }

    const usuario = JSON.parse(usuarioGuardado);

    const nombreElemento = document.getElementById('nombre-usuario');
    const bienvenidaElemento = document.querySelector('.texto_bienvenida');

    if (nombreElemento) {
        nombreElemento.textContent = usuario.nombre;
    }

    if (bienvenidaElemento) {
        bienvenidaElemento.textContent = '¡Bienvenido,';
    }

    /* ============================================================
       2. RENDERIZAR EMERGENCIA ACTIVA
       ============================================================ */
    const emergencia = DATOS_SIGRE.emergenciaActiva;

    const tarjetaEmergencia = document.getElementById('tarjeta-emergencia');
    const emergenciaDescripcion = document.querySelector('.emergencia_descripcion');
    const emergenciaUbicacion = document.querySelector('.emergencia_ubicacion');

    if (emergencia.activa) {

        if (emergenciaDescripcion) {
            emergenciaDescripcion.textContent = emergencia.descripcion;
        }

        if (emergenciaUbicacion) {
            emergenciaUbicacion.innerHTML = `
                <i class="fa-solid fa-location-dot"></i> ${emergencia.ubicacion}
            `;
        }

    } else {

        // Si no hay emergencia activa, ocultar la tarjeta
        if (tarjetaEmergencia) {
            tarjetaEmergencia.style.display = 'none';
        }

    }

    /* ============================================================
       3. NOTIFICACIONES
       ============================================================ */
    const contadorNotificaciones = document.querySelector('.contador_notificaciones');

    if (contadorNotificaciones) {
        const cantidad = DATOS_SIGRE.notificaciones;

        if (cantidad > 0) {
            contadorNotificaciones.textContent = cantidad;
            contadorNotificaciones.style.display = 'flex';
        } else {
            contadorNotificaciones.style.display = 'none';
        }
    }

    /* ============================================================
       4. LISTA DE RECIENTES
       ============================================================ */
    const listaRecientes = document.getElementById('lista-recientes');

    if (listaRecientes) {
        listaRecientes.innerHTML = DATOS_SIGRE.recientes.map(item => `
            <div class="guardado_item">
                <div class="guardado_icono">
                    <i class="${item.icono}"></i>
                </div>
                <div class="guardado_texto">
                    <p class="guardado_titulo">${item.titulo}</p>
                    <p class="guardado_tiempo">${item.tiempo}</p>
                </div>
            </div>
        `).join('');
    }

    /* ============================================================
       5. BOTÓN SOS
       ============================================================ */
    const botonSOS = document.getElementById('boton-sos');

    if (botonSOS) {
        botonSOS.addEventListener('click', () => {
            const confirmar = confirm(
                '¿Enviar alerta SOS?\n\n' +
                'Se notificará a las autoridades de tu ubicación actual.'
            );

            if (confirmar) {
                alert('¡Alerta SOS enviada! Las autoridades se pondrán en contacto.');
                // Aquí irá el fetch al backend cuando lo tengamos
            }
        });
    }

});