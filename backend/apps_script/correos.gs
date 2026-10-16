// SIGRE · Envío de correos con Google Apps Script
//
// Render (plan gratis) bloquea el SMTP de Gmail, así que el backend publicado
// envía los correos (código de verificación y recuperación de contraseña)
// llamando por HTTPS a este script, que vive en la cuenta del proyecto
// (sigre.oficial@gmail.com) y los envía con MailApp. Ver _enviar_correo_ahora()
// en backend/app.py.
//
// Instalación (en script.google.com, con la cuenta del proyecto):
//   1. Nuevo proyecto "SIGRE correos" y pegar este código.
//   2. ⚙️ Configuración del proyecto → Propiedades de las secuencias de comandos:
//      CLAVE_SIGRE = una clave aleatoria (la misma de MAIL_SCRIPT_CLAVE en Render).
//   3. Ejecutar probar() una vez para autorizar el envío de correos.
//   4. Implementar → Nueva implementación → Aplicación web, ejecutar como "Yo"
//      y acceso "Cualquier persona". La URL (/exec) va en MAIL_SCRIPT_URL.
//
// Petición que espera (JSON): { clave, para, asunto, texto }
// Respuesta: { ok: true } o { ok: false, error: "..." }

function doPost(e) {
  try {
    const datos = JSON.parse(e.postData.contents);
    const clave = PropertiesService.getScriptProperties().getProperty("CLAVE_SIGRE");
    if (!clave || datos.clave !== clave) {
      return responder({ ok: false, error: "no autorizado" });
    }
    if (!datos.para || !datos.asunto || !datos.texto) {
      return responder({ ok: false, error: "faltan datos" });
    }
    MailApp.sendEmail({ to: datos.para, subject: datos.asunto, body: datos.texto, name: "SIGRE" });
    return responder({ ok: true });
  } catch (error) {
    return responder({ ok: false, error: String(error) });
  }
}

function responder(objeto) {
  return ContentService.createTextOutput(JSON.stringify(objeto))
    .setMimeType(ContentService.MimeType.JSON);
}

// Ejecútala una vez a mano para dar permiso de enviar correos.
function probar() {
  MailApp.sendEmail(Session.getActiveUser().getEmail(), "Prueba de SIGRE", "El envío de correos funciona.");
}

// Diagnóstico: muestra cómo es la clave guardada, sin mostrarla completa.
function revisarClave() {
  const clave = PropertiesService.getScriptProperties().getProperty("CLAVE_SIGRE");
  if (!clave) {
    console.log("NO existe la propiedad CLAVE_SIGRE");
    return;
  }
  console.log("CLAVE_SIGRE tiene " + clave.length + " caracteres. Empieza por «" +
              clave.slice(0, 4) + "» y termina en «" + clave.slice(-4) + "».");
}
