import io
import os 
from pathlib import Path

import smtplib
from email.message import EmailMessage
from itsdangerous import URLSafeTimedSerializer
from dotenv import load_dotenv

import hashlib
import secrets
from datetime import timedelta

import re
import secrets
import threading
from datetime import date, datetime, timedelta
import psycopg
import unicodedata
from urllib.parse import urlparse

import requests

from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_file, send_from_directory
from flask_jwt_extended import JWTManager,create_access_token
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required
from reportlab.lib.pagesizes import A4
from reportlab.lib.utils import ImageReader, simpleSplit
from reportlab.pdfgen import canvas
from PIL import Image, ImageOps

from werkzeug.security import check_password_hash, generate_password_hash

from database import obtener_conexion
from rutas import rutas_bp
from administracion import administracion_bp
from notificaciones import notificaciones_bp
from push import push_bp

#lee las variables del archivo backend/.env
load_dotenv(Path(__file__).resolve().parent / ".env")


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024 + 64 * 1024

#flask toma la clave del archivo .env

app.config["JWT_SECRET_KEY"]= os.getenv("JWT_SECRET_KEY")

if not app.config["JWT_SECRET_KEY"]:
    raise RuntimeError("No se encontró JWT_SECRET_KEY en backend/.env")

# Duración de la sesión. Por defecto 8 horas; se puede cambiar con
# JWT_HORAS_SESION en backend/.env (Flask-JWT-Extended usa 15 minutos).
app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(
    hours=int(os.getenv("JWT_HORAS_SESION", "8"))
)

jwt= JWTManager(app)
app.register_blueprint(rutas_bp)
app.register_blueprint(administracion_bp)
app.register_blueprint(notificaciones_bp)
app.register_blueprint(push_bp)


def emitir_token(usuario_id, rol):
    return create_access_token(
        identity=str(usuario_id),
        additional_claims={"rol": rol}
    )


@app.get("/api/auth/google/config")
def configuracion_google():
    # El Client ID es público; el secreto de cliente nunca se expone al navegador.
    return jsonify({"client_id": os.getenv("GOOGLE_CLIENT_ID", "")})


@app.post("/api/auth/google")
def iniciar_sesion_google():
    datos = request.get_json(silent=True)
    credencial = datos.get("credential") if isinstance(datos, dict) else None
    client_id = os.getenv("GOOGLE_CLIENT_ID")
    if not client_id:
        return jsonify({"error": "Falta configurar GOOGLE_CLIENT_ID en backend/.env"}), 503
    if not isinstance(credencial, str) or not credencial:
        return jsonify({"error": "Google no envió una credencial válida"}), 400

    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token
        claims = id_token.verify_oauth2_token(
            credencial, google_requests.Request(), client_id
        )
    except ImportError:
        return jsonify({"error": "Instala las dependencias de Google con pip install google-auth"}), 503
    except Exception:
        return jsonify({"error": "No se pudo verificar la cuenta de Google"}), 401

    correo_google = claims.get("email")
    if not isinstance(correo_google, str):
        return jsonify({"error": "Google no devolvió un correo válido"}), 401
    email = correo_google.strip().lower()
    google_sub = claims.get("sub")
    nombre = limpiar_texto(claims.get("name"), 120)
    correo_verificado = claims.get("email_verified") is True
    dominio_workspace = bool(claims.get("hd"))
    dominio_gmail = email.endswith(("@gmail.com", "@googlemail.com"))

    # Google advierte que la propiedad de correos externos puede cambiar.
    if not correo_verificado or not (dominio_gmail or dominio_workspace):
        return jsonify({"error": "Usa una cuenta Gmail o una cuenta verificada de Google Workspace"}), 403
    if not isinstance(google_sub, str) or not google_sub:
        return jsonify({"error": "Google no devolvió un identificador válido"}), 401
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        return jsonify({"error": "Google devolvió un correo no válido"}), 400
    if not nombre:
        nombre = email.split("@", 1)[0]

    try:
        with obtener_conexion() as conexion:
            conexion.execute(
                "SELECT set_config('app.login_email', %s, true)", (email,)
            )
            usuario = conexion.execute(
                "SELECT id, rol FROM usuarios WHERE google_sub = %s", (google_sub,)
            ).fetchone()

            if usuario is None:
                usuario_email = conexion.execute(
                    "SELECT id, rol, google_sub FROM usuarios WHERE email = %s", (email,)
                ).fetchone()
                if usuario_email is not None:
                    if usuario_email[2] not in (None, google_sub):
                        return jsonify({"error": "Este correo ya está vinculado a otra cuenta Google"}), 409
                    if usuario_email[2] is None:
                        conexion.execute(
                            "UPDATE usuarios SET google_sub = %s WHERE id = %s",
                            (google_sub, usuario_email[0])
                        )
                    usuario = usuario_email[:2]
                else:
                    # Hash de un secreto aleatorio: conserva el esquema actual
                    # sin crear una contraseña que la persona conozca o pueda usar.
                    password_no_utilizable = generate_password_hash(secrets.token_urlsafe(48))
                    usuario = conexion.execute(
                        """
                        INSERT INTO usuarios (email, password_hash, rol, nombre, google_sub)
                        VALUES (%s, %s, 'ciudadano', %s, %s)
                        RETURNING id, rol
                        """,
                        (email, password_no_utilizable, nombre, google_sub)
                    ).fetchone()
    except psycopg.errors.UniqueViolation:
        # Otra solicitud pudo crear la cuenta al mismo tiempo; el usuario puede
        # volver a intentar y se iniciará sesión en la cuenta ya creada.
        return jsonify({"error": "La cuenta se está creando; vuelve a intentar en unos segundos"}), 409

    return jsonify({"access_token": emitir_token(usuario[0], usuario[1])}), 200

def limpiar_texto(valor, limite):
    if not isinstance(valor, str):
        return None

    texto = unicodedata.normalize("NFC", valor)
    texto = "".join(caracter for caracter in texto if caracter.isprintable())
    texto = " ".join(texto.split())

    if not texto or len(texto) > limite:
        return None

    return texto


def _enviar_correo_ahora(destino, asunto, texto):
    """Envía un correo desde la cuenta de SIGRE. Devuelve True si salió.

    - Con MAIL_SCRIPT_URL (en Render): lo envía un Google Apps Script de la
      cuenta sigre.oficial por HTTPS. Render gratis bloquea el SMTP de Gmail.
    - Sin ella (en tu PC): SMTP de Gmail con MAIL_USERNAME y MAIL_APP_PASSWORD.
    """
    url_script = os.getenv("MAIL_SCRIPT_URL")
    try:
        if url_script:
            respuesta = requests.post(
                url_script,
                json={"clave": os.getenv("MAIL_SCRIPT_CLAVE", ""), "para": destino,
                      "asunto": asunto, "texto": texto},
                timeout=30,
            )
            resultado = respuesta.json()
            if not resultado.get("ok"):
                app.logger.error("El Apps Script no envió el correo: %s", resultado.get("error"))
                return False
            return True

        remitente = os.getenv("MAIL_USERNAME")
        clave_aplicacion = os.getenv("MAIL_APP_PASSWORD")
        if not remitente or not clave_aplicacion:
            app.logger.error("Falta configurar MAIL_SCRIPT_URL o MAIL_USERNAME y MAIL_APP_PASSWORD.")
            return False
        mensaje = EmailMessage()
        mensaje["Subject"] = asunto
        mensaje["From"] = f"SIGRE <{remitente}>"
        mensaje["To"] = destino
        mensaje.set_content(texto)
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=20) as servidor:
            servidor.starttls()
            servidor.login(remitente, clave_aplicacion)
            servidor.send_message(mensaje)
        return True
    except Exception:
        app.logger.exception("No se pudo enviar un correo.")
        return False


def enviar_correo(destino, asunto, texto):
    """Envía el correo en segundo plano: la respuesta a la página no espera a Gmail."""
    threading.Thread(target=_enviar_correo_ahora, args=(destino, asunto, texto), daemon=True).start()
    return True


def hash_codigo(email, codigo):
    # El hash incluye el correo: el mismo código en dos cuentas da hashes distintos.
    return hashlib.sha256(f"{email}:{codigo}".encode()).hexdigest()


