"""SIGRE · SOS en vivo: cola de emergencias y asignación a operadores (Socket.IO).

Salas:
    operadores   todas las cuentas autoridad conectadas al panel.
    en_espera    los ciudadanos cuya emergencia aún no atiende nadie.
    sos-<id>     el ciudadano y el operador de una emergencia.

La base (migracion_sos.sql) aplica las reglas con seguridad por filas; aquí se
fija la cuenta de cada conexión antes de consultarla.
"""
import logging
import math
import os

import psycopg
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from flask_socketio import emit, join_room, leave_room

from database import obtener_conexion
from push import enviar_push_pendientes

registro = logging.getLogger(__name__)

ROLES_CIUDADANO = ("ciudadano", "voluntario")


sos_bp = Blueprint("sos", __name__)


@sos_bp.get("/api/sos/ice")
@jwt_required()
def servidores_ice():
    # Las credenciales del TURN viven en variables de entorno, no en el frontend.
    servidores = [{"urls": "stun:stun.l.google.com:19302"}]
    urls = [url.strip() for url in os.getenv("TURN_URLS", "").split(",") if url.strip()]
    if urls and os.getenv("TURN_USUARIO") and os.getenv("TURN_CLAVE"):
        servidores.append({
            "urls": urls,
            "username": os.getenv("TURN_USUARIO"),
            "credential": os.getenv("TURN_CLAVE"),
        })
    return jsonify({"iceServers": servidores})



def _conexion(usuario):
    conexion = obtener_conexion()
    conexion.execute("SELECT set_config('app.user_id', %s, true)", (str(usuario["usuario_id"]),))
    conexion.execute("SELECT set_config('app.user_role', %s, true)", (usuario["rol"],))
    return conexion


def _id_sesion(datos):
    try:
        valor = int((datos or {}).get("sesion"))
    except (TypeError, ValueError):
        return None
    return valor if valor > 0 else None


def _ubicacion(datos):
    """Devuelve (lat, lng, precisión) válidos o None."""
    try:
        lat = float(datos.get("lat"))
        lng = float(datos.get("lng"))
    except (AttributeError, TypeError, ValueError):
        return None
    if not (math.isfinite(lat) and math.isfinite(lng) and -90 <= lat <= 90 and -180 <= lng <= 180):
        return None
    try:
        precision = float(datos.get("precision"))
        precision = precision if math.isfinite(precision) and 0 <= precision <= 100000 else None
    except (TypeError, ValueError):
        precision = None
    return lat, lng, precision


def _fecha(valor):
    return valor.isoformat() if valor else None


    

def _contacto(conexion, sesion):
    """Datos del ciudadano para el operador que lo atiende (o None)."""
    fila = conexion.execute(
        "SELECT nombre, telefono, contacto_emergencia_nombre, contacto_emergencia_telefono "
        "FROM sigre_contacto_sos(%s)", (sesion,)
    ).fetchone()
    if not fila:
        return None
    return {
        "nombre": fila[0],
        "telefono": fila[1],
        "contacto_emergencia_nombre": fila[2],
        "contacto_emergencia_telefono": fila[3],
    }



