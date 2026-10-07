import io
import os 
from pathlib import Path

import re
from datetime import datetime
import psycopg
import unicodedata
from urllib.parse import urlparse

from dotenv import load_dotenv
from flask import Flask, jsonify,request, send_file
from flask_jwt_extended import JWTManager,create_access_token
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from werkzeug.security import check_password_hash, generate_password_hash

from database import obtener_conexion

#lee las variables del archivo backend/.env
load_dotenv(Path(__file__).resolve().parent / ".env")


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024 + 64 * 1024

#flask toma la clave del archivo .env

app.config["JWT_SECRET_KEY"]= os.getenv("JWT_SECRET_KEY")

if not app.config["JWT_SECRET_KEY"]:
    raise RuntimeError("No se encontró JWT_SECRET_KEY en backend/.env")

jwt= JWTManager(app)

def limpiar_texto(valor, limite):
    if not isinstance(valor, str):
        return None

    texto = unicodedata.normalize("NFC", valor)
    texto = "".join(caracter for caracter in texto if caracter.isprintable())
    texto = " ".join(texto.split())

    if not texto or len(texto) > limite:
        return None

    return texto

@app.post("/api/auth/registro")
def registrar_usuario():
    datos = request.get_json(silent=True)

    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    email = datos.get("email")
    password = datos.get("password")

    if not isinstance(email, str) or not isinstance(password, str):
        return jsonify({"error": "Faltan email o contraseña"}), 400

    email = email.strip().lower()

    if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        return jsonify({"error": "El email no tiene un formato válido"}), 400

    if len(password) < 12 or len(password) > 128:
        return jsonify({"error": "La contraseña debe tener entre 12 y 128 caracteres"}), 400

    password_hash = generate_password_hash(password)

    try:
        with obtener_conexion() as conexion:
            conexion.execute(
                """
                INSERT INTO usuarios (email, password_hash, rol)
                VALUES (%s, %s, %s)
                """,
                (email, password_hash, "ciudadano")
            )
    except psycopg.errors.UniqueViolation:
        return jsonify({"error": "Ese email ya está registrado"}), 409

    return jsonify({"mensaje": "Cuenta creada. Ya puedes iniciar sesión."}), 201


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
            "SELECT id, password_hash, rol FROM usuarios WHERE email = %s",
            (email,)
        ).fetchone()

    if usuario is None or not check_password_hash(usuario[1], password):
        return jsonify({"error": "Email o contraseña incorrectos"}), 401

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
            "SELECT id, email, rol FROM usuarios WHERE id = %s",
            (usuario_id,)
        ).fetchone()

    if usuario is None:
        return jsonify({"error": "Cuenta no encontrada"}), 404

    return jsonify({
        "id": usuario[0],
        "email": usuario[1],
        "rol": usuario[2]
    })

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
        respuesta.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        respuesta.headers["Access-Control-Allow-Headers"] = "Content-Type"
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
       fecha_visto, descripcion, estado, creado_en
        FROM reportes_desaparecidos
        {where_sql}
        ORDER BY creado_en DESC
    """

    with obtener_conexion() as conexion:
        filas = conexion.execute(consulta, parametros).fetchall()

    columnas = (
    "id", "tipo", "nombre", "telefono_contacto", "edad", "genero",
    "sector", "fecha_visto", "descripcion", "estado", "creado_en"
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


@app.post("/api/desaparecidos")
def crear_reporte_desaparecido():
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
        fila = conexion.execute(
            """
            INSERT INTO reportes_desaparecidos
                (tipo, nombre, telefono_contacto, edad, genero, sector, fecha_visto,
                descripcion, foto, foto_mime, autoriza_publicacion)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, TRUE)
            RETURNING id, creado_en
            """,
            (
                tipo, nombre, telefono_contacto, edad, genero, sector, fecha_visto,
                descripcion, psycopg.Binary(contenido_foto), mime
            )
        ).fetchone()

    return jsonify({
        "mensaje": "Reporte publicado",
        "id": fila[0],
        "creado_en": fila[1].isoformat()
    }), 201
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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

