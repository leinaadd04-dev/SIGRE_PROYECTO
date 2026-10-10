// SIGRE · Centros de acopio y albergues.
// Los centros los registran las entidades desde el panel de administración (GET /api/centros).
(() => {
    const API_BASE = `http://${window.location.hostname}:5000`;
    const list = document.getElementById("lista-centros");
    const search = document.getElementById("buscar-centro");
    const type = document.getElementById("filtro-tipo");
    const status = document.getElementById("filtro-estado");
    const empty = document.getElementById("sin-resultados");
    let centros = [];

    const htmlSafe = valor => String(valor == null ? "" : valor).replace(/[&<>"']/g, c => (
        { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
    ));
    const nivel = item => {
        if (!item.capacidad) return "sin_cupos";
        const pct = item.ocupados / item.capacidad * 100;
        if (pct >= 100) return "completo";
        if (pct >= 85) return "rojo";
        if (pct >= 50) return "amarillo";
        return "verde";
    };
    const etiquetaNivel = estado => ({ verde: "Baja ocupación", amarillo: "Ocupación media", rojo: "Ocupación alta", completo: "Completo", sin_cupos: "Cupos sin informar" })[estado];

    const mapa = L.map("mapa-centros").setView([8.757, -75.884], 13);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "&copy; OpenStreetMap contributors", maxZoom: 19 }).addTo(mapa);
    const capaMarcadores = L.layerGroup().addTo(mapa);
    const marcadores = new Map();

    function actualizarMarcadores(items) {
        capaMarcadores.clearLayers();
        marcadores.clear();
        items.filter(item => item.latitud != null).forEach(item => {
            const estado = item.estado === "cerrado" ? "cerrado" : nivel(item);
            const icono = L.divIcon({ className: "", html: `<span class="marcador-centro ${estado}"><i class="fa-solid ${item.tipo === "acopio" ? "fa-box" : "fa-house"}"></i></span>`, iconSize: [32, 38], iconAnchor: [16, 36] });
            const cupos = item.capacidad ? `<br>Cupos: ${item.ocupados}/${item.capacidad}` : "";
            const marcador = L.marker([item.latitud, item.longitud], { icon: icono })
                .bindPopup(`<strong>${htmlSafe(item.nombre)}</strong><br>${item.tipo === "acopio" ? "Centro de acopio" : "Albergue"}${item.estado === "cerrado" ? " (cerrado)" : ""}<br>${htmlSafe(item.direccion)}${cupos}${item.telefono ? `<br><a href="tel:${htmlSafe(item.telefono.replace(/[^0-9+]/g, ""))}">${htmlSafe(item.telefono)}</a>` : ""}`)
                .addTo(capaMarcadores);
            marcadores.set(item.id, marcador);
        });
    }

    function render() {
        const q = search.value.trim().toLocaleLowerCase("es");
        const filtered = centros.filter(item =>
            `${item.nombre} ${item.direccion} ${item.descripcion || ""} ${item.necesidades || ""}`.toLocaleLowerCase("es").includes(q)
            && (type.value === "todos" || item.tipo === type.value)
            && (status.value === "todos" || nivel(item) === status.value));
        document.getElementById("contador-resultados").textContent = filtered.length;

        list.innerHTML = filtered.map(item => {
            const estado = nivel(item);
            const esAcopio = item.tipo === "acopio";
            const cerrado = item.estado === "cerrado";
            const porcentaje = item.capacidad ? Math.min(100, Math.round(item.ocupados / item.capacidad * 100)) : 0;
            const cupos = item.capacidad
                ? `<div class="cupo_encabezado"><span>Ocupación de cupos</span><strong>${item.ocupados} / ${item.capacidad}</strong></div>
                   <div class="barra_cupo ${estado}" role="progressbar" aria-label="Ocupación de cupos" aria-valuemin="0" aria-valuemax="${item.capacidad}" aria-valuenow="${item.ocupados}"><span style="width:${porcentaje}%"></span></div>`
                : "";
            const ubicacion = item.latitud != null
                ? `<button type="button" class="boton_ver_ubicacion" data-centro="${item.id}"><i class="fa-solid fa-map-location-dot"></i> Ver ubicación</button>`
                : "";
            const telefono = item.telefono
                ? `<p class="centro_detalle"><i class="fa-solid fa-phone"></i><a href="tel:${htmlSafe(item.telefono.replace(/[^0-9+]/g, ""))}">${htmlSafe(item.telefono)}</a></p>`
                : "";
            return `<article class="centro_card ${cerrado ? "centro_cerrado" : ""}">
                <div class="centro_icono_grande ${cerrado ? "cerrado" : (esAcopio ? "verde" : estado)}" aria-hidden="true"><i class="fa-solid ${esAcopio ? "fa-boxes-stacked" : "fa-house-chimney"}"></i></div>
                <div class="centro_card_contenido">
                    <div class="centro_card_cabecera"><div><h3>${htmlSafe(item.nombre)}</h3><p class="centro_tipo">${esAcopio ? "Centro de acopio" : "Albergue temporal"}</p></div><span class="centro_estado ${cerrado ? "cerrado" : (esAcopio ? "verde" : estado)}">${cerrado ? "Cerrado" : (esAcopio ? "Recibe donaciones" : etiquetaNivel(estado))}</span></div>
                    <p class="centro_detalle"><i class="fa-solid fa-location-dot"></i><span>${htmlSafe(item.direccion)}</span></p>
                    ${item.descripcion ? `<p class="centro_detalle"><i class="fa-solid ${esAcopio ? "fa-box-open" : "fa-house-medical"}"></i><span>${htmlSafe(item.descripcion)}</span></p>` : ""}
                    ${item.necesidades ? `<p class="centro_detalle centro_necesidades"><i class="fa-solid fa-hand-holding-heart"></i><span><strong>Necesita:</strong> ${htmlSafe(item.necesidades)}</span></p>` : ""}
                    ${telefono}
                    ${cupos}
                    <div class="centro_card_footer">
                        <span><i class="fa-solid fa-clock-rotate-left"></i> Actualizado ${new Date(item.actualizado_en).toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short" })}</span>
                        ${ubicacion}
                    </div>
                </div>
            </article>`;
        }).join("");

        if (!centros.length) {
            empty.textContent = "Aún no hay centros registrados. Las entidades los agregan desde el panel de administración.";
        } else {
            empty.textContent = "No hay centros que coincidan con esos filtros.";
        }
        empty.hidden = filtered.length > 0;
        actualizarMarcadores(filtered);
    }

    function actualizarResumen() {
        document.getElementById("total-centros").textContent = centros.length;
        document.getElementById("total-albergues").textContent = centros.filter(x => x.tipo === "albergue").length;
        document.getElementById("total-abiertos").textContent = centros.filter(x => x.estado === "abierto").length;
    }

    // "Ver ubicación": sube al mapa, se acerca al centro y abre su ventana.
    list.addEventListener("click", evento => {
        const boton = evento.target.closest("[data-centro]");
        if (!boton) return;
        const marcador = marcadores.get(Number(boton.dataset.centro));
        if (!marcador) return;
        document.getElementById("mapa-centros").scrollIntoView({ behavior: "smooth", block: "center" });
        mapa.setView(marcador.getLatLng(), 17);
        marcador.openPopup();
    });
    [search, type, status].forEach(control => { control.addEventListener("input", render); control.addEventListener("change", render); });

    async function cargar() {
        empty.hidden = false;
        empty.textContent = "Cargando centros...";
        try {
            const respuesta = await fetch(API_BASE + "/api/centros");
            if (!respuesta.ok) throw new Error();
            centros = await respuesta.json();
            actualizarResumen();
            render();
        } catch (error) {
            list.innerHTML = "";
            empty.hidden = false;
            empty.textContent = "No se pudieron cargar los centros. Revisa que Flask esté en ejecución y que la migración de administración esté aplicada.";
        }
        setTimeout(() => mapa.invalidateSize(), 100);
    }

    cargar();
})();
