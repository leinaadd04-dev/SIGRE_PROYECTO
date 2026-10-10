/* SIGRE · Módulo dinámico de desaparecidos */
(() => {
    const API_BASE = window.SIGRE_API;   // js/config.js
    const ENDPOINT = API_BASE + "/api/desaparecidos";

    const grid = document.getElementById("cuadricula-reportes");
    const statusBox = document.getElementById("estado-reportes");
    const counter = document.getElementById("contador-reportes");
    const search = document.getElementById("filtro-texto");
    const typeFilter = document.getElementById("filtro-tipo");
    const statusFilter = document.getElementById("filtro-estado");
    const fileInput = document.getElementById("input-foto");
    const dropZone = document.getElementById("zona-subida");
    const preview = document.getElementById("foto-previsualizada");
    const uploadContents = document.getElementById("contenido-zona-subida");
    const addDetailsButton = document.getElementById("boton-anadir-datos");
    const formSection = document.getElementById("seccion-formulario");
    const form = document.getElementById("formulario-reporte");
    const typeInput = document.getElementById("tipo-reporte");
    const message = document.getElementById("mensaje-formulario");
    const modal = document.getElementById("ventana-caso-fondo");
    const posterLink = document.getElementById("boton-descargar-cartel");
    const commentsPanel = document.getElementById("panel-comentarios");
    const openCommentsButton = document.getElementById("boton-abrir-comentarios");
    const closeCommentsButton = document.getElementById("boton-cerrar-comentarios");
    const commentList = document.getElementById("lista-comentarios");
    const commentForm = document.getElementById("formulario-comentario");
    const commentStatus = document.getElementById("estado-comentarios");
    const loginCommentNotice = document.getElementById("aviso-iniciar-sesion-comentario");
    let photoFile = null;
    let selectedType = "persona";
    let searchTimer;
    let loadedReports = [];
    let currentReport = null;

    function htmlSafe(value) {
        return String(value == null ? "" : value).replace(/[&<>"']/g, function (char) {
            return {
                "&": "&amp;", "<": "&lt;", ">": "&gt;",
                '"': "&quot;", "'": "&#39;"
            }[char];
        });
    }

    function fullPhotoUrl(path) {
        return path.indexOf("http") === 0 ? path : API_BASE + path;
    }

    function getToken() {
        return localStorage.getItem("sigre_token");
    }

    function headersAutenticados() {
        const token = getToken();
        return token ? { Authorization: "Bearer " + token } : {};
    }

    function renderReports(reports) {
        loadedReports = reports;
        counter.textContent = String(reports.length);

        if (!reports.length) {
            grid.innerHTML = "";
            statusBox.hidden = false;
            statusBox.classList.remove("error");
            statusBox.textContent = "No hay reportes que coincidan con esos filtros.";
            return;
        }

        statusBox.hidden = true;
        grid.innerHTML = reports.map(function (report) {
            const statusText = report.estado === "encontrado" ? "Encontrado" : "Activo";
            const statusClass = report.estado === "encontrado" ? "encontrado" : "activo";
            const detail = [report.edad, report.sector].filter(Boolean).join(" · ");
            const textoCompartir = encodeURIComponent(
    `SIGRE: reporte de ${report.tipo} de ${report.nombre}. ` +
    `Visto en: ${report.sector || "sector no especificado"}.`
);
const urlCompartir = encodeURIComponent(window.location.href.split("#")[0]);

return '<article class="tarjeta_reporte" data-reporte-id="' +
    htmlSafe(report.id) + '">' +
    '<div class="foto_reporte_compartir">' +
        '<img src="' + htmlSafe(fullPhotoUrl(report.foto_url)) +
        '" alt="Foto de ' + htmlSafe(report.nombre) + '" loading="lazy">' +
        '<button type="button" class="boton_compartir" aria-label="Compartir reporte">' +
            '<i class="fa-solid fa-share-nodes"></i>' +
        '</button>' +
        '<div class="menu_compartir" hidden>' +
            '<a target="_blank" rel="noopener noreferrer" href="https://wa.me/?text=' +
              textoCompartir + '%20' + urlCompartir +
            '"><i class="fa-brands fa-whatsapp"></i> WhatsApp</a>' +
            '<a target="_blank" rel="noopener noreferrer" href="https://www.facebook.com/sharer/sharer.php?u=' +
             urlCompartir + '"><i class="fa-brands fa-facebook"></i> Facebook</a>' +
            '<a target="_blank" rel="noopener noreferrer" href="https://www.instagram.com/">' +
             '<i class="fa-brands fa-instagram"></i> Instagram</a>' +
             '<button  type="button" class="copiar_enlace_reporte" data-url="' +
            urlCompartir +
            '"><i class="fa-solid fa-link" ></i> Copiar enlace</button>' +
            
        '</div>' +
    '</div>' +
    '<span class="etiqueta_estado ' + statusClass + '">' + statusText + '</span>' +
    '<div class="info_tarjeta_reporte"><h3>' + htmlSafe(report.nombre) + '</h3>' +
        '<p>' + htmlSafe(detail || "Información del reporte") + '</p>' +
    '</div>' +
'</article>';


        }).join("");
    }

    async function loadReports() {
        statusBox.hidden = false;
        statusBox.classList.remove("error");
        statusBox.textContent = "Cargando reportes...";

        const params = new URLSearchParams();
        if (typeFilter.value) params.set("tipo", typeFilter.value);
        if (statusFilter.value) params.set("estado", statusFilter.value);
        if (search.value.trim()) params.set("q", search.value.trim());

        try {
            const response = await fetch(ENDPOINT + "?" + params.toString());
            const data = await response.json();
            if (!response.ok) throw new Error(data.error || "Error al cargar reportes");
            renderReports(data);
        } catch (error) {
            grid.innerHTML = "";
            counter.textContent = "0";
            statusBox.hidden = false;
            statusBox.classList.add("error");
            statusBox.textContent = "No se pudieron cargar reportes. Revisa que Flask, la base de datos y la migración estén listos.";
            console.error(error);
        }
    }

    function setType(type) {
        selectedType = type;
        typeInput.value = type;
        document.querySelectorAll(".boton_tipo").forEach(function (button) {
            const active = button.dataset.tipo === type;
            button.classList.toggle("activo", active);
            button.setAttribute("aria-pressed", String(active));
        });
    }

    document.querySelectorAll(".boton_tipo").forEach(function (button) {
        button.addEventListener("click", function () {
            setType(button.dataset.tipo);
        });
    });

    function choosePhoto(file) {
        if (!file) return;
        const allowedTypes = ["image/jpeg", "image/png", "image/webp"];
        if (!allowedTypes.includes(file.type)) {
            alert("Selecciona una imagen JPG, PNG o WEBP.");
            return;
        }
        if (file.size > 5 * 1024 * 1024) {
            alert("La imagen debe pesar máximo 5 MB.");
            return;
        }
        photoFile = file;
        preview.src = URL.createObjectURL(file);
        preview.hidden = false;
        uploadContents.hidden = true;
        addDetailsButton.hidden = false;
    }

    dropZone.addEventListener("click", function (event) {
        if (event.target !== fileInput) fileInput.click();
    });
    dropZone.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            fileInput.click();
        }
    });
    fileInput.addEventListener("change", function () {
        choosePhoto(fileInput.files[0]);
    });
    ["dragenter", "dragover"].forEach(function (eventName) {
        dropZone.addEventListener(eventName, function (event) {
            event.preventDefault();
            dropZone.classList.add("arrastrando");
        });
    });
    ["dragleave", "drop"].forEach(function (eventName) {
        dropZone.addEventListener(eventName, function (event) {
            event.preventDefault();
            dropZone.classList.remove("arrastrando");
        });
    });
    dropZone.addEventListener("drop", function (event) {
        choosePhoto(event.dataTransfer.files[0]);
    });

    addDetailsButton.addEventListener("click", function () {
        if (!photoFile) return;
        formSection.hidden = false;
        formSection.scrollIntoView({ behavior: "smooth", block: "start" });
        document.getElementById("nombre-reporte").focus({ preventScroll: true });
    });

    function openReport(report) {
        currentReport = report;
        document.getElementById("ventana-foto").src = fullPhotoUrl(report.foto_url);
        document.getElementById("ventana-foto").alt = "Foto de " + report.nombre;
        document.getElementById("ventana-nombre").textContent = report.nombre;
        document.getElementById("ventana-edad").textContent = report.edad || "Edad no especificada";
        document.getElementById("ventana-genero").textContent = report.genero || "Género no especificado";
        document.getElementById("ventana-ubicacion").textContent = report.sector || "Sector no especificado";
        posterLink.href = API_BASE + "/api/desaparecidos/" + encodeURIComponent(report.id) + "/cartel";
        const telefono = document.getElementById("ventana-telefono");

        if (report.telefono_contacto) {
            telefono.textContent = report.telefono_contacto;
            telefono.href = "tel:" + report.telefono_contacto;
        } else {
            telefono.textContent = "Teléfono no especificado";
            telefono.removeAttribute("href");
        }
        document.getElementById("ventana-fecha").textContent = report.fecha_visto
            ? new Date(report.fecha_visto).toLocaleString("es-CO")
            : "Fecha no especificada";
        document.getElementById("ventana-descripcion").textContent = report.descripcion || "";
        const state = document.getElementById("ventana-estado");
        state.textContent = report.estado === "encontrado" ? "Encontrado" : "Activo";
        state.classList.toggle("encontrado", report.estado === "encontrado");
        commentForm.hidden = !getToken();
        loginCommentNotice.hidden = Boolean(getToken());
        commentsPanel.hidden = true;
        openCommentsButton.setAttribute("aria-expanded", "false");
        openCommentsButton.innerHTML = '<i class="fa-solid fa-comment-dots" aria-hidden="true"></i> Comentar';
        commentStatus.textContent = report.notificaciones_disponibles === false
            ? "Este reporte es anterior al registro de autores. El comentario se guardará, pero no se podrá notificar a quien lo publicó."
            : "";
        modal.hidden = false;
        commentList.innerHTML = "";
        document.getElementById("boton-cerrar-ventana").focus();
    }

    async function loadComments(report) {
        commentList.innerHTML = "<p>Cargando comentarios...</p>";
        try {
            const response = await fetch(ENDPOINT + "/" + encodeURIComponent(report.id) + "/comentarios");
            const data = await response.json();
            if (!response.ok) throw new Error(data.error || "No se pudieron cargar los comentarios.");
            commentList.innerHTML = data.length
                ? data.map(function (item) {
                    const fecha = new Date(item.creado_en).toLocaleString("es-CO");
                    return '<article class="comentario_testigo"><strong>' + htmlSafe(item.nombre_testigo) +
                        '</strong><p>' + htmlSafe(item.comentario) + '</p><time>' + htmlSafe(fecha) + '</time></article>';
                }).join("")
                : '<p class="sin_comentarios">Todavía no hay comentarios. Si tienes información verídica, compártela.</p>';
        } catch (error) {
            commentList.innerHTML = '<p class="error_comentarios">' + htmlSafe(error.message) + '</p>';
        }
    }

    commentForm.addEventListener("submit", async function (event) {
        event.preventDefault();
        if (!currentReport || !getToken()) {
            loginCommentNotice.hidden = false;
            commentForm.hidden = true;
            return;
        }
        const submitButton = document.getElementById("boton-enviar-comentario");
        submitButton.disabled = true;
        commentStatus.textContent = "Enviando comentario...";
        try {
            const response = await fetch(ENDPOINT + "/" + encodeURIComponent(currentReport.id) + "/comentarios", {
                method: "POST",
                headers: Object.assign({ "Content-Type": "application/json" }, headersAutenticados()),
                body: JSON.stringify({
                    comentario: document.getElementById("texto-comentario").value,
                    telefono_testigo: document.getElementById("telefono-testigo").value,
                    veracidad_confirmada: document.getElementById("confirmar-veracidad").checked,
                    autoriza_compartir_telefono: document.getElementById("autorizar-telefono").checked
                })
            });
            const data = await response.json();
            if (!response.ok) throw new Error(data.error || "No se pudo enviar el comentario.");
            commentForm.reset();
            await loadComments(currentReport);
            commentStatus.textContent = data.detalle || "Comentario enviado.";
        } catch (error) {
            commentStatus.textContent = error.message;
        } finally {
            submitButton.disabled = false;
        }
    });

    grid.addEventListener("click", function (event) {
                const botonCompartir = event.target.closest(".boton_compartir");

        if (botonCompartir) {
            event.stopPropagation();
            const menu = botonCompartir.nextElementSibling;
            menu.hidden = !menu.hidden;
            return;
        }

        if (event.target.closest(".menu_compartir")) return;
        const card = event.target.closest(".tarjeta_reporte");
        if (!card) return;
        const report = loadedReports.find(function (item) {
            return String(item.id) === card.dataset.reporteId;
        });
        if (report) openReport(report);
    });

    function closeModal() { modal.hidden = true; }
    function openComments() {
        commentsPanel.hidden = false;
        openCommentsButton.setAttribute("aria-expanded", "true");
        openCommentsButton.innerHTML = '<i class="fa-solid fa-comment-dots" aria-hidden="true"></i> Cerrar comentarios';
        loadComments(currentReport);
        commentsPanel.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
    function closeComments() {
        commentsPanel.hidden = true;
        openCommentsButton.setAttribute("aria-expanded", "false");
        openCommentsButton.innerHTML = '<i class="fa-solid fa-comment-dots" aria-hidden="true"></i> Comentar';
        openCommentsButton.focus();
    }
    openCommentsButton.addEventListener("click", function () {
        if (commentsPanel.hidden) openComments();
        else closeComments();
    });
    closeCommentsButton.addEventListener("click", closeComments);
    document.getElementById("boton-cerrar-ventana").addEventListener("click", closeModal);
    modal.addEventListener("click", function (event) {
        if (event.target === modal) closeModal();
    });
    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && !modal.hidden) closeModal();
    });

    [typeFilter, statusFilter].forEach(function (control) {
        control.addEventListener("change", loadReports);
    });
    search.addEventListener("input", function () {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(loadReports, 250);
    });

    form.addEventListener("submit", async function (event) {
        event.preventDefault();
        message.textContent = "";
        if (!getToken()) {
            message.textContent = "Inicia sesión en SIGRE para publicar el reporte y recibir sus comentarios. ";
            const loginLink = document.createElement("a");
            loginLink.href = "login.html";
            loginLink.textContent = "Ir a iniciar sesión";
            message.appendChild(loginLink);
            return;
        }
        if (!photoFile) {
            message.textContent = "Primero selecciona la foto del reporte.";
            return;
        }

        const formData = new FormData(form);
        formData.set("tipo", selectedType);
        formData.set("foto", photoFile, photoFile.name);
        formData.set(
            "autoriza_publicacion",
            document.getElementById("autoriza-publicacion").checked ? "true" : "false"
        );

        const submitButton = document.getElementById("boton-publicar");
        submitButton.disabled = true;
        submitButton.textContent = "Publicando...";

        try {
            const response = await fetch(ENDPOINT, {
                method: "POST",
                headers: headersAutenticados(),
                body: formData
            });
            const result = await response.json();
            if (!response.ok) throw new Error(result.error || "No fue posible publicar el reporte.");

            message.textContent = "Reporte publicado.";
            form.reset();
            photoFile = null;
            fileInput.value = "";
            preview.removeAttribute("src");
            preview.hidden = true;
            uploadContents.hidden = false;
            addDetailsButton.hidden = true;
            formSection.hidden = true;
            setType("persona");
            await loadReports();
            document.querySelector(".seccion_reportes").scrollIntoView({ behavior: "smooth" });
        } catch (error) {
            message.textContent = error.message;
        } finally {
            submitButton.disabled = false;
            submitButton.innerHTML = '<i class="fa-solid fa-bullhorn"></i> Publicar reporte';
        }
    });

    // Las notificaciones llevan a desaparecidos.html?reporte=ID: abre ese caso.
    async function openReportFromUrl() {
        const reportId = new URLSearchParams(window.location.search).get("reporte");
        await loadReports();
        if (!reportId) return;
        const report = loadedReports.find(function (item) { return String(item.id) === reportId; });
        if (!report) return;
        document.querySelector('.tarjeta_reporte[data-reporte-id="' + CSS.escape(reportId) + '"]')
            ?.scrollIntoView({ behavior: "smooth", block: "center" });
        openReport(report);
    }

    openReportFromUrl();
})();