def registrar_eventos_sos(socketio, conectados):

    def yo():
        return conectados.get(request.sid)

    def sids_de(usuario_id):
        return [sid for sid, datos in list(conectados.items()) if datos["usuario_id"] == usuario_id]

    def avisar_cola():
        # Cada ciudadano en espera vuelve a pedir su posición.
        socketio.emit("cola:actualizar", to="en_espera")

    # ---------- Ciudadano ----------

    @socketio.on("sos:crear")
    def sos_crear(datos):
        usuario = yo()
        if usuario is None or usuario["rol"] not in ROLES_CIUDADANO:
            return {"error": "Solo las cuentas de la comunidad pueden pedir SOS en vivo."}
        ubicacion = _ubicacion(datos or {})
        if ubicacion is None:
            return {"error": "No llegó una ubicación válida."}
        lat, lng, precision = ubicacion

        try:
            with _conexion(usuario) as conexion:
                sesion, creada_en = conexion.execute(
                    "INSERT INTO sesiones_sos (ciudadano_id) VALUES (%s) RETURNING id, creada_en",
                    (usuario["usuario_id"],),
                ).fetchone()
                conexion.execute(
                    "INSERT INTO ubicaciones_sos (sesion_id, latitud, longitud, precision_m) "
                    "VALUES (%s, %s, %s, %s)",
                    (sesion, lat, lng, precision),
                )
                posicion = conexion.execute(
                    "SELECT sigre_posicion_cola_sos(%s)", (sesion,)
                ).fetchone()[0]
        except psycopg.errors.UniqueViolation:
            # Ya tiene una emergencia abierta: se retoma esa en vez de crear otra.
            return sos_retomar()
        except psycopg.Error:
            registro.exception("No se pudo crear la emergencia SOS")
            return {"error": "No se pudo registrar la emergencia. Llama al 123."}

        join_room(f"sos-{sesion}")
        join_room("en_espera")
        emit("sos:nueva", {
            "sesion": sesion,
            "lat": lat,
            "lng": lng,
            "precision": precision,
            "creada_en": _fecha(creada_en),
        }, to="operadores")
        enviar_push_pendientes()
        avisar_cola()
        return {"sesion": sesion, "estado": "en_espera", "posicion": posicion}

    @socketio.on("cola:posicion")
    def cola_posicion(datos):
        usuario = yo()
        sesion = _id_sesion(datos)
        if usuario is None or sesion is None:
            return {"error": "Emergencia no válida."}
        with _conexion(usuario) as conexion:
            posicion = conexion.execute(
                "SELECT sigre_posicion_cola_sos(%s)", (sesion,)
            ).fetchone()[0]
        return {"sesion": sesion, "posicion": posicion}

    @socketio.on("sos:cancelar")
    def sos_cancelar(datos):
        usuario = yo()
        sesion = _id_sesion(datos)
        if usuario is None or sesion is None:
            return {"error": "Emergencia no válida."}
        with _conexion(usuario) as conexion:
            cancelada = conexion.execute(
                "UPDATE sesiones_sos SET estado = 'cancelada', finalizada_en = NOW(), "
                "motivo_cierre = 'Cancelada por el ciudadano antes de ser atendida' "
                "WHERE id = %s AND ciudadano_id = %s AND estado = 'en_espera' RETURNING id",
                (sesion, usuario["usuario_id"]),
            ).fetchone()
        if cancelada is None:
            return {"error": "La emergencia ya no está en espera."}
        leave_room("en_espera")
        leave_room(f"sos-{sesion}")
        emit("sos:retirada", {"sesion": sesion, "motivo": "cancelada"}, to="operadores")
        avisar_cola()
        return {"ok": True}

    # ---------- Operador ----------

    @socketio.on("sos:cola")
    def sos_cola():
        usuario = yo()
        if usuario is None or usuario["rol"] != "autoridad":
            return {"error": "No permitido."}
        with _conexion(usuario) as conexion:
            filas = conexion.execute(
                """
                SELECT s.id, s.creada_en, u.latitud, u.longitud, u.precision_m
                FROM sesiones_sos s
                LEFT JOIN LATERAL (
                    SELECT latitud, longitud, precision_m FROM ubicaciones_sos
                    WHERE sesion_id = s.id ORDER BY registrada_en DESC, id DESC LIMIT 1
                ) u ON TRUE
                WHERE s.estado = 'en_espera'
                ORDER BY s.creada_en, s.id
                """
            ).fetchall()
        return {"cola": [{
            "sesion": fila[0],
            "creada_en": _fecha(fila[1]),
            "lat": fila[2],
            "lng": fila[3],
            "precision": fila[4],
        } for fila in filas]}


    @socketio.on("sos:aceptar")
    def sos_aceptar(datos):
        usuario = yo()
        sesion = _id_sesion(datos)
        if usuario is None or usuario["rol"] != "autoridad":
            return {"error": "No permitido."}
        if sesion is None:
            return {"error": "Emergencia no válida."}

        # Asignación atómica: si dos operadores aceptan a la vez, PostgreSQL
        # bloquea la fila y el segundo UPDATE ya no la encuentra en espera.
        with _conexion(usuario) as conexion:
            tomada = conexion.execute(
                "UPDATE sesiones_sos SET estado = 'en_curso', operador_id = %s, atendida_en = NOW() "
                "WHERE id = %s AND estado = 'en_espera' AND operador_id IS NULL "
                "RETURNING ciudadano_id, atendida_en",
                (usuario["usuario_id"], sesion),
            ).fetchone()
            contacto = _contacto(conexion, sesion) if tomada is not None else None

        if tomada is None:
            return {"error": "Esta emergencia ya fue tomada por otro operador."}

        atendida_en = _fecha(tomada[1])
        sala = f"sos-{sesion}"
        join_room(sala)
        for sid in sids_de(tomada[0]):
            leave_room("en_espera", sid=sid)
            join_room(sala, sid=sid)
        emit("sos:aceptada", {"sesion": sesion, "atendida_en": atendida_en}, to=sala)
        emit("sos:retirada", {"sesion": sesion, "motivo": "tomada"}, to="operadores")
        avisar_cola()
        return {"ok": True, "sesion": sesion, "contacto": contacto, "atendida_en": atendida_en}

    
    @socketio.on("sos:finalizar")
    def sos_finalizar(datos):
        """Cuelga la videollamada y cierra la emergencia. Lo puede hacer el
        operador que la atiende o el ciudadano que la pidió."""
        usuario = yo()
        sesion = _id_sesion(datos)
        if usuario is None or sesion is None:
            return {"error": "Emergencia no válida."}
        es_operador = usuario["rol"] == "autoridad"
        participante = "operador_id" if es_operador else "ciudadano_id"
        motivo = "Finalizada por el operador" if es_operador else "Finalizada por el ciudadano"

        with _conexion(usuario) as conexion:
            fila = conexion.execute(
                "UPDATE sesiones_sos SET estado = 'finalizada', finalizada_en = NOW(), motivo_cierre = %s "
                f"WHERE id = %s AND {participante} = %s AND estado = 'en_curso' "
                "RETURNING atendida_en, finalizada_en",
                (motivo, sesion, usuario["usuario_id"]),
            ).fetchone()
        if fila is None:
            return {"error": "Esta emergencia ya no está en curso."}

        duracion = int((fila[1] - fila[0]).total_seconds())
        sala = f"sos-{sesion}"
        emit("sos:finalizada", {
            "sesion": sesion,
            "por": "operador" if es_operador else "ciudadano",
            "duracion": duracion,
        }, to=sala)
        socketio.close_room(sala)   # nadie queda en la sala de una emergencia cerrada
        return {"ok": True, "duracion": duracion}



   
    # ---------- Ambos ----------

    @socketio.on("sos:retomar")
    def sos_retomar(datos=None):
        """Tras recargar la página o recuperar la conexión, vuelve a unir la
        cuenta a su emergencia abierta, si tiene una."""
        usuario = yo()
        if usuario is None:
            return {"error": "No permitido."}
        if usuario["rol"] == "autoridad":
            condicion = "operador_id = %s AND estado = 'en_curso'"
        else:
            condicion = "ciudadano_id = %s AND estado IN ('en_espera', 'en_curso')"
        with _conexion(usuario) as conexion:
            fila = conexion.execute(
                f"SELECT id, estado, atendida_en FROM sesiones_sos WHERE {condicion} "
                "ORDER BY creada_en DESC LIMIT 1",
                (usuario["usuario_id"],),
            ).fetchone()
            if fila is None:
                return {"sesion": None}
            sesion, estado, atendida_en = fila
            posicion = None
            if estado == "en_espera":
                posicion = conexion.execute(
                    "SELECT sigre_posicion_cola_sos(%s)", (sesion,)
                ).fetchone()[0]
            # Al operador se le reenvía el contacto (por ejemplo, tras recargar el panel).
            contacto = _contacto(conexion, sesion) if usuario["rol"] == "autoridad" else None

        join_room(f"sos-{sesion}")
        if estado == "en_espera":
            join_room("en_espera")
        return {
            "sesion": sesion,
            "estado": estado,
            "posicion": posicion,
            "atendida_en": _fecha(atendida_en),
            "contacto": contacto,
        }

    # ---------- Señalización WebRTC ----------
    def es_participante(usuario, sesion):
        with _conexion(usuario) as conexion:
            fila = conexion.execute(
                "SELECT 1 FROM sesiones_sos WHERE id = %s AND estado = 'en_curso' "
                "AND %s IN (ciudadano_id, operador_id)",
                (sesion, usuario["usuario_id"]),
            ).fetchone()
        return fila is not None

    def retransmitir(evento):
        def manejador(datos):
            usuario = yo()
            sesion = _id_sesion(datos)
            if usuario is None or sesion is None or not es_participante(usuario, sesion):
                return {"error": "No participas en esta emergencia."}
            mensaje = {"sesion": sesion, "sdp": datos.get("sdp"), "candidato": datos.get("candidato")}
            emit(evento, mensaje, to=f"sos-{sesion}", include_self=False)
            return {"ok": True}
        return manejador

    for evento in ("webrtc:offer", "webrtc:answer", "webrtc:ice", "webrtc:pedir_oferta"):

        socketio.on_event(evento, retransmitir(evento))




    