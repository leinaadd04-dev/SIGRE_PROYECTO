/* SIGRE · Panel de administración: inventario de centros de acopio y albergues.
   - Tabla de productos agrupada por categoría, con filtros por centro,
     categoría, estado (agotado / por agotarse / suficiente) y búsqueda.
   - La cantidad se cambia directo en la tabla (− / + o escribiendo el número).
   - Agregar, editar y eliminar productos. Solo cuentas de autoridad.
   Usa las utilidades de js/admin.js (window.SigreAdmin). */
(() => {
    const A = window.SigreAdmin;
    if (!A) return;
    const { llamarApi, htmlSafe, fecha, mostrarMensaje, textoError } = A;

    // El mismo orden y los mismos nombres que en la página pública (js/centros.js).
    const CATEGORIAS = {
        no_perecederos: { texto: "Alimentos no perecederos", icono: "fa-jar" },
        perecederos: { texto: "Alimentos perecederos", icono: "fa-carrot" },
        agua: { texto: "Agua potable", icono: "fa-bottle-water" },
        aseo: { texto: "Elementos de aseo", icono: "fa-pump-soap" },
        descanso: { texto: "Colchonetas, almohadas y cobijas", icono: "fa-bed" },
        ropa: { texto: "Ropa y calzado", icono: "fa-shirt" },
        bebes: { texto: "Artículos para bebés", icono: "fa-baby" },
        mascotas: { texto: "Alimento y cuidado de mascotas", icono: "fa-paw" },
        botiquin: { texto: "Botiquín y medicamentos", icono: "fa-kit-medical" },
        otros: { texto: "Otros", icono: "fa-box" }
    };
    const UNIDADES = {
        unidades: "unidades", kg: "kg", libras: "libras", litros: "litros",
        paquetes: "paquetes", cajas: "cajas", bolsas: "bolsas", pares: "pares"
    };
    // Unidades que tienen sentido en cada categoría (la primera es la que se propone).
    const UNIDADES_POR_CATEGORIA = {
        no_perecederos: ["kg", "libras", "paquetes", "unidades", "bolsas", "cajas"],
        perecederos: ["kg", "libras", "unidades", "paquetes", "bolsas", "cajas"],
        agua: ["litros", "unidades", "bolsas", "paquetes", "cajas"],
        aseo: ["unidades", "paquetes", "cajas", "bolsas"],
        descanso: ["unidades", "paquetes"],
        ropa: ["unidades", "pares", "paquetes"],
        bebes: ["unidades", "paquetes", "cajas", "bolsas"],
        mascotas: ["kg", "libras", "bolsas", "unidades"],
        botiquin: ["unidades", "cajas", "paquetes"],
        otros: Object.keys(UNIDADES)
    };
    // Calzado y medias se cuentan por pares y usan tallas numéricas.
    const ES_PAR = /zapat|chancl|tenis|bota|sandal|calzado|media|calcet/i;
    const TALLAS_ROPA = ["XS", "S", "M", "L", "XL", "XXL", "2", "4", "6", "8", "10", "12", "14", "16"];
    const TALLAS_CALZADO = ["18", "20", "22", "24", "26", "28", "30", "32", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44"];

    // Sugerencias del campo "Producto" según la categoría elegida.
    const SUGERENCIAS = {
        no_perecederos: ["Arroz", "Fríjol", "Lentejas", "Pasta", "Atún enlatado", "Leche en polvo", "Aceite", "Panela", "Harina de maíz"],
        perecederos: ["Huevos", "Plátano", "Yuca", "Frutas", "Verduras", "Pan", "Carne", "Pollo"],
        agua: ["Botellas de agua", "Bolsas de agua", "Garrafas de agua"],
        aseo: ["Jabón de baño", "Papel higiénico", "Crema dental", "Cepillo de dientes", "Toallas higiénicas", "Shampoo", "Desodorante", "Detergente", "Tapabocas"],
        descanso: ["Colchonetas", "Almohadas", "Cobijas", "Sábanas", "Toldillos", "Hamacas"],
        ropa: ["Camisetas adulto", "Camisetas niño", "Pantalones adulto", "Pantalones niño", "Ropa interior", "Medias", "Zapatos adulto", "Zapatos niño", "Chanclas"],
        bebes: ["Pañales", "Leche de fórmula", "Pañitos húmedos", "Teteros", "Compotas"],
        mascotas: ["Concentrado para perro", "Concentrado para gato", "Arena para gato", "Correas"],
        botiquin: ["Acetaminofén", "Suero oral", "Gasas", "Alcohol", "Curitas", "Vendas"],
        otros: ["Linternas", "Pilas", "Velas", "Encendedores", "Bolsas de basura"]
    };

    const seccion = document.getElementById("seccion-inventario");
    if (!seccion) return;
    const tabla = document.getElementById("tabla-inventario");
    const resumen = document.getElementById("resumen-inventario");
    const formulario = document.getElementById("formulario-producto");
    const buscador = document.getElementById("buscar-producto");
    const filtroCentro = document.getElementById("filtro-centro-inventario");
    const filtroCategoria = document.getElementById("filtro-categoria-inventario");
    const filtroEstado = document.getElementById("filtro-estado-inventario");

    let productos = [];
    let centros = [];
    let editando = null;

    /* ---------- Utilidades ---------- */

    function estado(p) {
        if (p.cantidad === 0) return "agotado";
        if (p.minimo > 0 && p.cantidad <= p.minimo) return "bajo";
        return "ok";
    }

    const TEXTO_ESTADO = { agotado: "Agotado", bajo: "Por agotarse", ok: "Suficiente" };

    function normalizar(texto) {
        return String(texto || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }

    function opciones(mapa, primera) {
        return (primera ? `<option value="">${htmlSafe(primera)}</option>` : "") +
            Object.keys(mapa).map(clave => `<option value="${clave}">${htmlSafe(mapa[clave].texto || mapa[clave])}</option>`).join("");
    }

    // Llena los selectores fijos una sola vez.
    filtroCategoria.innerHTML = opciones(CATEGORIAS, "Todas las categorías");
    formulario.categoria.innerHTML = opciones(CATEGORIAS);

    function llenarCentros() {
        const elegido = filtroCentro.value;
        const lista = centros.map(c =>
            `<option value="${c.id}">${htmlSafe(c.nombre)} (${c.tipo === "albergue" ? "albergue" : "acopio"})</option>`).join("");
        filtroCentro.innerHTML = `<option value="">Todos los centros</option>` + lista;
        formulario.centro_id.innerHTML = lista;
        if (centros.some(c => String(c.id) === elegido)) filtroCentro.value = elegido;
    }

    function datalist(id, valores) {
        document.getElementById(id).innerHTML = valores.map(v => `<option value="${htmlSafe(v)}">`).join("");
    }

    // Ajusta el formulario a la categoría: unidades, sugerencias y talla (solo ropa).
    function actualizarCampos() {
        const categoria = formulario.categoria.value;
        const esRopa = categoria === "ropa";
        const esPar = esRopa && ES_PAR.test(formulario.producto.value);
        const permitidas = UNIDADES_POR_CATEGORIA[categoria] || Object.keys(UNIDADES);
        const anterior = formulario.unidad.value;

        formulario.unidad.innerHTML = permitidas.map(u => `<option value="${u}">${UNIDADES[u]}</option>`).join("");
        if (esPar) formulario.unidad.value = "pares";
        else if (permitidas.includes(anterior)) formulario.unidad.value = anterior;

        document.getElementById("campo-talla").hidden = !esRopa;
        if (!esRopa) formulario.talla.value = "";
        formulario.talla.placeholder = esPar ? "Ej. 28, 38" : "Ej. S, M, 10";
        datalist("sugerencias-tallas", esPar ? TALLAS_CALZADO : TALLAS_ROPA);
        datalist("sugerencias-productos", SUGERENCIAS[categoria] || []);
    }

    /* ---------- Pintar ---------- */

    function filtrados() {
        const texto = normalizar(buscador.value.trim());
        return productos.filter(p =>
            (!filtroCentro.value || String(p.centro_id) === filtroCentro.value) &&
            (!filtroCategoria.value || p.categoria === filtroCategoria.value) &&
            (!filtroEstado.value || estado(p) === filtroEstado.value) &&
            (!texto || normalizar(`${p.producto} ${p.talla || ""} ${p.centro_nombre}`).includes(texto)));
    }

    // Tarjetas por categoría (respetan el filtro de centro). Tocar una filtra la tabla.
    function pintarResumen() {
        const base = productos.filter(p => !filtroCentro.value || String(p.centro_id) === filtroCentro.value);
        resumen.innerHTML = Object.keys(CATEGORIAS).map(clave => {
            const deCategoria = base.filter(p => p.categoria === clave);
            if (!deCategoria.length) return "";
            const agotados = deCategoria.filter(p => estado(p) === "agotado").length;
            const bajos = deCategoria.filter(p => estado(p) === "bajo").length;
            const alerta = agotados ? `<small class="inv_alerta agotado">${agotados} agotado${agotados === 1 ? "" : "s"}</small>`
                : bajos ? `<small class="inv_alerta bajo">${bajos} por agotarse</small>`
                    : `<small class="inv_alerta ok">Todo suficiente</small>`;
            return `<button type="button" class="inv_resumen_item${filtroCategoria.value === clave ? " activo" : ""}" data-categoria="${clave}">
                <i class="fa-solid ${CATEGORIAS[clave].icono}"></i>
                <span><strong>${htmlSafe(CATEGORIAS[clave].texto)}</strong>
                ${deCategoria.length} producto${deCategoria.length === 1 ? "" : "s"}</span>
                ${alerta}
            </button>`;
        }).join("");
    }

    function filaProducto(p) {
        const est = estado(p);
        const esAlbergue = p.centro_tipo === "albergue";
        return `<tr data-producto="${p.id}">
            <td data-titulo="Producto"><strong>${htmlSafe(p.producto)}</strong>${p.talla ? ` <span class="inv_talla">Talla ${htmlSafe(p.talla)}</span>` : ""}</td>
            <td data-titulo="Centro"><span class="inv_centro"><i class="fa-solid ${esAlbergue ? "fa-house-chimney" : "fa-boxes-stacked"}"></i> ${htmlSafe(p.centro_nombre)}</span></td>
            <td data-titulo="Cantidad">
                <div class="inv_cantidad">
                    <button type="button" class="inv_paso" data-paso="-1" aria-label="Restar uno a ${htmlSafe(p.producto)}">−</button>
                    <input type="number" min="0" max="1000000" step="1" value="${p.cantidad}" data-cantidad="${p.id}" aria-label="Cantidad de ${htmlSafe(p.producto)}">
                    <button type="button" class="inv_paso" data-paso="1" aria-label="Sumar uno a ${htmlSafe(p.producto)}">+</button>
                    <span class="inv_unidad">${htmlSafe(UNIDADES[p.unidad] || p.unidad)}</span>
                </div>
            </td>
            <td data-titulo="Mínimo">${p.minimo ? p.minimo : "—"}</td>
            <td data-titulo="Estado"><span class="inv_estado ${est}">${TEXTO_ESTADO[est]}</span></td>
            <td data-titulo="Actualizado"><small>${htmlSafe(fecha(p.actualizado_en, true))}</small></td>
            <td data-titulo="Acciones" class="inv_acciones">
                <button type="button" class="admin_boton_secundario" data-editar-producto="${p.id}" aria-label="Editar ${htmlSafe(p.producto)}"><i class="fa-solid fa-pen"></i></button>
                <button type="button" class="admin_boton_secundario peligro" data-eliminar-producto="${p.id}" aria-label="Eliminar ${htmlSafe(p.producto)}"><i class="fa-solid fa-trash"></i></button>
            </td>
        </tr>`;
    }

    function pintarTabla() {
        pintarResumen();
        if (!centros.length) {
            tabla.innerHTML = `<tr><td colspan="7" class="admin_vacio">Primero registra un centro de acopio o albergue en la pestaña "Centros y albergues".</td></tr>`;
            return;
        }
        if (!productos.length) {
            tabla.innerHTML = `<tr><td colspan="7" class="admin_vacio">El inventario está vacío. Pulsa "Agregar producto" para registrar el primero.</td></tr>`;
            return;
        }
        const lista = filtrados();
        if (!lista.length) {
            tabla.innerHTML = `<tr><td colspan="7" class="admin_vacio">No hay productos que coincidan con los filtros.</td></tr>`;
            return;
        }
        // Una fila de título por categoría y debajo sus productos.
        tabla.innerHTML = Object.keys(CATEGORIAS).map(clave => {
            const deCategoria = lista.filter(p => p.categoria === clave);
            if (!deCategoria.length) return "";
            const total = deCategoria.reduce((suma, p) => suma + p.cantidad, 0);
            return `<tr class="inv_fila_categoria"><td colspan="7">
                    <i class="fa-solid ${CATEGORIAS[clave].icono}"></i> ${htmlSafe(CATEGORIAS[clave].texto)}
                    <span>${deCategoria.length} producto${deCategoria.length === 1 ? "" : "s"} · ${total.toLocaleString("es-CO")} en total</span>
                </td></tr>` + deCategoria.map(filaProducto).join("");
        }).join("");
    }

    /* ---------- Cargar ---------- */

    async function cargar() {
        tabla.innerHTML = `<tr><td colspan="7" class="admin_vacio">Cargando inventario...</td></tr>`;
        try {
            [centros, productos] = await Promise.all([
                llamarApi("/api/centros"),
                llamarApi("/api/centros/inventario")
            ]);
            mostrarMensaje("mensaje-inventario", "");
            llenarCentros();
            pintarTabla();
        } catch (error) {
            tabla.innerHTML = "";
            mostrarMensaje("mensaje-inventario", textoError(error), "error");
        }
    }

    /* ---------- Formulario ---------- */

    function abrirFormulario(producto) {
        editando = producto || null;
        formulario.reset();
        llenarCentros();
        document.getElementById("titulo-formulario-producto").textContent =
            producto ? `Editar: ${producto.producto}${producto.talla ? " · Talla " + producto.talla : ""}` : "Agregar producto";
        if (producto) {
            ["centro_id", "categoria", "producto", "cantidad", "minimo"].forEach(campo => {
                formulario[campo].value = producto[campo];
            });
            formulario.talla.value = producto.talla || "";
            actualizarCampos();
            // La unidad guardada se respeta aunque no esté entre las propuestas.
            if (![...formulario.unidad.options].some(o => o.value === producto.unidad)) {
                formulario.unidad.insertAdjacentHTML("beforeend", `<option value="${producto.unidad}">${UNIDADES[producto.unidad] || producto.unidad}</option>`);
            }
            formulario.unidad.value = producto.unidad;
        } else {
            // Propone el centro y la categoría que se están mirando.
            if (filtroCentro.value) formulario.centro_id.value = filtroCentro.value;
            if (filtroCategoria.value) formulario.categoria.value = filtroCategoria.value;
            actualizarCampos();
        }
        mostrarMensaje("mensaje-formulario-producto", "");
        formulario.hidden = false;
        formulario.scrollIntoView({ behavior: "smooth", block: "start" });
        formulario.producto.focus({ preventScroll: true });
    }

    function cerrarFormulario() {
        formulario.hidden = true;
        editando = null;
    }

    formulario.categoria.addEventListener("change", actualizarCampos);
    // Al escribir "Zapatos", "Chanclas" o "Medias" la unidad pasa sola a "pares".
    formulario.producto.addEventListener("input", () => {
        if (formulario.categoria.value !== "ropa") return;
        const esPar = ES_PAR.test(formulario.producto.value);
        if (esPar && formulario.unidad.value !== "pares") formulario.unidad.value = "pares";
        formulario.talla.placeholder = esPar ? "Ej. 28, 38" : "Ej. S, M, 10";
        datalist("sugerencias-tallas", esPar ? TALLAS_CALZADO : TALLAS_ROPA);
    });
    document.getElementById("boton-nuevo-producto").addEventListener("click", () => {
        if (!centros.length) {
            mostrarMensaje("mensaje-inventario", "Primero registra un centro en la pestaña \"Centros y albergues\".", "error");
            return;
        }
        abrirFormulario(null);
    });
    document.getElementById("cancelar-producto").addEventListener("click", cerrarFormulario);

    formulario.addEventListener("submit", async evento => {
        evento.preventDefault();
        const datos = {
            centro_id: Number(formulario.centro_id.value),
            categoria: formulario.categoria.value,
            producto: formulario.producto.value.trim(),
            talla: formulario.categoria.value === "ropa" ? formulario.talla.value.trim() : "",
            cantidad: Number(formulario.cantidad.value || 0),
            unidad: formulario.unidad.value,
            minimo: Number(formulario.minimo.value || 0)
        };
        if (datos.producto.length < 2) return mostrarMensaje("mensaje-formulario-producto", "Escribe el nombre del producto.", "error");
        if (!Number.isInteger(datos.cantidad) || datos.cantidad < 0) return mostrarMensaje("mensaje-formulario-producto", "La cantidad debe ser un número entero de 0 en adelante.", "error");
        if (!Number.isInteger(datos.minimo) || datos.minimo < 0) return mostrarMensaje("mensaje-formulario-producto", "El mínimo debe ser un número entero de 0 en adelante.", "error");

        const boton = document.getElementById("guardar-producto");
        boton.disabled = true;
        try {
            const eraEdicion = Boolean(editando);
            await llamarApi(eraEdicion ? `/api/admin/inventario/${editando.id}` : "/api/admin/inventario",
                { method: "POST", body: JSON.stringify(datos) });
            cerrarFormulario();
            mostrarMensaje("mensaje-inventario", eraEdicion ? "Producto actualizado." : `"${datos.producto}" se agregó al inventario.`, "exito");
            await cargar();
        } catch (error) {
            mostrarMensaje("mensaje-formulario-producto", textoError(error), "error");
        } finally {
            boton.disabled = false;
        }
    });

    /* ---------- Cambiar la cantidad desde la tabla ---------- */

    async function guardarCantidad(id, cantidad, entrada) {
        const producto = productos.find(p => p.id === id);
        if (!producto || cantidad === producto.cantidad) return;
        if (!Number.isInteger(cantidad) || cantidad < 0 || cantidad > 1000000) {
            entrada.value = producto.cantidad;
            mostrarMensaje("mensaje-inventario", "La cantidad debe ser un número entero de 0 en adelante.", "error");
            return;
        }
        entrada.disabled = true;
        try {
            const actualizado = await llamarApi(`/api/admin/inventario/${id}/cantidad`,
                { method: "POST", body: JSON.stringify({ cantidad: cantidad }) });
            Object.assign(producto, actualizado);
            mostrarMensaje("mensaje-inventario", "");
            pintarTabla();
            // Devuelve el foco a la misma casilla tras volver a pintar.
            tabla.querySelector(`[data-cantidad="${id}"]`)?.focus();
        } catch (error) {
            entrada.value = producto.cantidad;
            entrada.disabled = false;
            mostrarMensaje("mensaje-inventario", textoError(error), "error");
        }
    }

    tabla.addEventListener("change", evento => {
        const entrada = evento.target.closest("[data-cantidad]");
        if (entrada) guardarCantidad(Number(entrada.dataset.cantidad), Number(entrada.value), entrada);
    });

    tabla.addEventListener("keydown", evento => {
        // Enter guarda sin tener que salir de la casilla.
        if (evento.key === "Enter" && evento.target.matches("[data-cantidad]")) {
            evento.preventDefault();
            evento.target.blur();
        }
    });

    tabla.addEventListener("click", async evento => {
        const paso = evento.target.closest("[data-paso]");
        if (paso) {
            const entrada = paso.parentElement.querySelector("[data-cantidad]");
            const nuevo = Math.max(0, Number(entrada.value || 0) + Number(paso.dataset.paso));
            entrada.value = nuevo;
            guardarCantidad(Number(entrada.dataset.cantidad), nuevo, entrada);
            return;
        }
        const editar = evento.target.closest("[data-editar-producto]");
        if (editar) {
            abrirFormulario(productos.find(p => p.id === Number(editar.dataset.editarProducto)));
            return;
        }
        const eliminar = evento.target.closest("[data-eliminar-producto]");
        if (eliminar) {
            const producto = productos.find(p => p.id === Number(eliminar.dataset.eliminarProducto));
            if (!producto || !window.confirm(`¿Eliminar "${producto.producto}${producto.talla ? " talla " + producto.talla : ""}" del inventario de ${producto.centro_nombre}?`)) return;
            try {
                await llamarApi(`/api/admin/inventario/${producto.id}/eliminar`, { method: "POST" });
                mostrarMensaje("mensaje-inventario", "Producto eliminado.", "exito");
                await cargar();
            } catch (error) {
                mostrarMensaje("mensaje-inventario", textoError(error), "error");
            }
        }
    });

    /* ---------- Filtros ---------- */

    resumen.addEventListener("click", evento => {
        const tarjeta = evento.target.closest("[data-categoria]");
        if (!tarjeta) return;
        // Tocar la categoría activa quita el filtro.
        filtroCategoria.value = filtroCategoria.value === tarjeta.dataset.categoria ? "" : tarjeta.dataset.categoria;
        pintarTabla();
    });
    [filtroCentro, filtroCategoria, filtroEstado].forEach(control => control.addEventListener("change", pintarTabla));
    buscador.addEventListener("input", pintarTabla);

    // Botón "Inventario" de cada centro (pestaña Centros y albergues, js/admin.js).
    document.getElementById("lista-centros-admin")?.addEventListener("click", evento => {
        const boton = evento.target.closest("[data-inventario]");
        if (!boton) return;
        filtroCategoria.value = "";
        filtroEstado.value = "";
        buscador.value = "";
        filtroCentro.dataset.pendiente = boton.dataset.inventario;
        const yaCargado = centros.length > 0;
        A.abrirSeccion("inventario");
        // Si la pestaña ya estaba cargada, se recarga por si el centro es nuevo.
        if (yaCargado) cargar().then(aplicarCentroPendiente);
    });

    // El filtro de centro solo se puede fijar cuando ya están cargadas sus opciones.
    function aplicarCentroPendiente() {
        const pendiente = filtroCentro.dataset.pendiente;
        if (!pendiente || !centros.length) return;
        filtroCentro.value = pendiente;
        delete filtroCentro.dataset.pendiente;
        pintarTabla();
    }

    A.registrarSeccion("inventario", async () => {
        await cargar();
        aplicarCentroPendiente();
    });
})();
