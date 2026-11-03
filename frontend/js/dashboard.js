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

    // null mientras carga, {activa: false} si no hay y {error: true} si falló la consulta.
    let emergenciaActual = null;

    fetch(`${window.SIGRE_API}/api/emergencias/activa`)
        .then(function (respuesta) {
            if (!respuesta.ok) throw new Error();
            return respuesta.json();
        })
        .then(function (emergencia) {
            emergenciaActual = emergencia;
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
            emergenciaActual = { error: true };
            pintarEmergencia('Emergencia activa', 'No se pudo consultar el estado de emergencias. En caso de peligro marca el 123.', '');
        });

    /* ---------- Ventana "Más Info" ---------- */
    const ventanaEmergencia = document.getElementById('ventana-emergencia');
    const botonMasInfo = document.getElementById('boton-mas-info');
    const ALCANCES = { departamento: 'Todo el departamento', municipio: 'Todo el municipio', sector: 'Un sector del municipio' };

    // El tipo lo escribe la autoridad: se reconoce por palabras clave.
    const RECOMENDACIONES = [
        {
            claves: ['inund', 'lluvia', 'creciente', 'desbord'],
            pasos: [
                'Aléjate de ríos, caños y zonas bajas.',
                'No cruces calles inundadas a pie ni en vehículo: el agua en movimiento puede arrastrarte.',
                'Si el agua entra a tu casa, desconecta la energía y sube a un lugar alto.',
                'Ten listo tu kit de emergencia y sigue las rutas de evacuación.'
            ]
        },
        {
            claves: ['sismo', 'terremoto', 'temblor'],
            pasos: [
                'Agáchate, cúbrete y sujétate mientras dure el movimiento.',
                'Aléjate de ventanas y de objetos que puedan caer.',
                'Al terminar, sal con calma por la ruta de evacuación; no uses ascensores.',
                'Espera réplicas y revisa si hay fugas de gas antes de volver a entrar.'
            ]
        },
        {
            claves: ['incendio', 'fuego', 'humo'],
            pasos: [
                'Sal de inmediato y no regreses por tus pertenencias.',
                'Si hay humo, avanza agachado y cúbrete la nariz y la boca con un paño húmedo.',
                'Toca las puertas antes de abrirlas: si están calientes, busca otra salida.',
                'Llama al 119 (Bomberos) cuando estés a salvo.'
            ]
        },
        {
            claves: ['vendaval', 'tormenta', 'viento', 'huracan', 'electrica'],
            pasos: [
                'Quédate bajo techo y lejos de las ventanas.',
                'Aléjate de árboles, postes y cables caídos.',
                'Asegura los objetos sueltos de patios y techos.'
            ]
        },
        {
            claves: ['desliz', 'derrumbe', 'remocion'],
            pasos: [
                'Aléjate de laderas, taludes y zonas con grietas.',
                'Si oyes ruidos fuertes del terreno, evacúa de inmediato.',
                'No regreses hasta que las autoridades lo indiquen.'
            ]
        }
    ];
    const PASOS_GENERALES = [
        'Mantén la calma y sigue las indicaciones de las autoridades.',
        'Ten a mano tu kit de emergencia, tus documentos y el celular cargado.',
        'Ubica la ruta de evacuación y el albergue más cercano.',
        'Si estás en peligro, marca el 123 o usa el botón SOS.'
    ];
    const PASOS_PREVENCION = [
        'Arma o revisa tu kit de emergencia: agua, linterna, botiquín y documentos.',
        'Conoce la ruta de evacuación y el albergue más cercano a tu casa.',
        'Activa las notificaciones de SIGRE para enterarte de las alertas a tiempo.'
    ];

    function sinTildes(texto) {
        return String(texto || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    }

    function pasosPara(tipo) {
        const texto = sinTildes(tipo);
        const grupo = RECOMENDACIONES.find(g => g.claves.some(clave => texto.includes(clave)));
        return grupo ? grupo.pasos : PASOS_GENERALES;
    }

    function hace(fecha) {
        const minutos = Math.round((Date.now() - fecha.getTime()) / 60000);
        if (minutos < 1) return 'hace un momento';
        if (minutos < 60) return `hace ${minutos} min`;
        const horas = Math.round(minutos / 60);
        if (horas < 24) return `hace ${horas} h`;
        const dias = Math.round(horas / 24);
        return `hace ${dias} ${dias === 1 ? 'día' : 'días'}`;
    }

    function llenarVentanaEmergencia() {
        const e = emergenciaActual || {};
        const nivel = document.getElementById('detalle-nivel');
        const datos = document.getElementById('detalle-datos');
        const lista = document.getElementById('detalle-recomendaciones');
        let tipo, descripcion, pasos, filas = [];

        if (e.activa) {
            tipo = e.tipo || 'Emergencia activa';
            descripcion = e.descripcion || '';
            pasos = pasosPara(e.tipo);
            const lugar = [e.sector, e.municipio, e.departamento].filter(Boolean).join(', ');
            if (lugar) filas.push(['fa-location-dot', 'Zona afectada', lugar]);
            if (ALCANCES[e.alcance]) filas.push(['fa-expand', 'Alcance', ALCANCES[e.alcance]]);
            const fecha = e.creada_en ? new Date(e.creada_en) : null;
            if (fecha && !isNaN(fecha)) {
                const texto = fecha.toLocaleString('es-CO', { dateStyle: 'long', timeStyle: 'short', timeZone: 'America/Bogota' });
                filas.push(['fa-clock', 'Publicada', `${texto} (${hace(fecha)})`]);
            }
        } else if (e.error) {
            tipo = 'Sin conexión con SIGRE';
            descripcion = 'No pudimos consultar si hay una emergencia activa. Revisa tu conexión; si estás en peligro, marca el 123.';
            pasos = PASOS_GENERALES;
        } else if (emergenciaActual) {
            tipo = 'Sin emergencias activas';
            descripcion = 'Las autoridades no han publicado alertas en este momento. Aprovecha para prepararte.';
            pasos = PASOS_PREVENCION;
        } else {
            tipo = 'Consultando...';
            descripcion = 'Estamos revisando si hay una emergencia activa.';
            pasos = PASOS_GENERALES;
        }

        document.getElementById('detalle-tipo').textContent = tipo;
        document.getElementById('detalle-descripcion').textContent = descripcion;

        nivel.hidden = !(e.activa && NIVELES[e.nivel_riesgo]);
        if (!nivel.hidden) {
            nivel.textContent = NIVELES[e.nivel_riesgo];
            nivel.className = `emergencia_nivel emergencia_nivel_${e.nivel_riesgo}`;
        }

        datos.replaceChildren();
        datos.hidden = filas.length === 0;
        filas.forEach(([icono, etiqueta, valor]) => {
            const fila = document.createElement('div');
            const dt = document.createElement('dt');
            const i = document.createElement('i');
            i.className = `fa-solid ${icono}`;
            dt.append(i, ' ' + etiqueta);
            const dd = document.createElement('dd');
            dd.textContent = valor;
            fila.append(dt, dd);
            datos.append(fila);
        });

        lista.replaceChildren(...pasos.map(paso => {
            const li = document.createElement('li');
            li.textContent = paso;
            return li;
        }));
    }

    function cerrarVentanaEmergencia() {
        if (!ventanaEmergencia || ventanaEmergencia.hidden) return;
        ventanaEmergencia.hidden = true;
        document.body.classList.remove('directorio_abierto');
        if (botonMasInfo) botonMasInfo.focus();
    }

    if (ventanaEmergencia && botonMasInfo) {
        botonMasInfo.addEventListener('click', () => {
            llenarVentanaEmergencia();
            ventanaEmergencia.hidden = false;
            document.body.classList.add('directorio_abierto');
            document.getElementById('cerrar-emergencia').focus();
        });
        document.getElementById('cerrar-emergencia').addEventListener('click', cerrarVentanaEmergencia);
        ventanaEmergencia.addEventListener('click', evento => {
            if (evento.target === ventanaEmergencia) cerrarVentanaEmergencia();
        });
        document.addEventListener('keydown', evento => {
            if (evento.key === 'Escape') cerrarVentanaEmergencia();
        });
    }

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
       Lo maneja js/navegacion_movil.js (window.SigreSOS): llama al 123.
       ============================================================ */

});