const formulario = document.getElementById("form_solicitud");
const mensaje = document.getElementById("mensaje_solicitud");

formulario.addEventListener("submit", async function (event) {

    event.preventDefault();

    const datos = new FormData();

    datos.append(
        "tipo_ayuda",
        document.getElementById("tipo_ayuda").value
    );

    datos.append(
        "titulo_solicitud",
        document.getElementById("titulo_solicitud").value
    );

    datos.append(
        "sector",
        document.getElementById("sector").value
    );

    datos.append(
        "descripcion",
        document.getElementById("descripcion").value
    );

    datos.append(
        "personas_afectadas",
        document.getElementById("personas_afectadas").value
    );

    datos.append(
        "urgencia",
        document.querySelector(
            'input[name="urgencia"]:checked'
        ).value
    );

    datos.append(
        "ubicacion",
        document.getElementById("ubicacion").value
    );


    try {

        const respuesta = await fetch(
            "http://127.0.0.1:5000/api/solicitudes-ayuda",
            {
                method: "POST",

                headers: {
                    "Authorization":
                        "Bearer " + localStorage.getItem("access_token")
                },

                body: datos
            }
        );


        const resultado = await respuesta.json();


        if (!respuesta.ok) {

            mensaje.textContent =
                resultado.error || "No se pudo enviar la solicitud.";

            mensaje.style.display = "block";

            return;
        }


        mensaje.textContent =
            "✓ Solicitud enviada correctamente. Número de solicitud: "
            + resultado.id;

        mensaje.style.display = "block";


        formulario.reset();


    } catch (error) {

        console.error(error);

        mensaje.textContent =
            "No fue posible conectar con el servidor.";

        mensaje.style.display = "block";
    }

});