def enviar_codigo_verificacion(email):
    """Crea un código de 6 números y lo envía al correo. No envía nada si la
    cuenta no existe, ya está verificada o se pidió un código hace menos de un minuto."""
    codigo = f"{secrets.randbelow(1_000_000):06d}"
    with obtener_conexion() as conexion:
        crear = conexion.execute(
            "SELECT sigre_crear_codigo_verificacion(%s, %s)",
            (email, hash_codigo(email, codigo))
        ).fetchone()[0]
    if not crear:
        return False
    return enviar_correo(
        email,
        "Tu código de verificación de SIGRE",
        "Hola,\n\n"
        f"Tu código para activar tu cuenta de SIGRE es:\n\n    {codigo}\n\n"
        "Vence en 10 minutos.\n\n"
        "Si no creaste una cuenta en SIGRE, ignora este correo."
    )


@app.post("/api/auth/registro")
def registrar_usuario():
    datos = request.get_json(silent=True)

    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    email = datos.get("email")
    password = datos.get("password")
    nombre = limpiar_texto(datos.get("nombre"), 120)
    telefono_texto = datos.get("telefono") or ""

    if not isinstance(email, str) or not isinstance(password, str):
        return jsonify({"error": "Faltan email o contraseña"}), 400

    if not nombre or len(nombre) < 2:
        return jsonify({"error": "Escribe tu nombre (mínimo 2 caracteres)"}), 400

    # Validar teléfono opcional
    telefono = limpiar_texto(telefono_texto, 20) if telefono_texto else None

    if telefono_texto and (
        not telefono
        or not re.fullmatch(r"\+?[0-9 ()-]{7,20}", telefono)
        or len(re.sub(r"\D", "", telefono)) < 7
    ):
        return jsonify({"error": "El teléfono no tiene un formato válido"}), 400

    # Validar correo
    email = email.strip().lower()

    if (
        len(email) > 254
        or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email)
    ):
        return jsonify({"error": "El email no tiene un formato válido"}), 400

    # Validar contraseña
    if len(password) < 12 or len(password) > 128:
        return jsonify({
            "error": "La contraseña debe tener entre 12 y 128 caracteres"
        }), 400

    password_hash = generate_password_hash(password)

    try:
        with obtener_conexion() as conexion:
            conexion.execute(
                """
                INSERT INTO usuarios (email, password_hash, rol, nombre, telefono)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (email, password_hash, "ciudadano", nombre, telefono)
            )
    except psycopg.errors.UniqueViolation:
        # Si la cuenta existe pero nunca se verificó, se reenvía el código para
        # que la persona termine el registro en lugar de quedarse bloqueada.
        try:
            with obtener_conexion() as conexion:
                pendiente = conexion.execute(
                    "SELECT sigre_cuenta_sin_verificar(%s)", (email,)
                ).fetchone()[0]
        except psycopg.errors.UndefinedFunction:
            # Falta volver a aplicar backend/migracion_verificacion_correo.sql.
            pendiente = False
        if pendiente:
            enviar_codigo_verificacion(email)
            return jsonify({
                "error": "Ya creaste esta cuenta, pero falta verificar el correo. "
                         "Escribe el código que enviamos (o pide uno nuevo).",
                "verificar": True,
            }), 409
        return jsonify({"error": "Ese email ya está registrado"}), 409

    enviar_codigo_verificacion(email)
    return jsonify({
        "mensaje": "Cuenta creada. Te enviamos un código de 6 números a tu correo.",
        "verificar": True,
    }), 201


@app.post("/api/auth/verificar")
def verificar_correo():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400
    email = datos.get("email")
    codigo = datos.get("codigo")
    if (not isinstance(email, str) or len(email) > 254
            or not isinstance(codigo, str) or not re.fullmatch(r"\d{6}", codigo)):
        return jsonify({"error": "Escribe los 6 números del código"}), 400
    email = email.strip().lower()

    with obtener_conexion() as conexion:
        resultado = conexion.execute(
            "SELECT sigre_verificar_correo(%s, %s)", (email, hash_codigo(email, codigo))
        ).fetchone()[0]

    respuestas = {
        "ok": ("¡Correo verificado! Ya puedes iniciar sesión.", 200),
        "ya_verificado": ("Tu correo ya estaba verificado. Ya puedes iniciar sesión.", 200),
        "invalido": ("El código no es correcto. Revísalo e inténtalo de nuevo.", 400),
        "expirado": ("El código venció. Pide uno nuevo con «Reenviar código».", 400),
        "bloqueado": ("Demasiados intentos. Pide un código nuevo con «Reenviar código».", 429),
    }
    texto, estado = respuestas.get(resultado, ("No se pudo verificar el código.", 400))
    return jsonify({"mensaje" if estado == 200 else "error": texto}), estado


@app.post("/api/auth/reenviar-codigo")
def reenviar_codigo():
    datos = request.get_json(silent=True)
    email = datos.get("email") if isinstance(datos, dict) else None
    if not isinstance(email, str) or len(email) > 254:
        return jsonify({"error": "Escribe un correo válido"}), 400
    enviar_codigo_verificacion(email.strip().lower())
    # Respuesta genérica: no revela si la cuenta existe.
    return jsonify({"mensaje": "Si la cuenta está pendiente de verificar, te enviamos un código nuevo."}), 200


@app.post("/api/auth/recuperar")
def solicitar_recuperacion():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    email = datos.get("email")
    if not isinstance(email, str):
        return jsonify({"error": "Escribe un correo válido"}), 400
    email = email.strip().lower()
    if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        return jsonify({"error": "Escribe un correo válido"}), 400

    # Respuesta genérica para no revelar si existe una cuenta.
    respuesta = {
        "mensaje": "Si el correo está registrado, recibirás instrucciones para recuperar tu contraseña."
    }

    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with obtener_conexion() as conexion:
        enviar = conexion.execute(
            "SELECT sigre_crear_recuperacion(%s, %s)", (email, token_hash)
        ).fetchone()[0]
    if not enviar:
        return jsonify(respuesta), 200

    frontend_url = os.getenv("FRONTEND_URL", "http://127.0.0.1:5500/frontend").rstrip("/")
    enlace = f"{frontend_url}/restablecer_contrasena.html?token={token}"
    enviar_correo(
        email,
        "Restablecer contraseña - SIGRE",
        "Hola,\n\n"
        "Recibimos una solicitud para restablecer tu contraseña de SIGRE.\n\n"
        f"Abre este enlace para crear una contraseña nueva:\n{enlace}\n\n"
        "El enlace vence en 15 minutos y solo puede utilizarse una vez.\n\n"
        "Si no solicitaste este cambio, ignora este correo."
    )

    return jsonify(respuesta), 200


@app.post("/api/auth/restablecer")
def restablecer_contrasena():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    token = datos.get("token")
    password = datos.get("password")
    if not isinstance(token, str) or not token or len(token) > 200:
        return jsonify({"error": "El enlace de recuperación no es válido"}), 400
    if not isinstance(password, str) or not 12 <= len(password) <= 128:
        return jsonify({"error": "La contraseña debe tener entre 12 y 128 caracteres"}), 400

    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with obtener_conexion() as conexion:
        cambiada = conexion.execute(
            "SELECT sigre_restablecer_contrasena(%s, %s)",
            (token_hash, generate_password_hash(password))
        ).fetchone()[0]

    if not cambiada:
        return jsonify({"error": "El enlace ha caducado o ya fue utilizado"}), 400
    return jsonify({"mensaje": "Contraseña actualizada correctamente. Ya puedes iniciar sesión."}), 200


@app.post("/api/auth/login")
def iniciar_sesion():
    datos = request.get_json(silent=True)

    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    email = datos.get("email")
    password = datos.get("password")

    if not isinstance(email, str) or not isinstance(password, str):
        return jsonify({"error": "Email o contraseña incorrectos"}), 401

    email = email.strip().lower()

    with obtener_conexion() as conexion:
        conexion.execute(
            "SELECT set_config('app.login_email', %s, true)",
            (email,)
        )
        usuario = conexion.execute(
            "SELECT id, password_hash, rol, email_verificado FROM usuarios WHERE email = %s",
            (email,)
        ).fetchone()

    if usuario is None or not check_password_hash(usuario[1], password):
        return jsonify({"error": "Email o contraseña incorrectos"}), 401

    if not usuario[3]:
        # Contraseña correcta pero correo sin verificar: se envía un código nuevo.
        enviar_codigo_verificacion(email)
        return jsonify({
            "error": "Tu correo aún no está verificado. Te enviamos un código de 6 números.",
            "verificar": True,
        }), 403

    token = create_access_token(
        identity=str(usuario[0]),
        additional_claims={"rol": usuario[2]}
    )

    return jsonify({"access_token": token}), 200

@app.get("/api/mi-cuenta")
@jwt_required()
def mi_cuenta():
    usuario_id = get_jwt_identity()
    rol = get_jwt().get("rol")

    if rol not in ("ciudadano", "voluntario", "autoridad"):
        return jsonify({"error": "Rol no válido"}), 403

    with obtener_conexion() as conexion:
        conexion.execute(
            "SELECT set_config('app.user_id', %s, true)",
            (usuario_id,)
        )
        conexion.execute(
            "SELECT set_config('app.user_role', %s, true)",
            (rol,)
        )
        usuario = conexion.execute(
            "SELECT id, email, rol, nombre, telefono FROM usuarios WHERE id = %s",
            (usuario_id,)
        ).fetchone()

    if usuario is None:
        return jsonify({"error": "Cuenta no encontrada"}), 404

    return jsonify({
        "id": usuario[0],
        "email": usuario[1],
        "rol": usuario[2],
        "nombre": usuario[3],
        "telefono": usuario[4]
    })

# ---------- Mi perfil: identificación, datos médicos y contacto de emergencia ----------
# Requiere backend/migracion_perfil_completo.sql. Los datos médicos son sensibles:
# se leen y guardan con funciones de la base que solo tocan la cuenta de la sesión.

CAMPOS_PERFIL = (
    "tipo_documento", "numero_documento", "fecha_nacimiento",
    "tipo_sangre", "alergias", "condiciones_medicas", "medicamentos",
    "contacto_emergencia_nombre", "contacto_emergencia_telefono",
    "direccion", "comunidad"
)
TIPOS_DOCUMENTO = ("CC", "TI", "CE", "PASAPORTE")
TIPOS_SANGRE = ("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-")


def texto_perfil(valor, minimo, maximo, multilinea=False):
    """Devuelve (ok, texto o None). Vacío cuenta como None (el campo es opcional)."""
    if valor is None or (isinstance(valor, str) and not valor.strip()):
        return True, None
    if not isinstance(valor, str):
        return False, None
    texto = unicodedata.normalize("NFC", valor)
    if multilinea:
        # Conserva los saltos de línea de los cuadros de texto largos.
        lineas = ["".join(c for c in linea if c.isprintable()).strip() for linea in texto.splitlines()]
        texto = "\n".join(lineas).strip()
    else:
        texto = " ".join("".join(c for c in texto if c.isprintable()).split())
    if not minimo <= len(texto) <= maximo:
        return False, None
    return True, texto


def respuesta_perfil(fila):
    perfil = dict(zip(CAMPOS_PERFIL, fila))
    if perfil["fecha_nacimiento"]:
        perfil["fecha_nacimiento"] = perfil["fecha_nacimiento"].isoformat()
    return perfil


@app.get("/api/mi-perfil")
@jwt_required()
def obtener_mi_perfil():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 401

    try:
        with obtener_conexion() as conexion:
            fijar_contexto_usuario(conexion, usuario_id, rol)
            perfil = conexion.execute(
                f"SELECT {', '.join(CAMPOS_PERFIL)} FROM sigre_mi_perfil()"
            ).fetchone()
    except psycopg.errors.UndefinedFunction:
        return jsonify({"error": "Falta preparar la base: aplica backend/migracion_perfil_completo.sql"}), 500

    if perfil is None:
        return jsonify({"error": "Cuenta no encontrada"}), 404
    respuesta = jsonify(respuesta_perfil(perfil))
    respuesta.headers["Cache-Control"] = "private, no-store"   # datos médicos: no guardar en caché
    return respuesta


@app.put("/api/mi-perfil")
@jwt_required()
def actualizar_mi_perfil():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 401

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos del perfil en formato JSON"}), 400

    tipo_documento = datos.get("tipo_documento") or None
    if tipo_documento is not None and tipo_documento not in TIPOS_DOCUMENTO:
        return jsonify({"error": "Tipo de documento no válido"}), 400

    ok, numero_documento = texto_perfil(datos.get("numero_documento"), 3, 40)
    if not ok or (numero_documento and not re.fullmatch(r"[A-Za-z0-9.\- ]{3,40}", numero_documento)):
        return jsonify({"error": "El número de documento debe tener entre 3 y 40 letras o números"}), 400
    if bool(tipo_documento) != bool(numero_documento):
        return jsonify({"error": "Escribe el tipo y el número de documento juntos, o deja ambos vacíos"}), 400
    if numero_documento:
        # "1.234.567" y "1234567" son el mismo documento.
        numero_documento = re.sub(r"[.\s]", "", numero_documento).upper()

    fecha_nacimiento = datos.get("fecha_nacimiento") or None
    if fecha_nacimiento is not None:
        try:
            fecha_nacimiento = date.fromisoformat(str(fecha_nacimiento))
        except ValueError:
            return jsonify({"error": "La fecha de nacimiento no es válida"}), 400
        if not date(1900, 1, 1) <= fecha_nacimiento <= date.today():
            return jsonify({"error": "La fecha de nacimiento debe estar entre 1900 y hoy"}), 400

    tipo_sangre = datos.get("tipo_sangre") or None
    if tipo_sangre is not None and tipo_sangre not in TIPOS_SANGRE:
        return jsonify({"error": "Tipo de sangre no válido"}), 400

    textos_largos = {}
    for campo, nombre in (("alergias", "Las alergias"),
                          ("condiciones_medicas", "Las condiciones médicas"),
                          ("medicamentos", "Los medicamentos")):
        ok, textos_largos[campo] = texto_perfil(datos.get(campo), 1, 3000, multilinea=True)
        if not ok:
            return jsonify({"error": f"{nombre} pueden tener máximo 3000 caracteres"}), 400

    ok, contacto_nombre = texto_perfil(datos.get("contacto_emergencia_nombre"), 2, 120)
    if not ok:
        return jsonify({"error": "El nombre del contacto de emergencia debe tener entre 2 y 120 caracteres"}), 400
    ok, contacto_telefono = texto_perfil(datos.get("contacto_emergencia_telefono"), 7, 30)
    if not ok or (contacto_telefono and (
        not re.fullmatch(r"\+?[0-9 ()-]{7,30}", contacto_telefono)
        or len(re.sub(r"\D", "", contacto_telefono)) < 7
    )):
        return jsonify({"error": "El teléfono del contacto de emergencia no es válido"}), 400
    if bool(contacto_nombre) != bool(contacto_telefono):
        return jsonify({"error": "Escribe el nombre y el teléfono del contacto de emergencia"}), 400

    ok, direccion = texto_perfil(datos.get("direccion"), 3, 300)
    if not ok:
        return jsonify({"error": "La dirección debe tener entre 3 y 300 caracteres"}), 400
    ok, comunidad = texto_perfil(datos.get("comunidad"), 2, 150)
    if not ok:
        return jsonify({"error": "El barrio o comunidad debe tener entre 2 y 150 caracteres"}), 400

    try:
        with obtener_conexion() as conexion:
            fijar_contexto_usuario(conexion, usuario_id, rol)
            guardado = conexion.execute(
                "SELECT sigre_guardar_mi_perfil(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (tipo_documento, numero_documento, fecha_nacimiento, tipo_sangre,
                 textos_largos["alergias"], textos_largos["condiciones_medicas"],
                 textos_largos["medicamentos"], contacto_nombre, contacto_telefono,
                 direccion, comunidad)
            ).fetchone()[0]
            perfil = conexion.execute(
                f"SELECT {', '.join(CAMPOS_PERFIL)} FROM sigre_mi_perfil()"
            ).fetchone()
    except psycopg.errors.UniqueViolation:
        return jsonify({"error": "Ese número de documento ya está registrado en otra cuenta"}), 409
    except psycopg.errors.UndefinedFunction:
        return jsonify({"error": "Falta preparar la base: aplica backend/migracion_perfil_completo.sql"}), 500

    if not guardado or perfil is None:
        return jsonify({"error": "Cuenta no encontrada"}), 404
    respuesta = jsonify({"mensaje": "Perfil actualizado correctamente", "perfil": respuesta_perfil(perfil)})
    respuesta.headers["Cache-Control"] = "private, no-store"
    return respuesta, 200


@app.get("/api/emergencias")
@jwt_required()
def listar_emergencias():
    usuario_id = get_jwt_identity()
    rol = get_jwt().get("rol")

    if rol not in ("ciudadano", "voluntario", "autoridad"):
        return jsonify({"error": "Rol no válido"}), 403

    with obtener_conexion() as conexion:
        conexion.execute(
            "SELECT set_config('app.user_id', %s, true)", (usuario_id,)
        )
        conexion.execute(
            "SELECT set_config('app.user_role', %s, true)",(rol,)
        )
        filas = conexion.execute("""
            SELECT id, tipo, descripcion, alcance,
                   departamento, municipio, sector,
                   latitud, longitud, nivel_riesgo, estado,
                   registrada_por, creada_en, actualizada_en,
                   finalizada_por, finalizada_en
            FROM emergencias
            ORDER BY actualizada_en DESC
        """).fetchall()

    columnas = (
        "id", "tipo", "descripcion", "alcance",
        "departamento", "municipio", "sector",
        "latitud", "longitud", "nivel_riesgo", "estado",
        "registrada_por", "creada_en", "actualizada_en",
        "finalizada_por", "finalizada_en"
    )

    return jsonify([dict(zip(columnas, fila)) for fila in filas])



# Módulo de reportes de personas y animales desaparecidos.
# API para el prototipo local; exige autorización explícita de publicación.
@app.after_request
def habilitar_cors_frontend_local(respuesta):
    origen = request.headers.get("Origin", "")
    partes = urlparse(origen)
    host_api = request.host.split(":")[0]

    # Acepta el frontend local si comparte el mismo host que la API.
    # Esto permite cambiar entre redes Wi-Fi sin actualizar una IP fija.
    if (
        partes.scheme == "http"
        and partes.hostname == host_api
        and partes.port in (5500, 8000)
    ):
        respuesta.headers["Access-Control-Allow-Origin"] = origen
        respuesta.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, OPTIONS"
        respuesta.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        respuesta.headers["Vary"] = "Origin"
    return respuesta


@app.route("/api/desaparecidos", methods=["OPTIONS"])
def opciones_desaparecidos():
    return "", 204


@app.get("/api/desaparecidos")
def listar_desaparecidos():
    tipo = request.args.get("tipo", "").strip().lower()
    estado = request.args.get("estado", "").strip().lower()
    busqueda = request.args.get("q", "").strip()

    if tipo and tipo not in ("persona", "animal"):
        return jsonify({"error": "Tipo de reporte no válido"}), 400
    if estado and estado not in ("activo", "encontrado"):
        return jsonify({"error": "Estado no válido"}), 400

    condiciones = []
    parametros = []
    if tipo:
        condiciones.append("tipo = %s")
        parametros.append(tipo)
    if estado:
        condiciones.append("estado = %s")
        parametros.append(estado)
    if busqueda:
        condiciones.append("(nombre ILIKE %s OR sector ILIKE %s)")
        parametros.extend((f"%{busqueda}%", f"%{busqueda}%"))

    where_sql = "WHERE " + " AND ".join(condiciones) if condiciones else ""
    consulta = f"""
        SELECT id, tipo, nombre, telefono_contacto, edad, genero, sector,
       (publicado_por IS NOT NULL) AS notificaciones_disponibles,
       fecha_visto, descripcion, estado, creado_en
        FROM reportes_desaparecidos
        {where_sql}
        ORDER BY creado_en DESC
    """

    with obtener_conexion() as conexion:
        filas = conexion.execute(consulta, parametros).fetchall()

    columnas = (
    "id", "tipo", "nombre", "telefono_contacto", "edad", "genero",
    "sector", "notificaciones_disponibles", "fecha_visto", "descripcion", "estado", "creado_en"
    )
    reportes = []
    for fila in filas:
        reporte = dict(zip(columnas, fila))
        for campo in ("fecha_visto", "creado_en"):
            if reporte[campo] is not None:
                reporte[campo] = reporte[campo].isoformat()
        reporte["foto_url"] = f"/api/desaparecidos/{reporte['id']}/foto"
        reportes.append(reporte)

    return jsonify(reportes)


@app.get("/api/desaparecidos/<int:reporte_id>/comentarios")
def listar_comentarios_desaparecido(reporte_id):
    with obtener_conexion() as conexion:
        existe = conexion.execute(
            "SELECT 1 FROM reportes_desaparecidos WHERE id = %s", (reporte_id,)
        ).fetchone()
        if existe is None:
            return jsonify({"error": "No se encontró el reporte"}), 404
        filas = conexion.execute(
            """
            SELECT id, nombre_testigo, comentario, creado_en
            FROM comentarios_desaparecidos
            WHERE reporte_id = %s
            ORDER BY creado_en DESC
            LIMIT 100
            """,
            (reporte_id,)
        ).fetchall()

    return jsonify([
        {
            "id": fila[0],
            "nombre_testigo": fila[1],
            "comentario": fila[2],
            "creado_en": fila[3].isoformat(),
        }
        for fila in filas
    ])


@app.post("/api/desaparecidos/<int:reporte_id>/comentarios")
@jwt_required()
def crear_comentario_desaparecido(reporte_id):
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Inicia sesión para dejar un comentario"}), 401

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos del comentario como JSON"}), 400

    comentario = limpiar_texto(datos.get("comentario"), 800)
    telefono = limpiar_texto(datos.get("telefono_testigo"), 20)
    confirma_veracidad = datos.get("veracidad_confirmada") is True
    autoriza_compartir_telefono = datos.get("autoriza_compartir_telefono") is True
    if not comentario or len(comentario) < 5:
        return jsonify({"error": "El comentario debe tener entre 5 y 800 caracteres"}), 400
    if not telefono or not re.fullmatch(r"\+?[0-9 ()-]{7,20}", telefono) or len(re.sub(r"\D", "", telefono)) < 7:
        return jsonify({"error": "Escribe un teléfono de contacto válido"}), 400
    if not confirma_veracidad:
        return jsonify({"error": "Confirma que tu comentario es verídico antes de enviarlo"}), 400
    if not autoriza_compartir_telefono:
        return jsonify({"error": "Autoriza compartir tu teléfono con quien publicó el reporte"}), 400

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        reporte = conexion.execute(
            "SELECT publicado_por FROM reportes_desaparecidos WHERE id = %s",
            (reporte_id,)
        ).fetchone()
        if reporte is None:
            return jsonify({"error": "No se encontró el reporte"}), 404

        cuenta = conexion.execute(
            "SELECT nombre, email FROM usuarios WHERE id = %s", (usuario_id,)
        ).fetchone()
        if cuenta is None:
            return jsonify({"error": "No se encontró tu cuenta"}), 404
        nombre_testigo = limpiar_texto(cuenta[0], 120) or cuenta[1].split("@", 1)[0]
        comentario_fila = conexion.execute(
            """
            INSERT INTO comentarios_desaparecidos
                (reporte_id, usuario_id, nombre_testigo, comentario,
                 veracidad_confirmada, autoriza_compartir_telefono)
            VALUES (%s, %s, %s, %s, TRUE, TRUE)
            RETURNING id
            """,
            (reporte_id, usuario_id, nombre_testigo, comentario)
        ).fetchone()
        comentario_id = comentario_fila[0]
        conexion.execute(
            """
            INSERT INTO contactos_comentarios_desaparecidos (comentario_id, telefono_testigo)
            VALUES (%s, %s)
            """,
            (comentario_id, telefono)
        )

        notificacion_creada = bool(reporte[0] and reporte[0] != usuario_id)
        if notificacion_creada:
            conexion.execute(
                """
                INSERT INTO notificaciones_comentarios_desaparecidos
                    (destinatario_id, comentario_id)
                VALUES (%s, %s)
                ON CONFLICT (comentario_id) DO NOTHING
                """,
                (reporte[0], comentario_id)
            )

    return jsonify({
        "mensaje": "Comentario enviado",
        "notificacion_creada": notificacion_creada,
        "detalle": "Se notificó a quien publicó el reporte." if notificacion_creada else
            "El comentario quedó guardado, pero este reporte antiguo no está vinculado a una cuenta SIGRE." if reporte[0] is None else
            "El comentario quedó guardado; no se envía una notificación a tu propia cuenta.",
    }), 201


@app.get("/api/notificaciones/comentarios/mias")
@jwt_required()
def listar_mis_notificaciones_comentarios():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 401

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        no_leidas = conexion.execute(
            """
            SELECT COUNT(*) FROM notificaciones_comentarios_desaparecidos
            WHERE destinatario_id = %s AND leida = FALSE
            """,
            (usuario_id,)
        ).fetchone()[0]
        filas = conexion.execute(
            """
            SELECT n.id, n.leida, n.creada_en, c.nombre_testigo, c.comentario,
                   cc.telefono_testigo, r.id, r.nombre, r.tipo
            FROM notificaciones_comentarios_desaparecidos n
            JOIN comentarios_desaparecidos c ON c.id = n.comentario_id
            JOIN contactos_comentarios_desaparecidos cc ON cc.comentario_id = c.id
            JOIN reportes_desaparecidos r ON r.id = c.reporte_id
            WHERE n.destinatario_id = %s
            ORDER BY n.creada_en DESC
            LIMIT 30
            """,
            (usuario_id,)
        ).fetchall()

    notificaciones = [
        {
            "id": fila[0], "leida": fila[1], "creada_en": fila[2].isoformat(),
            "nombre_testigo": fila[3], "comentario": fila[4],
            "telefono_testigo": fila[5], "reporte_id": fila[6],
            "reporte_nombre": fila[7], "reporte_tipo": fila[8],
        }
        for fila in filas
    ]
    return jsonify({"no_leidas": no_leidas, "notificaciones": notificaciones})


@app.post("/api/notificaciones/comentarios/<int:notificacion_id>/leida")
@jwt_required()
def marcar_notificacion_comentario_leida(notificacion_id):
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 401
    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        fila = conexion.execute(
            """
            UPDATE notificaciones_comentarios_desaparecidos
            SET leida = TRUE
            WHERE id = %s AND destinatario_id = %s
            RETURNING id
            """,
            (notificacion_id, usuario_id)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "No se encontró esa notificación"}), 404
    return jsonify({"mensaje": "Notificación marcada como leída"})


@app.get("/api/desaparecidos/<int:reporte_id>/foto")
def foto_desaparecido(reporte_id):
    with obtener_conexion() as conexion:
        fila = conexion.execute(
            """
            SELECT foto, foto_mime
            FROM reportes_desaparecidos
            WHERE id = %s
            """,
            (reporte_id,)
        ).fetchone()

    if fila is None:
        return jsonify({"error": "Foto no encontrada"}), 404

    respuesta = send_file(
        io.BytesIO(bytes(fila[0])),
        mimetype=fila[1],
        download_name=f"reporte-{reporte_id}"
    )
    respuesta.headers["Cache-Control"] = "public, max-age=300"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta


@app.get("/api/desaparecidos/<int:reporte_id>/cartel")
def descargar_cartel_desaparecido(reporte_id):
    with obtener_conexion() as conexion:
        fila = conexion.execute(
            """
            SELECT tipo, nombre, telefono_contacto, edad, genero, sector,
                   fecha_visto, descripcion, estado, foto, foto_mime
            FROM reportes_desaparecidos
            WHERE id = %s
            """,
            (reporte_id,)
        ).fetchone()

    if fila is None:
        return jsonify({"error": "No se encontró el reporte"}), 404

    (tipo, nombre, telefono, edad, genero, sector, fecha_visto,
     descripcion, estado, foto, foto_mime) = fila
    nombre = nombre or "Sin nombre"
    telefono = telefono or "No especificado"
    edad = edad or "No especificada"
    genero = genero or "No especificado"
    sector = sector or "No especificado"
    descripcion = descripcion or "Sin descripción"
    estado = estado or "activo"
    imagen_pdf = io.BytesIO()
    with Image.open(io.BytesIO(bytes(foto))) as imagen_original:
        imagen = ImageOps.exif_transpose(imagen_original)
        if imagen.mode in ("RGBA", "LA") or "transparency" in imagen.info:
            imagen_rgba = imagen.convert("RGBA")
            fondo = Image.new("RGBA", imagen_rgba.size, (246, 232, 198, 255))
            fondo.alpha_composite(imagen_rgba)
            imagen = fondo.convert("RGB")
        else:
            imagen = imagen.convert("RGB")
        imagen.save(imagen_pdf, format="JPEG", quality=92)
    imagen_pdf.seek(0)

    buffer_pdf = io.BytesIO()
    ancho, alto = A4
    pdf = canvas.Canvas(buffer_pdf, pagesize=A4, pageCompression=1)
    pdf.setTitle(f"Cartel SIGRE - {nombre}")
    pdf.setAuthor("SIGRE")

    # Fondo de papel envejecido con doble borde.
    pdf.setFillColorRGB(0.74, 0.63, 0.45)
    pdf.rect(0, 0, ancho, alto, fill=1, stroke=0)
    pdf.setFillColorRGB(0.95, 0.88, 0.72)
    pdf.rect(20, 20, ancho - 40, alto - 40, fill=1, stroke=0)
    pdf.setStrokeColorRGB(0.39, 0.28, 0.17)
    pdf.setLineWidth(2.2)
    pdf.rect(28, 28, ancho - 56, alto - 56, fill=0, stroke=1)
    pdf.setStrokeColorRGB(0.61, 0.47, 0.30)
    pdf.setLineWidth(0.8)
    pdf.setDash(2, 4)
    pdf.rect(36, 36, ancho - 72, alto - 72, fill=0, stroke=1)
    pdf.setDash()

    activo = estado == "activo"
    color_estado = (0.48, 0.19, 0.14) if activo else (0.40, 0.30, 0.51)
    titulo = "SE BUSCA" if activo else "REPORTE ENCONTRADO"
    pdf.setFillColorRGB(0.29, 0.18, 0.12)
    pdf.setFont("Times-Bold", 39 if activo else 25)
    pdf.drawCentredString(ancho / 2, alto - 79, titulo)
    pdf.setStrokeColorRGB(*color_estado)
    pdf.setLineWidth(2)
    pdf.line(105, alto - 91, ancho - 105, alto - 91)
    pdf.setFillColorRGB(0.40, 0.30, 0.20)
    pdf.setFont("Times-Roman", 8.5)
    pdf.drawCentredString(ancho / 2, alto - 108, f"AYÚDANOS A COMPARTIR INFORMACIÓN VERIFICADA · {tipo.upper()}")

    # La foto se ajusta dentro del marco manteniendo su proporción.
    marco_x, marco_y, marco_ancho, marco_alto = 151, alto - 390, 293, 245
    pdf.setFillColorRGB(0.84, 0.76, 0.59)
    pdf.rect(marco_x - 5, marco_y - 5, marco_ancho + 10, marco_alto + 10, fill=1, stroke=0)
    pdf.setStrokeColorRGB(0.39, 0.28, 0.17)
    pdf.setLineWidth(3)
    pdf.rect(marco_x - 5, marco_y - 5, marco_ancho + 10, marco_alto + 10, fill=0, stroke=1)
    pdf.drawImage(
        ImageReader(imagen_pdf), marco_x, marco_y,
        width=marco_ancho, height=marco_alto,
        preserveAspectRatio=True, anchor="c", mask="auto"
    )

    pdf.setFillColorRGB(0.29, 0.18, 0.12)
    nombre_lineas = simpleSplit(nombre, "Times-Bold", 19, ancho - 80)
    y_nombre = marco_y - 29
    for linea in nombre_lineas[:2]:
        pdf.setFont("Times-Bold", 19)
        pdf.drawCentredString(ancho / 2, y_nombre, linea)
        y_nombre -= 22

    margen = 48
    ancho_columna = (ancho - 2 * margen - 22) / 2
    x_izquierda = margen
    x_derecha = margen + ancho_columna + 22
    ancho_tarjetas = ancho - 2 * margen

    def dibujar_fila_campos(y_superior, campos, alto_fila):
        pdf.setFillColorRGB(0.97, 0.92, 0.81)
        pdf.setStrokeColorRGB(0.77, 0.66, 0.47)
        pdf.setLineWidth(0.7)
        for x, etiqueta, valor in campos:
            # Restablece el fondo en cada tarjeta; el campo anterior cambia el color de texto.
            pdf.setFillColorRGB(0.97, 0.92, 0.81)
            pdf.roundRect(x, y_superior - alto_fila, ancho_columna, alto_fila, 6, fill=1, stroke=1)
            pdf.setFillColorRGB(0.40, 0.29, 0.18)
            pdf.setFont("Times-Bold", 10.5)
            pdf.drawString(x + 10, y_superior - 14, etiqueta.upper())
            lineas = simpleSplit(str(valor), "Times-Roman", 14.5, ancho_columna - 20)
            pdf.setFillColorRGB(0.18, 0.14, 0.10)
            pdf.setFont("Times-Roman", 14.5)
            for indice, linea in enumerate(lineas):
                pdf.drawString(x + 10, y_superior - 33 - indice * 17, linea)

    y_datos = y_nombre - 5
    valor_fecha = fecha_visto.strftime("%d/%m/%Y %I:%M %p") if fecha_visto else "No especificada"
    sector_lineas = simpleSplit(str(sector), "Times-Roman", 14.5, ancho_columna - 20)
    fila_1_alto = max(56, 39 + len(sector_lineas) * 17)
    dibujar_fila_campos(y_datos, [
        (x_izquierda, "Edad", edad),
        (x_derecha, "Última vez visto", sector),
    ], fila_1_alto)

    fila_2_superior = y_datos - fila_1_alto - 8
    fecha_lineas = simpleSplit(valor_fecha, "Times-Roman", 14.5, ancho_columna - 20)
    fila_2_alto = max(56, 39 + len(fecha_lineas) * 17)
    dibujar_fila_campos(fila_2_superior, [
        (x_izquierda, "Género", genero),
        (x_derecha, "Fecha y hora", valor_fecha),
    ], fila_2_alto)

    # Teléfono y descripción comparten una tarjeta amplia para aprovechar la hoja.
    descripcion_superior = fila_2_superior - fila_2_alto - 10
    descripcion_inferior = 94
    descripcion_alto = descripcion_superior - descripcion_inferior
    pdf.setFillColorRGB(0.94, 0.86, 0.69)
    pdf.setStrokeColorRGB(0.68, 0.50, 0.30)
    pdf.roundRect(margen, descripcion_inferior, ancho_tarjetas, descripcion_alto, 8, fill=1, stroke=1)
    pdf.setFillColorRGB(0.40, 0.29, 0.18)
    pdf.setFont("Times-Bold", 12)
    pdf.drawString(margen + 12, descripcion_superior - 18, "TELÉFONO DE CONTACTO")
    pdf.setFillColorRGB(0.18, 0.14, 0.10)
    pdf.setFont("Times-Roman", 15)
    pdf.drawString(margen + 12, descripcion_superior - 37, telefono)
    pdf.setFillColorRGB(0.40, 0.29, 0.18)
    pdf.setFont("Times-Bold", 12.5)
    pdf.drawString(margen + 12, descripcion_superior - 58, "DESCRIPCIÓN Y SEÑAS PARTICULARES")

    ancho_descripcion = ancho_tarjetas - 24
    inicio_descripcion = descripcion_superior - 78
    espacio_disponible = max(30, inicio_descripcion - (descripcion_inferior + 12))
    tamano_descripcion = 14.5
    lineas_descripcion = simpleSplit(descripcion, "Times-Roman", tamano_descripcion, ancho_descripcion)
    espacio_linea = 17
    while len(lineas_descripcion) * espacio_linea > espacio_disponible and tamano_descripcion > 8:
        tamano_descripcion -= 0.5
        lineas_descripcion = simpleSplit(descripcion, "Times-Roman", tamano_descripcion, ancho_descripcion)
        espacio_linea = tamano_descripcion + 2
    if len(lineas_descripcion) * espacio_linea > espacio_disponible:
        espacio_linea = espacio_disponible / max(len(lineas_descripcion), 1)
        tamano_descripcion = max(5.5, espacio_linea - 1.5)
        lineas_descripcion = simpleSplit(descripcion, "Times-Roman", tamano_descripcion, ancho_descripcion)
        espacio_linea = max(tamano_descripcion + 1, min(espacio_linea, tamano_descripcion + 2))
    pdf.setFillColorRGB(0.18, 0.14, 0.10)
    pdf.setFont("Times-Roman", tamano_descripcion)
    for indice, linea in enumerate(lineas_descripcion):
        y_linea = inicio_descripcion - indice * espacio_linea
        if y_linea < descripcion_inferior + 10:
            break
        pdf.drawString(margen + 12, y_linea, linea)

    pdf.setFillColorRGB(*color_estado)
    pdf.roundRect(margen, 54, ancho_tarjetas, 30, 8, fill=1, stroke=0)
    pdf.setFillColorRGB(1, 0.96, 0.88)
    pdf.setFont("Times-Bold", 14)
    pdf.drawCentredString(ancho / 2, 63, f"ESTADO: {'ACTIVO' if activo else 'ENCONTRADO'}")
    pdf.setFillColorRGB(0.40, 0.30, 0.20)
    pdf.setFont("Times-Bold", 8.5)
    pdf.drawCentredString(ancho / 2, 39, "SIGRE · REPORTE COMUNITARIO · VERIFICA LA INFORMACIÓN ANTES DE COMPARTIR")
    pdf.showPage()
    pdf.save()
    buffer_pdf.seek(0)

    respuesta = send_file(
        buffer_pdf,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=f"cartel-sigre-{reporte_id}.pdf",
    )
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    respuesta.headers["Cache-Control"] = "no-store"
    return respuesta


@app.post("/api/desaparecidos")
@jwt_required()
def crear_reporte_desaparecido():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Inicia sesión para publicar un reporte y recibir comentarios"}), 401

    tipo = limpiar_texto(request.form.get("tipo"), 10)
    nombre = limpiar_texto(request.form.get("nombre"), 120)
    telefono_contacto = limpiar_texto(
    request.form.get("telefono_contacto"), 20)
    edad = limpiar_texto(request.form.get("edad", ""), 40)
    genero = limpiar_texto(request.form.get("genero", ""), 40)
    sector = limpiar_texto(request.form.get("sector"), 160)
    descripcion = limpiar_texto(request.form.get("descripcion"), 1200)
    fecha_visto_texto = limpiar_texto(request.form.get("fecha_visto", ""), 40)
    foto = request.files.get("foto")
    autorizada = request.form.get("autoriza_publicacion") == "true"

    if tipo not in ("persona", "animal"):
        return jsonify({"error": "Selecciona persona o animal"}), 400
    if not nombre or not telefono_contacto or not sector or not descripcion:
        return jsonify({
            "error": "Completa nombre, teléfono de contacto, sector y descripción"}), 400
    if not autorizada:
        return jsonify({"error": "Se requiere autorización para publicar la foto y los datos"}), 400
    if foto is None or not foto.filename:
        return jsonify({"error": "Selecciona una fotografía"}), 400

    contenido_foto = foto.read(5 * 1024 * 1024 + 1)
    if not contenido_foto or len(contenido_foto) > 5 * 1024 * 1024:
        return jsonify({"error": "La imagen debe pesar máximo 5 MB"}), 400

    firma = contenido_foto[:12]
    if firma.startswith(b"\xff\xd8\xff"):
        mime = "image/jpeg"
    elif firma.startswith(b"\x89PNG\r\n\x1a\n"):
        mime = "image/png"
    elif firma[:4] == b"RIFF" and firma[8:12] == b"WEBP":
        mime = "image/webp"
    else:
        return jsonify({"error": "Usa una imagen JPG, PNG o WEBP"}), 400

    fecha_visto = None
    if fecha_visto_texto:
        try:
            fecha_visto = datetime.fromisoformat(
                fecha_visto_texto.replace("Z", "+00:00")
            )
        except ValueError:
            return jsonify({"error": "La fecha indicada no es válida"}), 400

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        fila = conexion.execute(
            """
            INSERT INTO reportes_desaparecidos
                (tipo, nombre, telefono_contacto, edad, genero, sector, fecha_visto,
                descripcion, foto, foto_mime, autoriza_publicacion, publicado_por)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, TRUE, %s)
            RETURNING id, creado_en
            """,
            (
                tipo, nombre, telefono_contacto, edad, genero, sector, fecha_visto,
                descripcion, psycopg.Binary(contenido_foto), mime, usuario_id
            )
        ).fetchone()

    return jsonify({
        "mensaje": "Reporte publicado",
        "id": fila[0],
        "creado_en": fila[1].isoformat()
    }), 201


# Módulo "Solicitar ayuda".
# Cada solicitud queda asociada a la cuenta del token JWT, nunca a un id
# enviado desde el navegador. Requiere backend/migracion_solicitudes_ayuda.sql.
CATEGORIAS_AYUDA = (
    "alimentos", "atencion_medica", "alojamiento", "transporte", "ropa", "otra"
)
URGENCIAS_AYUDA = ("baja", "media", "alta", "critica")
TIPOS_SOLICITUD = ("ayuda", "visita")
ALCANCES_AYUDA = ("comunidad", "familias", "hogar")
MOTIVOS_VISITA = (
    "evaluar_danos", "condiciones_vivienda", "riesgo_estructural",
    "encuesta_social", "otra"
)
FRANJAS_VISITA = ("manana", "tarde", "cualquiera")
DIAS_MAXIMOS_VISITA = 60
LIMITE_ADJUNTO = 5 * 1024 * 1024


def fijar_contexto_usuario(conexion, usuario_id, rol):
    conexion.execute(
        "SELECT set_config('app.user_id', %s, true)", (str(usuario_id),)
    )
    conexion.execute(
        "SELECT set_config('app.user_role', %s, true)", (rol,)
    )


def usuario_autenticado():
    rol = get_jwt().get("rol")
    try:
        usuario_id = int(get_jwt_identity())
    except (TypeError, ValueError):
        return None, None
    if rol not in ("ciudadano", "voluntario", "autoridad"):
        return None, None
    return usuario_id, rol


def detectar_mime_adjunto(contenido):
    firma = contenido[:12]
    if firma.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if firma.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if firma[:4] == b"RIFF" and firma[8:12] == b"WEBP":
        return "image/webp"
    if firma.startswith(b"%PDF-"):
        return "application/pdf"
    return None


@app.post("/api/solicitudes-ayuda")
@jwt_required()
def crear_solicitud_ayuda():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    tipo = limpiar_texto(request.form.get("tipo", "ayuda"), 10)
    alcance = limpiar_texto(request.form.get("alcance"), 10)
    nombre_comunidad = limpiar_texto(request.form.get("nombre_comunidad", ""), 120)
    categoria = limpiar_texto(request.form.get("categoria", ""), 20)
    motivo_visita = limpiar_texto(request.form.get("motivo_visita", ""), 30)
    fecha_visita_texto = limpiar_texto(request.form.get("fecha_visita_preferida", ""), 10)
    franja_horaria = limpiar_texto(request.form.get("franja_horaria", ""), 10)
    urgencia = limpiar_texto(request.form.get("urgencia"), 10)
    descripcion = limpiar_texto(request.form.get("descripcion"), 1200)
    personas_texto = limpiar_texto(request.form.get("personas_afectadas"), 6)
    direccion = limpiar_texto(request.form.get("direccion"), 200)
    nombre_contacto = limpiar_texto(request.form.get("nombre_contacto"), 120)
    telefono_contacto = limpiar_texto(request.form.get("telefono_contacto"), 20)
    latitud_texto = limpiar_texto(request.form.get("latitud", ""), 20)
    longitud_texto = limpiar_texto(request.form.get("longitud", ""), 20)
    autorizada = request.form.get("autoriza_compartir") == "true"
    adjunto = request.files.get("adjunto")

    if tipo not in TIPOS_SOLICITUD:
        return jsonify({"error": "Tipo de solicitud no válido"}), 400
    if alcance not in ALCANCES_AYUDA:
        return jsonify({"error": "Indica a quiénes beneficia la solicitud"}), 400
    if alcance == "hogar":
        nombre_comunidad = None
    elif not nombre_comunidad or len(nombre_comunidad) < 3:
        return jsonify({
            "error": "Escribe el nombre del barrio, comunidad u organización beneficiada"
        }), 400

    fecha_visita = None
    if tipo == "ayuda":
        motivo_visita = franja_horaria = None
        if categoria not in CATEGORIAS_AYUDA:
            return jsonify({"error": "Selecciona una categoría de ayuda válida"}), 400
    else:
        categoria = None
        if motivo_visita not in MOTIVOS_VISITA:
            return jsonify({"error": "Selecciona el motivo de la visita"}), 400
        if franja_horaria not in FRANJAS_VISITA:
            return jsonify({"error": "Selecciona la franja horaria para la visita"}), 400
        try:
            fecha_visita = date.fromisoformat(fecha_visita_texto or "")
        except ValueError:
            return jsonify({"error": "Selecciona una fecha válida para la visita"}), 400
        hoy = date.today()
        if not hoy + timedelta(days=1) <= fecha_visita <= hoy + timedelta(days=DIAS_MAXIMOS_VISITA):
            return jsonify({
                "error": f"La fecha de la visita debe estar entre mañana y los próximos {DIAS_MAXIMOS_VISITA} días"
            }), 400

    if urgencia not in URGENCIAS_AYUDA:
        return jsonify({"error": "Selecciona un nivel de urgencia válido"}), 400
    if not descripcion or len(descripcion) < 10:
        return jsonify({"error": "Describe lo que necesitas (mínimo 10 caracteres)"}), 400
    if not personas_texto or not personas_texto.isdigit() or not 1 <= int(personas_texto) <= 10000:
        return jsonify({"error": "Indica cuántas personas están afectadas (entre 1 y 10000)"}), 400
    personas_afectadas = int(personas_texto)
    if not direccion or len(direccion) < 5:
        return jsonify({"error": "Escribe la dirección o el sector (mínimo 5 caracteres)"}), 400
    if not nombre_contacto or len(nombre_contacto) < 2:
        return jsonify({"error": "Escribe el nombre de contacto"}), 400
    if (
        not telefono_contacto
        or not re.fullmatch(r"\+?[0-9 ()-]{7,20}", telefono_contacto)
        or len(re.sub(r"\D", "", telefono_contacto)) < 7
    ):
        return jsonify({"error": "Escribe un teléfono de contacto válido"}), 400
    if not autorizada:
        return jsonify({
            "error": "Debes autorizar que la información se comparta con el equipo responsable"
        }), 400

    latitud = longitud = None
    if latitud_texto or longitud_texto:
        try:
            latitud = float(latitud_texto)
            longitud = float(longitud_texto)
        except (TypeError, ValueError):
            return jsonify({"error": "La ubicación seleccionada no es válida"}), 400
        if not (-90 <= latitud <= 90 and -180 <= longitud <= 180):
            return jsonify({"error": "La ubicación seleccionada no es válida"}), 400

    contenido_adjunto = None
    mime_adjunto = None
    if adjunto is not None and adjunto.filename:
        # El nombre original del archivo se descarta; solo se guardan los bytes.
        contenido_adjunto = adjunto.read(LIMITE_ADJUNTO + 1)
        if not contenido_adjunto or len(contenido_adjunto) > LIMITE_ADJUNTO:
            return jsonify({"error": "El archivo debe pesar máximo 5 MB"}), 400
        mime_adjunto = detectar_mime_adjunto(contenido_adjunto)
        if mime_adjunto is None:
            return jsonify({"error": "Adjunta una imagen JPG, PNG o WEBP, o un documento PDF"}), 400

    try:
        with obtener_conexion() as conexion:
            fijar_contexto_usuario(conexion, usuario_id, rol)
            fila = conexion.execute(
                """
                INSERT INTO solicitudes_ayuda
                    (usuario_id, tipo, alcance, nombre_comunidad, categoria,
                     motivo_visita, fecha_visita_preferida, franja_horaria,
                     urgencia, descripcion, personas_afectadas,
                     direccion, latitud, longitud, nombre_contacto, telefono_contacto,
                     adjunto, adjunto_mime, autoriza_compartir)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, TRUE)
                RETURNING id, estado, creada_en
                """,
                (
                    usuario_id, tipo, alcance, nombre_comunidad, categoria,
                    motivo_visita, fecha_visita, franja_horaria,
                    urgencia, descripcion, personas_afectadas,
                    direccion, latitud, longitud, nombre_contacto, telefono_contacto,
                    psycopg.Binary(contenido_adjunto) if contenido_adjunto else None,
                    mime_adjunto
                )
            ).fetchone()
    except psycopg.errors.ForeignKeyViolation:
        return jsonify({"error": "Tu cuenta ya no existe. Inicia sesión de nuevo."}), 401

    return jsonify({
        "mensaje": "Visita solicitada" if tipo == "visita" else "Solicitud enviada",
        "id": fila[0],
        "tipo": tipo,
        "estado": fila[1],
        "creada_en": fila[2].isoformat()
    }), 201


@app.get("/api/solicitudes-ayuda/mias")
@jwt_required()
def listar_mis_solicitudes_ayuda():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        filas = conexion.execute(
            """
            SELECT id, tipo, alcance, nombre_comunidad, categoria,
                   motivo_visita, fecha_visita_preferida, franja_horaria,
                   urgencia, descripcion, personas_afectadas,
                   direccion, latitud, longitud, nombre_contacto, telefono_contacto,
                   adjunto_mime, estado, creada_en, actualizada_en
            FROM solicitudes_ayuda
            WHERE usuario_id = %s
            ORDER BY creada_en DESC
            LIMIT 100
            """,
            (usuario_id,)
        ).fetchall()

    columnas = (
        "id", "tipo", "alcance", "nombre_comunidad", "categoria",
        "motivo_visita", "fecha_visita_preferida", "franja_horaria",
        "urgencia", "descripcion", "personas_afectadas",
        "direccion", "latitud", "longitud", "nombre_contacto", "telefono_contacto",
        "adjunto_mime", "estado", "creada_en", "actualizada_en"
    )
    solicitudes = []
    for fila in filas:
        solicitud = dict(zip(columnas, fila))
        for campo in ("creada_en", "actualizada_en", "fecha_visita_preferida"):
            if solicitud[campo] is not None:
                solicitud[campo] = solicitud[campo].isoformat()
        solicitud["tiene_adjunto"] = solicitud["adjunto_mime"] is not None
        solicitudes.append(solicitud)

    return jsonify(solicitudes)


@app.get("/api/solicitudes-ayuda/<int:solicitud_id>/adjunto")
@jwt_required()
def adjunto_solicitud_ayuda(solicitud_id):
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        fila = conexion.execute(
            """
            SELECT adjunto, adjunto_mime
            FROM solicitudes_ayuda
            WHERE id = %s AND usuario_id = %s AND adjunto IS NOT NULL
            """,
            (solicitud_id, usuario_id)
        ).fetchone()

    if fila is None:
        return jsonify({"error": "Adjunto no encontrado"}), 404

    extension = {
        "image/jpeg": "jpg", "image/png": "png",
        "image/webp": "webp", "application/pdf": "pdf"
    }[fila[1]]
    respuesta = send_file(
        io.BytesIO(bytes(fila[0])),
        mimetype=fila[1],
        as_attachment=True,
        download_name=f"solicitud-{solicitud_id}.{extension}"
    )
    respuesta.headers["Cache-Control"] = "private, no-store"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta


# Avatar de la cuenta: un animalito de la galería o una foto propia.
# Requiere backend/migracion_avatares.sql.
ANIMALES_AVATAR = (
    "perro", "gato", "zorro", "panda", "koala", "leon",
    "rana", "mono", "conejo", "tigre", "oso", "buho"
)
LIMITE_FOTO_AVATAR = 2 * 1024 * 1024


@app.get("/api/mi-cuenta/avatar")
@jwt_required()
def obtener_avatar():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        fila = conexion.execute(
            """
            SELECT tipo, animal, actualizado_en
            FROM avatares_usuario
            WHERE usuario_id = %s
            """,
            (usuario_id,)
        ).fetchone()

    if fila is None:
        return jsonify({"tipo": None})

    return jsonify({
        "tipo": fila[0],
        "animal": fila[1],
        "actualizado_en": fila[2].isoformat()
    })


@app.get("/api/mi-cuenta/avatar/foto")
@jwt_required()
def foto_avatar():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    with obtener_conexion() as conexion:
        fijar_contexto_usuario(conexion, usuario_id, rol)
        fila = conexion.execute(
            """
            SELECT foto, foto_mime
            FROM avatares_usuario
            WHERE usuario_id = %s AND tipo = 'foto'
            """,
            (usuario_id,)
        ).fetchone()

    if fila is None:
        return jsonify({"error": "Foto no encontrada"}), 404

    respuesta = send_file(
        io.BytesIO(bytes(fila[0])),
        mimetype=fila[1],
        download_name="avatar"
    )
    respuesta.headers["Cache-Control"] = "private, no-store"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta


@app.post("/api/mi-cuenta/avatar")
@jwt_required()
def guardar_avatar():
    usuario_id, rol = usuario_autenticado()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    tipo = limpiar_texto(request.form.get("tipo"), 10)
    animal = None
    contenido_foto = None
    mime = None

    if tipo == "animal":
        animal = limpiar_texto(request.form.get("animal"), 10)
        if animal not in ANIMALES_AVATAR:
            return jsonify({"error": "Elige un animalito de la galería"}), 400
    elif tipo == "foto":
        foto = request.files.get("foto")
        if foto is None or not foto.filename:
            return jsonify({"error": "Selecciona una foto"}), 400
        # El nombre original se descarta; solo se guardan los bytes validados.
        contenido_foto = foto.read(LIMITE_FOTO_AVATAR + 1)
        if not contenido_foto or len(contenido_foto) > LIMITE_FOTO_AVATAR:
            return jsonify({"error": "La foto debe pesar máximo 2 MB"}), 400
        mime = detectar_mime_adjunto(contenido_foto)
        if mime not in ("image/jpeg", "image/png", "image/webp"):
            return jsonify({"error": "Usa una foto JPG, PNG o WEBP"}), 400
    elif tipo != "ninguno":
        return jsonify({"error": "Tipo de avatar no válido"}), 400

    try:
        with obtener_conexion() as conexion:
            fijar_contexto_usuario(conexion, usuario_id, rol)
            if tipo == "ninguno":
                conexion.execute(
                    "DELETE FROM avatares_usuario WHERE usuario_id = %s",
                    (usuario_id,)
                )
            else:
                conexion.execute(
                    """
                    INSERT INTO avatares_usuario
                        (usuario_id, tipo, animal, foto, foto_mime)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (usuario_id) DO UPDATE
                    SET tipo = EXCLUDED.tipo,
                        animal = EXCLUDED.animal,
                        foto = EXCLUDED.foto,
                        foto_mime = EXCLUDED.foto_mime,
                        actualizado_en = NOW()
                    """,
                    (
                        usuario_id, tipo, animal,
                        psycopg.Binary(contenido_foto) if contenido_foto else None,
                        mime
                    )
                )
    except psycopg.errors.ForeignKeyViolation:
        return jsonify({"error": "Tu cuenta ya no existe. Inicia sesión de nuevo."}), 401

    return jsonify({
        "mensaje": "Avatar eliminado" if tipo == "ninguno" else "Avatar guardado",
        "tipo": None if tipo == "ninguno" else tipo,
        "animal": animal
    })


# Estadísticas del dashboard: solo totales, sin datos personales.
# Requiere backend/migracion_estadisticas.sql.
@app.get("/api/estadisticas/usuarios")
def estadisticas_usuarios():
    with obtener_conexion() as conexion:
        total = conexion.execute(
            "SELECT contar_usuarios_registrados()"
        ).fetchone()[0]

    respuesta = jsonify({"usuarios_registrados": total})
    respuesta.headers["Cache-Control"] = "public, max-age=60"
    return respuesta


@app.get("/salud")
def inicio():
    return "SIGRE funcionando"


@app.get("/api/salud")
def estado_salud():
    with obtener_conexion() as conexion:
        conexion.execute("SELECT 1")

    return jsonify({
        "estado": "ok",
        "base_datos": "conectada"
    })


# ---------- Páginas del frontend ----------
# Publicado en internet, Flask entrega también las páginas (frontend/) desde la
# misma dirección que la API. En tu PC puedes seguir usando Live Server.
CARPETA_FRONTEND = Path(__file__).resolve().parent.parent / "frontend"


@app.get("/")
def pagina_inicio():
    return send_from_directory(CARPETA_FRONTEND, "index.html")


@app.get("/<path:ruta>")
def archivo_frontend(ruta):
    # Las rutas de la API que no existen responden JSON, no una página.
    if ruta.startswith("api/"):
        return jsonify({"error": "Ruta no encontrada"}), 404
    # send_from_directory no deja salir de la carpeta frontend (../ no funciona).
    respuesta = send_from_directory(CARPETA_FRONTEND, ruta)
    if ruta == "service-worker.js":
        # El navegador debe revisar siempre si hay una versión nueva.
        respuesta.headers["Cache-Control"] = "no-cache"
    return respuesta


if __name__ == "__main__":
    # Solo para tu PC. En Render se usa gunicorn y este bloque no se ejecuta.
    app.run(host="0.0.0.0", port=5000, debug=os.getenv("FLASK_DEBUG", "1") == "1")

