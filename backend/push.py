"""SIGRE · Notificaciones push (llegan al celular aunque la app esté cerrada).

- El celular se inscribe desde el menú ☰ ("Activar notificaciones en este
  dispositivo") y guarda su dirección de push con /api/push/suscribir.
- Las notificaciones las crean los disparadores de la base (las mismas de la
  campana). Después de cada acción que puede crearlas (peticiones POST/PUT),
  enviar_push_pendientes() las manda en segundo plano a los celulares inscritos.
- Usa claves VAPID: VAPID_PUBLIC_KEY y VAPID_PRIVATE_KEY en backend/.env y en
  Render (se crean con: python backend/push.py). Sin ellas, el push se apaga
  y el resto de SIGRE funciona igual.

Requiere backend/migracion_push.sql.
"""

import json
import logging
import os
import re
import threading

import psycopg
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

from database import obtener_conexion

push_bp = Blueprint("push", __name__)
registro = logging.getLogger(__name__)

_candado_envio = threading.Lock()
_hay_mas = threading.Event()


def push_activo():
    return bool(os.getenv("VAPID_PUBLIC_KEY") and os.getenv("VAPID_PRIVATE_KEY"))


def _conexion_de(usuario_id):
    conexion = obtener_conexion()
    conexion.execute("SELECT set_config('app.user_id', %s, true)", (str(usuario_id),))
    return conexion


def _usuario():
    try:
        return int(get_jwt_identity())
    except (TypeError, ValueError):
        return None


# ---------- Rutas ----------

@push_bp.get("/api/push/clave-publica")
def clave_publica():
    if not push_activo():
        return jsonify({"activo": False})
    return jsonify({"activo": True, "clave": os.getenv("VAPID_PUBLIC_KEY")})


@push_bp.post("/api/push/suscribir")
@jwt_required()
def suscribir():
    usuario_id = _usuario()
    datos = request.get_json(silent=True) or {}
    endpoint = datos.get("endpoint")
    claves = datos.get("keys") if isinstance(datos.get("keys"), dict) else {}
    p256dh, auth = claves.get("p256dh"), claves.get("auth")
    # La dirección la da el navegador: siempre es HTTPS de un servicio de push.
    if (usuario_id is None
            or not isinstance(endpoint, str) or not re.fullmatch(r"https://[^\s]{10,990}", endpoint)
            or not isinstance(p256dh, str) or not re.fullmatch(r"[A-Za-z0-9_\-=]{10,200}", p256dh)
            or not isinstance(auth, str) or not re.fullmatch(r"[A-Za-z0-9_\-=]{10,100}", auth)):
        return jsonify({"error": "No se pudo activar en este dispositivo"}), 400
    with _conexion_de(usuario_id) as conexion:
        conexion.execute("SELECT sigre_guardar_suscripcion_push(%s, %s, %s)", (endpoint, p256dh, auth))
    return jsonify({"mensaje": "Notificaciones activadas en este dispositivo"})


@push_bp.post("/api/push/desuscribir")
@jwt_required()
def desuscribir():
    usuario_id = _usuario()
    endpoint = (request.get_json(silent=True) or {}).get("endpoint")
    if usuario_id is None or not isinstance(endpoint, str) or len(endpoint) > 1000:
        return jsonify({"error": "Dispositivo no válido"}), 400
    with _conexion_de(usuario_id) as conexion:
        conexion.execute("SELECT sigre_borrar_suscripcion_push(%s)", (endpoint,))
    return jsonify({"mensaje": "Notificaciones desactivadas en este dispositivo"})


# ---------- Envío ----------

def _enviar_lote():
    from pywebpush import WebPushException, webpush

    with obtener_conexion() as conexion:
        filas = conexion.execute(
            "SELECT endpoint, p256dh, auth, tipo, titulo, mensaje, enlace, notificacion_id "
            "FROM sigre_push_pendientes()"
        ).fetchall()

    for endpoint, p256dh, auth, tipo, titulo, mensaje, enlace, notificacion_id in filas:
        aviso = json.dumps({
            "titulo": titulo,
            "mensaje": mensaje[:240],
            "enlace": enlace or "dashboard.html",
            "tipo": tipo,
            "etiqueta": f"sigre-{notificacion_id}",
        }, ensure_ascii=False)
        try:
            webpush(
                subscription_info={"endpoint": endpoint, "keys": {"p256dh": p256dh, "auth": auth}},
                data=aviso,
                vapid_private_key=os.getenv("VAPID_PRIVATE_KEY"),
                vapid_claims={"sub": os.getenv("VAPID_CONTACTO", "mailto:sigre.oficial@gmail.com")},
                ttl=24 * 3600,
                timeout=10,
            )
        except WebPushException as error:
            estado = getattr(error.response, "status_code", None)
            if estado in (404, 410):
                # El celular ya no existe (desinstaló la app o quitó el permiso).
                with obtener_conexion() as conexion:
                    conexion.execute("SELECT sigre_descartar_suscripcion_push(%s)", (endpoint,))
            else:
                registro.warning("No se pudo enviar un push (estado %s)", estado)
        except Exception:
            registro.exception("No se pudo enviar un push")


def _enviar_en_segundo_plano():
    # Un solo envío a la vez; si llegan más avisos mientras tanto, se repite.
    if not _candado_envio.acquire(blocking=False):
        _hay_mas.set()
        return
    try:
        while True:
            _hay_mas.clear()
            try:
                _enviar_lote()
            except psycopg.errors.UndefinedFunction:
                registro.warning("Falta aplicar backend/migracion_push.sql")
                return
            except Exception:
                registro.exception("Falló el envío de notificaciones push")
                return
            if not _hay_mas.is_set():
                return
    finally:
        _candado_envio.release()


def enviar_push_pendientes():
    """Envía en segundo plano las notificaciones nuevas a los celulares inscritos."""
    if push_activo():
        threading.Thread(target=_enviar_en_segundo_plano, daemon=True).start()


@push_bp.after_app_request
def despues_de_cada_accion(respuesta):
    # Las notificaciones nacen de acciones (publicar, cambiar estados, comentar…).
    if request.method in ("POST", "PUT") and respuesta.status_code < 400:
        enviar_push_pendientes()
    return respuesta


if __name__ == "__main__":
    # Crea un par de claves VAPID nuevas para backend/.env y Render.
    import base64

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    def b64(datos):
        return base64.urlsafe_b64encode(datos).rstrip(b"=").decode()

    privada = ec.generate_private_key(ec.SECP256R1())
    numero = privada.private_numbers().private_value.to_bytes(32, "big")
    publica = privada.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    print(f"VAPID_PUBLIC_KEY={b64(publica)}")
    print(f"VAPID_PRIVATE_KEY={b64(numero)}")
