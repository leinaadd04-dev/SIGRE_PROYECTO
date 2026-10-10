/* ============================================================
   SIGRE - Dashboard del Ciudadano
   Maneja: nombre del usuario, emergencia activa y la lista de
   recientes. Todo se carga desde localStorage y
   desde un objeto de datos simulado.
   ============================================================ */

/* ============================================================
   DATOS SIMULADOS
   Cuando tengamos backend Flask, esto vendrá de la API.
   ============================================================ */
const DATOS_SIGRE = {
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
    // La publica una cuenta de autoridad desde el panel (GET /api/emergencias/activa).
    const tarjetaEmergencia = document.getElementById('tarjeta-emergencia');
    const tituloEmergencia = tarjetaEmergencia ? tarjetaEmergencia.querySelector('h2') : null;
    const emergenciaDescripcion = document.querySelector('.emergencia_descripcion');
    const emergenciaUbicacion = document.querySelector('.emergencia_ubicacion');
    const NIVELES = { bajo: 'riesgo bajo', medio: 'riesgo medio', alto: 'riesgo alto', critico: 'riesgo crítico' };

    function pintarEmergencia(titulo, descripcion, ubicacion) {
        if (tituloEmergencia) tituloEmergencia.textContent = titulo;
        if (emergenciaDescripcion) emergenciaDescripcion.textContent = descripcion;
        if (emergenciaUbicacion) {
            emergenciaUbicacion.replaceChildren();
            if (ubicacion) {
                const icono = document.createElement('i');
                icono.className = 'fa-solid fa-location-dot';
                emergenciaUbicacion.append(icono, ' ' + ubicacion);
            }
        }
    }

    fetch(`http://${window.location.hostname}:5000/api/emergencias/activa`)
        .then(function (respuesta) {
            if (!respuesta.ok) throw new Error();
            return respuesta.json();
        })
        .then(function (emergencia) {
            if (!emergencia.activa) {
                pintarEmergencia('Sin emergencias activas', 'No hay alertas publicadas por las autoridades en este momento.', '');
                if (tarjetaEmergencia) tarjetaEmergencia.classList.add('sin_emergencia');
                return;
            }
            const lugar = [emergencia.sector, emergencia.municipio, emergencia.departamento].filter(Boolean).join(', ');
            pintarEmergencia(
                `Emergencia activa · ${NIVELES[emergencia.nivel_riesgo] || ''}`,
                `${emergencia.tipo}: ${emergencia.descripcion}`,
                lugar
            );
        })
        .catch(function () {
            pintarEmergencia('Emergencia activa', 'No se pudo consultar el estado de emergencias. En caso de peligro marca el 123.', '');
        });

    /* ============================================================
       3. NOTIFICACIONES
       La campana la maneja js/notificaciones.js con datos reales de la API.
       ============================================================ */

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