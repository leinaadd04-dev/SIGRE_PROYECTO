"""SIGRE · Notificaciones de la campana (todas las páginas internas).

Las notificaciones se crean solas con disparadores en PostgreSQL (nueva
emergencia, jornada, desaparecido, centro, cambio de estado de una solicitud,
comentarios, etc.). Aquí solo se consultan y se marcan como leídas.
Requiere backend/migracion_notificaciones.sql.
"""

import logging

import psycopg
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from database import obtener_conexion

notificaciones_bp = Blueprint("notificaciones", __name__)
registro = logging.getLogger(__name__)

COLUMNAS = ("id", "tipo", "titulo", "mensaje", "enlace", "creada_en", "leida")


class SesionNoValida(Exception):
    pass


@notificaciones_bp.errorhandler(SesionNoValida)
def sesion_no_valida(_error):
    return jsonify({"error": "Sesión no válida"}), 401


@notificaciones_bp.errorhandler(psycopg.Error)
def error_base_datos(error):
    registro.exception("Error de base de datos en notificaciones")
    if isinstance(error, (psycopg.errors.UndefinedFunction, psycopg.errors.UndefinedTable)):
        mensaje = "Falta preparar la base: aplica backend/migracion_notificaciones.sql."
    else:
        mensaje = "No se pudieron consultar las notificaciones."
    return jsonify({"error": mensaje}), 500


def _conexion_usuario():
    rol = get_jwt().get("rol")
    try:
        usuario_id = int(get_jwt_identity())
    except (TypeError, ValueError):
        raise SesionNoValida()
    if rol not in ("ciudadano", "voluntario", "autoridad"):
        raise SesionNoValida()
    conexion = obtener_conexion()
    conexion.execute("SELECT set_config('app.user_id', %s, true)", (str(usuario_id),))
    conexion.execute("SELECT set_config('app.user_role', %s, true)", (rol,))
    return conexion


@notificaciones_bp.get("/api/notificaciones")
@jwt_required()
def listar_notificaciones():
    with _conexion_usuario() as conexion:
        filas = conexion.execute(
            f"SELECT {', '.join(COLUMNAS)} FROM sigre_mis_notificaciones(30)"
        ).fetchall()
        no_leidas = conexion.execute(
            "SELECT count(*) FROM sigre_mis_notificaciones(100) WHERE NOT leida"
        ).fetchone()[0]
    notificaciones = []
    for fila in filas:
        notificacion = dict(zip(COLUMNAS, fila))
        notificacion["creada_en"] = notificacion["creada_en"].isoformat()
        notificaciones.append(notificacion)
    return jsonify({"no_leidas": no_leidas, "notificaciones": notificaciones})


@notificaciones_bp.post("/api/notificaciones/<int:notificacion_id>/leida")
@jwt_required()
def marcar_leida(notificacion_id):
    with _conexion_usuario() as conexion:
        conexion.execute("SELECT sigre_marcar_notificaciones_leidas(%s)", (notificacion_id,))
    return jsonify({"mensaje": "Notificación marcada como leída"})


@notificaciones_bp.post("/api/notificaciones/leidas")
@jwt_required()
def marcar_todas_leidas():
    with _conexion_usuario() as conexion:
        total = conexion.execute("SELECT sigre_marcar_notificaciones_leidas(NULL)").fetchone()[0]
    return jsonify({"mensaje": "Notificaciones marcadas como leídas", "total": total})
