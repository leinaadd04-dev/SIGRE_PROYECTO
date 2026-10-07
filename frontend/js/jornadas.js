// SIGRE · Lógica de Jornadas Comunitarias

document.addEventListener('DOMContentLoaded', function () {
    const chips = document.querySelectorAll('.chip_filtro');
    const tarjetas = document.querySelectorAll('.tarjeta_jornada');

    chips.forEach(function (chip) {
        chip.addEventListener('click', function () {
            chips.forEach(function (otroChip) {
                otroChip.classList.remove('activo');
            });
            chip.classList.add('activo');

            const categoriaElegida = chip.dataset.filtro;
            tarjetas.forEach(function (tarjeta) {
                const coincide = categoriaElegida === 'todas' ||
                    tarjeta.dataset.categoria === categoriaElegida;

                if (coincide) {
                    tarjeta.style.display = '';
                    requestAnimationFrame(function () {
                        tarjeta.classList.remove('tarjeta_oculta');
                    });
                } else {
                    tarjeta.classList.add('tarjeta_oculta');
                    setTimeout(function () {
                        if (tarjeta.classList.contains('tarjeta_oculta')) {
                            tarjeta.style.display = 'none';
                        }
                    }, 250);
                }
            });
        });
    });

    // Intereses y participaciones se guardan en este navegador.
    const CLAVE_INTERESES = 'sigre_jornadas_intereses';
    const CLAVE_PARTICIPADAS = 'sigre_jornadas_participadas';
    const listaIntereses = document.getElementById('lista-intereses');
    const listaParticipadas = document.getElementById('lista-participadas');

    function leerLista(clave) {
        try {
            const elementos = JSON.parse(localStorage.getItem(clave) || '[]');
            return Array.isArray(elementos) ? elementos : [];
        } catch (error) {
            return [];
        }
    }

    let intereses = leerLista(CLAVE_INTERESES);
    let participadas = leerLista(CLAVE_PARTICIPADAS);

    function guardarListas() {
        try {
            localStorage.setItem(CLAVE_INTERESES, JSON.stringify(intereses));
            localStorage.setItem(CLAVE_PARTICIPADAS, JSON.stringify(participadas));
        } catch (error) {
            console.warn('No se pudieron guardar las jornadas en este navegador.', error);
        }
    }

    function dibujarLista(contenedor, elementos, mensajeVacio, tipoLista) {
        if (!contenedor) return;
        contenedor.replaceChildren();

        if (!elementos.length) {
            const aviso = document.createElement('p');
            aviso.className = 'aviso_sin_intereses';
            aviso.textContent = mensajeVacio;
            contenedor.appendChild(aviso);
            return;
        }

        elementos.forEach(function (elemento) {
            const fila = document.createElement('div');
            fila.className = 'item_lista_jornada';

            const nombre = document.createElement('span');
            nombre.className = 'nombre_item_lista';
            nombre.textContent = elemento.nombre;

            if (tipoLista === 'intereses') {
                const confirmado = document.createElement('span');
                confirmado.className = 'check_interes';
                confirmado.setAttribute('aria-label', 'Guardado en mis intereses');
                confirmado.innerHTML = '<i class="fa-solid fa-check" aria-hidden="true"></i>';
                fila.append(nombre, confirmado);
            } else {
                const quitar = document.createElement('button');
                quitar.type = 'button';
                quitar.className = 'quitar_item_jornada';
                quitar.dataset.tipoLista = tipoLista;
                quitar.dataset.id = elemento.id;
                quitar.setAttribute('aria-label', 'Quitar ' + elemento.nombre);
                quitar.innerHTML = '<i class="fa-solid fa-xmark" aria-hidden="true"></i>';
                fila.append(nombre, quitar);
            }
            contenedor.appendChild(fila);
        });
    }

    function actualizarPaneles() {
        dibujarLista(
            listaIntereses,
            intereses,
            'Toca el corazón de una jornada para guardarla aquí.',
            'intereses'
        );
        dibujarLista(
            listaParticipadas,
            participadas,
            'Aún no has marcado una jornada para participar.',
            'participadas'
        );

        document.querySelectorAll('.boton_me_gusta').forEach(function (boton) {
            const guardada = intereses.some(function (item) {
                return item.id === boton.dataset.id;
            });
            boton.setAttribute('aria-pressed', String(guardada));
            boton.setAttribute(
                'aria-label',
                guardada ? 'Quitar de mis intereses' : 'Guardar en mis intereses'
            );
            boton.innerHTML = guardada
                ? '<i class="fa-solid fa-heart" aria-hidden="true"></i>'
                : '<i class="fa-regular fa-heart" aria-hidden="true"></i>';
            boton.classList.toggle('seleccionado', guardada);
        });

        document.querySelectorAll('.boton_participar').forEach(function (boton) {
            const anotada = participadas.some(function (item) {
                return item.id === boton.dataset.id;
            });
            boton.setAttribute('aria-pressed', String(anotada));
            boton.classList.toggle('seleccionado', anotada);
            boton.textContent = anotada ? 'Cancelar participación' : 'Quiero participar';
        });
    }

    actualizarPaneles();

    document.addEventListener('click', function (evento) {
        const quitar = evento.target.closest('.quitar_item_jornada');
        if (quitar) {
            const lista = quitar.dataset.tipoLista === 'intereses' ? intereses : participadas;
            const actualizada = lista.filter(function (item) {
                return item.id !== quitar.dataset.id;
            });
            if (quitar.dataset.tipoLista === 'intereses') {
                intereses = actualizada;
            } else {
                participadas = actualizada;
            }
            guardarListas();
            actualizarPaneles();
            return;
        }

        const botonInteres = evento.target.closest('.boton_me_gusta');
        if (botonInteres) {
            const id = botonInteres.dataset.id;
            const existe = intereses.some(function (item) { return item.id === id; });
            intereses = existe
                ? intereses.filter(function (item) { return item.id !== id; })
                : intereses.concat({ id: id, nombre: botonInteres.dataset.nombre });
            guardarListas();
            actualizarPaneles();
            return;
        }

        const botonParticipar = evento.target.closest('.boton_participar');
        if (botonParticipar) {
            const id = botonParticipar.dataset.id;
            const existe = participadas.some(function (item) { return item.id === id; });
            participadas = existe
                ? participadas.filter(function (item) { return item.id !== id; })
                : participadas.concat({ id: id, nombre: botonParticipar.dataset.nombre });
            guardarListas();
            actualizarPaneles();
        }
    });

    // Mapa de las jornadas
    const botonesUbicacion = document.querySelectorAll('.boton_ver_ubicacion');
    const ventanaMapaFondo = document.getElementById('ventana-mapa-fondo');
    const mapaTitulo = document.getElementById('mapa-titulo');
    const botonCerrarMapa = document.getElementById('boton-cerrar-mapa');
    const enlaceStreetView = document.getElementById('enlace-street-view');
    const botonModoOscuro = document.getElementById('boton-mapa-oscuro');
    const contenedorMapa = document.getElementById('mapa-contenedor');

    let mapaLeaflet = null;
    let marcadorLeaflet = null;

    function abrirVentanaMapa(lat, lon, nombre) {
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
            alert('Esta jornada todavía no tiene coordenadas válidas.');
            return;
        }
        if (!window.L) {
            alert('No se pudo cargar Leaflet. Revisa tu conexión a internet y recarga la página.');
            return;
        }

        mapaTitulo.textContent = 'Ubicación: ' + nombre;
        if (enlaceStreetView) {
            enlaceStreetView.href =
                'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=' + lat + ',' + lon;
        }
        ventanaMapaFondo.hidden = false;

        if (mapaLeaflet === null) {
            mapaLeaflet = L.map('mapa-jornada-leaflet').setView([lat, lon], 15);

            const capaCalles = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '&copy; OpenStreetMap',
                maxZoom: 19
            });
            const capaRelieve = L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', {
                attribution: '&copy; OpenStreetMap, SRTM | &copy; OpenTopoMap (CC-BY-SA)',
                maxZoom: 17
            });
            const capaSatelite = L.tileLayer(
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                { attribution: 'Tiles &copy; Esri', maxZoom: 19 }
            );

            capaCalles.addTo(mapaLeaflet);
            L.control.layers({
                'Calles': capaCalles,
                'Relieve': capaRelieve,
                'Satélite': capaSatelite
            }).addTo(mapaLeaflet);

            const iconoSigre = L.divIcon({
                className: 'marcador_sigre',
                html: '<i class="fa-solid fa-location-dot"></i>',
                iconSize: [32, 32],
                iconAnchor: [16, 32]
            });
            marcadorLeaflet = L.marker([lat, lon], { icon: iconoSigre }).addTo(mapaLeaflet);
        } else {
            mapaLeaflet.setView([lat, lon], 15);
            marcadorLeaflet.setLatLng([lat, lon]);
        }

        window.setTimeout(function () {
            mapaLeaflet.invalidateSize();
        }, 150);
    }

    botonesUbicacion.forEach(function (boton) {
        boton.addEventListener('click', function () {
            abrirVentanaMapa(
                Number.parseFloat(boton.dataset.lat),
                Number.parseFloat(boton.dataset.lon),
                boton.dataset.nombre || 'Jornada comunitaria'
            );
        });
    });

    if (botonModoOscuro && contenedorMapa) {
        botonModoOscuro.addEventListener('click', function () {
            const activo = contenedorMapa.classList.toggle('mapa_oscuro');
            botonModoOscuro.setAttribute('aria-pressed', String(activo));
            if (mapaLeaflet) {
                window.setTimeout(function () { mapaLeaflet.invalidateSize(); }, 100);
            }
        });
    }

    function cerrarVentanaMapa() {
        ventanaMapaFondo.hidden = true;
    }

    if (botonCerrarMapa) {
        botonCerrarMapa.addEventListener('click', cerrarVentanaMapa);
    }
    if (ventanaMapaFondo) {
        ventanaMapaFondo.addEventListener('click', function (evento) {
            if (evento.target === ventanaMapaFondo) cerrarVentanaMapa();
        });
    }
    document.addEventListener('keydown', function (evento) {
        if (evento.key === 'Escape' && ventanaMapaFondo && !ventanaMapaFondo.hidden) {
            cerrarVentanaMapa();
        }
    });
});
