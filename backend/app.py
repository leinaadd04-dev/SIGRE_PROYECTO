import os 
from pathlib import Path

import re
import psycopg
import unicodedata

from dotenv import load_dotenv
from flask import Flask, jsonify,request
from flask_jwt_extended import JWTManager,create_access_token
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from werkzeug.security import check_password_hash, generate_password_hash

from database import obtener_conexion

#lee las variables del archivo backend/.env
load_dotenv(Path(__file__).resolve().parent / ".env")


app = Flask(__name__)

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
    app.run(debug=True)