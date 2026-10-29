"""SIGRE · Panel de administración (rol 'autoridad': administrador o entidad).

- Resumen, lista de usuarios y cambio de rol.
- Gestión de centros de acopio y albergues (y su listado público).
- Gestión de reportes de desaparecidos (marcar encontrado o retirar).

Requiere backend/migracion_administracion.sql. Cada operación se comprueba dos
veces: aquí con el rol del token y en PostgreSQL con el rol guardado en la base.
"""

import logging
import re
import unicodedata

import psycopg
from PIL import Image, ImageOps

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required, verify_jwt_in_request

from database import obtener_conexion

administracion_bp = Blueprint("administracion", __name__)
registro = logging.getLogger(__name__)

ROLES = ("ciudadano", "voluntario", "autoridad")
TIPOS_CENTRO = ("acopio", "albergue")
ESTADOS_CENTRO = ("abierto", "cerrado")
COLUMNAS_CENTRO = (
    "id", "nombre", "tipo", "direccion", "descripcion", "necesidades", "telefono",
    "latitud", "longitud", "capacidad", "ocupados", "estado", "actualizado_en",
)


class SinPermiso(Exception):
    pass


@administracion_bp.errorhandler(SinPermiso)
def sin_permiso(_error):
    return jsonify({"error": "Esta sección es solo para cuentas de administrador o entidad"}), 403


# Sin este manejador, un error de la base llega al navegador como una página de
# depuración sin CORS y parece que "no hay conexión con el servidor".
@administracion_bp.errorhandler(psycopg.Error)
def error_base_datos(error):
    if isinstance(error, psycopg.errors.InsufficientPrivilege):
        return jsonify({"error": "Esta sección es solo para cuentas de administrador o entidad"}), 403
    if isinstance(error, psycopg.errors.InvalidParameterValue):
        return jsonify({"error": error.diag.message_primary or "Dato no válido"}), 400
    registro.exception("Error de base de datos en administración")
    if isinstance(error, (psycopg.errors.UndefinedFunction, psycopg.errors.UndefinedTable)):
        mensaje = ("Falta preparar la base: aplica las migraciones del backend "
                   "(administración, contenidos, participación en jornadas e inventario de centros).")
    elif isinstance(error, psycopg.OperationalError):
        mensaje = "No se pudo conectar con la base de datos. Revisa que PostgreSQL esté encendido."
    else:
        mensaje = "La base de datos no pudo completar la operación. Revisa la terminal de Flask."
    return jsonify({"error": mensaje}), 500


# ---------- Utilidades ----------

def _autoridad():
    """Devuelve el id de la cuenta si el token es de una autoridad."""
    if get_jwt().get("rol") != "autoridad":
        raise SinPermiso()
    try:
        return int(get_jwt_identity())
    except (TypeError, ValueError):
        raise SinPermiso()


def _conexion_autoridad(usuario_id):
    conexion = obtener_conexion()
    conexion.execute("SELECT set_config('app.user_id', %s, true)", (str(usuario_id),))
    conexion.execute("SELECT set_config('app.user_role', 'autoridad', true)")
    return conexion


def _texto(valor, minimo, maximo, opcional=False):
    if valor is None or (isinstance(valor, str) and not valor.strip()):
        return (True, None) if opcional else (False, None)
    if not isinstance(valor, str):
        return False, None
    texto = unicodedata.normalize("NFC", valor)
    texto = " ".join("".join(c for c in texto if c.isprintable()).split())
    if not minimo <= len(texto) <= maximo:
        return False, None
    return True, texto


def _entero(valor, minimo, maximo):
    if isinstance(valor, bool):
        return None
    try:
        numero = int(valor)
    except (TypeError, ValueError):
        return None
    return numero if minimo <= numero <= maximo and str(numero) == str(valor).strip() else None


def _fila_centro(fila):
    centro = dict(zip(COLUMNAS_CENTRO, fila))
    centro["actualizado_en"] = centro["actualizado_en"].isoformat()
    return centro


def _validar_centro(datos):
    """Devuelve (centro, None) o (None, mensaje de error)."""
    if not isinstance(datos, dict):
        return None, "Envía los datos como JSON"

    ok, nombre = _texto(datos.get("nombre"), 3, 120)
    if not ok:
        return None, "Escribe el nombre del centro (entre 3 y 120 caracteres)"
    tipo = datos.get("tipo")
    if tipo not in TIPOS_CENTRO:
        return None, "Elige si es centro de acopio o albergue"
    ok, direccion = _texto(datos.get("direccion"), 3, 200)
    if not ok:
        return None, "Escribe la dirección o el sector (entre 3 y 200 caracteres)"
    ok, descripcion = _texto(datos.get("descripcion"), 1, 600, opcional=True)
    if not ok:
        return None, "La descripción puede tener máximo 600 caracteres"
    ok, necesidades = _texto(datos.get("necesidades"), 1, 400, opcional=True)
    if not ok:
        return None, "Las necesidades pueden tener máximo 400 caracteres"
    ok, telefono = _texto(datos.get("telefono"), 7, 20, opcional=True)
    if not ok or (telefono and (
        not re.fullmatch(r"\+?[0-9 ()-]{7,20}", telefono)
        or len(re.sub(r"\D", "", telefono)) < 7
    )):
        return None, "Escribe un teléfono válido o déjalo vacío"

    # Los cupos solo aplican a albergues; un centro de acopio recibe donaciones.
    if tipo == "acopio":
        capacidad = ocupados = 0
    else:
        capacidad = _entero(datos.get("capacidad", 0), 0, 100000)
        ocupados = _entero(datos.get("ocupados", 0), 0, 100000)
    if capacidad is None or ocupados is None:
        return None, "Los cupos deben ser números enteros entre 0 y 100000"
    if ocupados > capacidad:
        return None, "Los cupos ocupados no pueden ser más que la capacidad"

    estado = datos.get("estado", "abierto")
    if estado not in ESTADOS_CENTRO:
        return None, "El estado debe ser abierto o cerrado"

    latitud = datos.get("latitud")
    longitud = datos.get("longitud")
    if latitud in (None, "") and longitud in (None, ""):
        latitud = longitud = None
    else:
        try:
            latitud, longitud = float(latitud), float(longitud)
        except (TypeError, ValueError):
            return None, "La ubicación en el mapa no es válida"
        if not (-90 <= latitud <= 90 and -180 <= longitud <= 180):
            return None, "La ubicación en el mapa no es válida"

    return {
        "nombre": nombre, "tipo": tipo, "direccion": direccion,
        "descripcion": descripcion, "necesidades": necesidades, "telefono": telefono,
        "latitud": latitud, "longitud": longitud,
        "capacidad": capacidad, "ocupados": ocupados, "estado": estado,
    }, None


# ---------- Centros: listado público ----------

@administracion_bp.get("/api/centros")
def listar_centros_publico():
    with obtener_conexion() as conexion:
        filas = conexion.execute(
            f"SELECT {', '.join(COLUMNAS_CENTRO)} FROM centros_ayuda "
            "ORDER BY estado, tipo, nombre"
        ).fetchall()
    return jsonify([_fila_centro(fila) for fila in filas])


# ---------- Resumen y usuarios ----------

@administracion_bp.get("/api/admin/resumen")
@jwt_required()
def resumen_admin():
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        resumen = conexion.execute("SELECT admin_resumen()").fetchone()[0]
    resumen["mi_id"] = usuario_id
    return jsonify(resumen)


@administracion_bp.get("/api/admin/usuarios")
@jwt_required()
def listar_usuarios_admin():
    usuario_id = _autoridad()
    ok, busqueda = _texto(request.args.get("q"), 1, 100, opcional=True)
    if not ok:
        return jsonify({"error": "La búsqueda puede tener máximo 100 caracteres"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        filas = conexion.execute(
            "SELECT id, email, nombre, telefono, rol, creado_en FROM admin_listar_usuarios(%s)",
            (busqueda,)
        ).fetchall()
    return jsonify([
        {"id": f[0], "email": f[1], "nombre": f[2], "telefono": f[3], "rol": f[4],
         "creado_en": f[5].isoformat(), "es_yo": f[0] == usuario_id}
        for f in filas
    ])


@administracion_bp.post("/api/admin/usuarios/<int:objetivo_id>/rol")
@jwt_required()
def cambiar_rol_admin(objetivo_id):
    usuario_id = _autoridad()
    datos = request.get_json(silent=True) or {}
    rol = datos.get("rol")
    if rol not in ROLES:
        return jsonify({"error": "Rol no válido"}), 400
    if objetivo_id == usuario_id:
        return jsonify({"error": "No puedes cambiar tu propio rol"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        encontrado = conexion.execute(
            "SELECT admin_cambiar_rol(%s, %s)", (objetivo_id, rol)
        ).fetchone()[0]
    if not encontrado:
        return jsonify({"error": "Usuario no encontrado"}), 404
    return jsonify({"mensaje": "Rol actualizado. Se aplicará cuando esa persona vuelva a iniciar sesión."})


# ---------- Centros: gestión ----------

@administracion_bp.post("/api/admin/centros")
@jwt_required()
def crear_centro():
    usuario_id = _autoridad()
    centro, error = _validar_centro(request.get_json(silent=True))
    if error:
        return jsonify({"error": error}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            f"""
            INSERT INTO centros_ayuda
                (nombre, tipo, direccion, descripcion, necesidades, telefono,
                 latitud, longitud, capacidad, ocupados, estado, creado_por)
            VALUES (%(nombre)s, %(tipo)s, %(direccion)s, %(descripcion)s, %(necesidades)s,
                    %(telefono)s, %(latitud)s, %(longitud)s, %(capacidad)s, %(ocupados)s,
                    %(estado)s, %(creado_por)s)
            RETURNING {', '.join(COLUMNAS_CENTRO)}
            """,
            dict(centro, creado_por=usuario_id)
        ).fetchone()
    return jsonify(_fila_centro(fila)), 201


@administracion_bp.post("/api/admin/centros/<int:centro_id>")
@jwt_required()
def editar_centro(centro_id):
    usuario_id = _autoridad()
    centro, error = _validar_centro(request.get_json(silent=True))
    if error:
        return jsonify({"error": error}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            f"""
            UPDATE centros_ayuda
            SET nombre = %(nombre)s, tipo = %(tipo)s, direccion = %(direccion)s,
                descripcion = %(descripcion)s, necesidades = %(necesidades)s,
                telefono = %(telefono)s, latitud = %(latitud)s, longitud = %(longitud)s,
                capacidad = %(capacidad)s, ocupados = %(ocupados)s, estado = %(estado)s,
                actualizado_en = NOW()
            WHERE id = %(id)s
            RETURNING {', '.join(COLUMNAS_CENTRO)}
            """,
            dict(centro, id=centro_id)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Centro no encontrado"}), 404
    return jsonify(_fila_centro(fila))


@administracion_bp.post("/api/admin/centros/<int:centro_id>/eliminar")
@jwt_required()
def eliminar_centro(centro_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            "DELETE FROM centros_ayuda WHERE id = %s RETURNING id", (centro_id,)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Centro no encontrado"}), 404
    return jsonify({"mensaje": "Centro eliminado"})


# ---------- Centros: inventario ----------
# Requiere backend/migracion_inventario_centros.sql.

CATEGORIAS_INVENTARIO = ("aseo", "no_perecederos", "perecederos", "agua", "mascotas",
                         "descanso", "ropa", "botiquin", "bebes", "otros")
UNIDADES_INVENTARIO = ("unidades", "kg", "libras", "litros", "paquetes", "cajas", "bolsas", "pares")
COLUMNAS_INVENTARIO = ("id", "centro_id", "centro_nombre", "centro_tipo", "categoria", "producto",
                       "talla", "cantidad", "unidad", "minimo", "actualizado_en")
SELECT_INVENTARIO = """
    SELECT i.id, i.centro_id, c.nombre, c.tipo, i.categoria, i.producto,
           i.talla, i.cantidad, i.unidad, i.minimo, i.actualizado_en
    FROM inventario_centros i
    JOIN centros_ayuda c ON c.id = i.centro_id
"""


def _fila_inventario(fila):
    producto = dict(zip(COLUMNAS_INVENTARIO, fila))
    producto["actualizado_en"] = producto["actualizado_en"].isoformat()
    return producto


def _validar_producto(datos):
    """Devuelve (producto, None) o (None, mensaje de error)."""
    if not isinstance(datos, dict):
        return None, "Envía los datos como JSON"
    centro_id = _entero(datos.get("centro_id"), 1, 10 ** 12)
    if centro_id is None:
        return None, "Elige el centro de acopio o albergue"
    categoria = datos.get("categoria")
    if categoria not in CATEGORIAS_INVENTARIO:
        return None, "Elige una categoría válida"
    ok, producto = _texto(datos.get("producto"), 2, 120)
    if not ok:
        return None, "Escribe el nombre del producto (entre 2 y 120 caracteres)"
    # La talla solo aplica a ropa y calzado; en las demás categorías se ignora.
    talla = None
    if categoria == "ropa":
        ok, talla = _texto(datos.get("talla"), 1, 20, opcional=True)
        if not ok:
            return None, "La talla puede tener máximo 20 caracteres"
    cantidad = _entero(datos.get("cantidad", 0), 0, 1000000)
    if cantidad is None:
        return None, "La cantidad debe ser un número entero entre 0 y 1.000.000"
    unidad = datos.get("unidad", "unidades")
    if unidad not in UNIDADES_INVENTARIO:
        return None, "Elige una unidad válida"
    minimo = _entero(datos.get("minimo", 0), 0, 1000000)
    if minimo is None:
        return None, "La cantidad mínima debe ser un número entero entre 0 y 1.000.000"
    return {"centro_id": centro_id, "categoria": categoria, "producto": producto, "talla": talla,
            "cantidad": cantidad, "unidad": unidad, "minimo": minimo}, None


@administracion_bp.get("/api/centros/inventario")
def listar_inventario():
    # Público: la comunidad ve qué hay y qué falta. Filtros opcionales.
    condiciones, parametros = [], []
    centro_id = request.args.get("centro_id")
    if centro_id:
        centro_id = _entero(centro_id, 1, 10 ** 12)
        if centro_id is None:
            return jsonify({"error": "Centro no válido"}), 400
        condiciones.append("i.centro_id = %s")
        parametros.append(centro_id)
    categoria = request.args.get("categoria")
    if categoria:
        if categoria not in CATEGORIAS_INVENTARIO:
            return jsonify({"error": "Categoría no válida"}), 400
        condiciones.append("i.categoria = %s")
        parametros.append(categoria)
    donde = ("WHERE " + " AND ".join(condiciones)) if condiciones else ""
    with obtener_conexion() as conexion:
        filas = conexion.execute(
            f"{SELECT_INVENTARIO} {donde} ORDER BY c.nombre, i.categoria, lower(i.producto), i.talla NULLS FIRST LIMIT 5000",
            parametros
        ).fetchall()
    return jsonify([_fila_inventario(fila) for fila in filas])


@administracion_bp.post("/api/admin/inventario")
@administracion_bp.post("/api/admin/inventario/<int:producto_id>")
@jwt_required()
def guardar_producto(producto_id=None):
    usuario_id = _autoridad()
    producto, error = _validar_producto(request.get_json(silent=True))
    if error:
        return jsonify({"error": error}), 400
    try:
        with _conexion_autoridad(usuario_id) as conexion:
            if conexion.execute("SELECT 1 FROM centros_ayuda WHERE id = %s",
                                (producto["centro_id"],)).fetchone() is None:
                return jsonify({"error": "El centro ya no existe"}), 404
            if producto_id is None:
                nuevo = conexion.execute(
                    """INSERT INTO inventario_centros
                           (centro_id, categoria, producto, talla, cantidad, unidad, minimo, actualizado_por)
                       VALUES (%(centro_id)s, %(categoria)s, %(producto)s, %(talla)s, %(cantidad)s,
                               %(unidad)s, %(minimo)s, %(usuario)s)
                       RETURNING id""",
                    dict(producto, usuario=usuario_id)
                ).fetchone()
            else:
                nuevo = conexion.execute(
                    """UPDATE inventario_centros
                       SET centro_id = %(centro_id)s, categoria = %(categoria)s, producto = %(producto)s,
                           talla = %(talla)s, cantidad = %(cantidad)s, unidad = %(unidad)s, minimo = %(minimo)s,
                           actualizado_por = %(usuario)s, actualizado_en = NOW()
                       WHERE id = %(id)s
                       RETURNING id""",
                    dict(producto, usuario=usuario_id, id=producto_id)
                ).fetchone()
            if nuevo is None:
                return jsonify({"error": "Producto no encontrado"}), 404
            fila = conexion.execute(f"{SELECT_INVENTARIO} WHERE i.id = %s", (nuevo[0],)).fetchone()
    except psycopg.errors.UniqueViolation:
        return jsonify({"error": "Ese producto (con esa talla) ya está en el inventario de este centro. Edita su cantidad."}), 409
    return jsonify(_fila_inventario(fila)), 201 if producto_id is None else 200


@administracion_bp.post("/api/admin/inventario/<int:producto_id>/cantidad")
@jwt_required()
def cambiar_cantidad_producto(producto_id):
    # Edición rápida desde la tabla: solo la cantidad.
    usuario_id = _autoridad()
    cantidad = _entero((request.get_json(silent=True) or {}).get("cantidad"), 0, 1000000)
    if cantidad is None:
        return jsonify({"error": "La cantidad debe ser un número entero entre 0 y 1.000.000"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        nuevo = conexion.execute(
            """UPDATE inventario_centros
               SET cantidad = %s, actualizado_por = %s, actualizado_en = NOW()
               WHERE id = %s
               RETURNING id""",
            (cantidad, usuario_id, producto_id)
        ).fetchone()
        if nuevo is None:
            return jsonify({"error": "Producto no encontrado"}), 404
        fila = conexion.execute(f"{SELECT_INVENTARIO} WHERE i.id = %s", (producto_id,)).fetchone()
    return jsonify(_fila_inventario(fila))


@administracion_bp.post("/api/admin/inventario/<int:producto_id>/eliminar")
@jwt_required()
def eliminar_producto(producto_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            "DELETE FROM inventario_centros WHERE id = %s RETURNING id", (producto_id,)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Producto no encontrado"}), 404
    return jsonify({"mensaje": "Producto eliminado del inventario"})


# ---------- Desaparecidos: gestión ----------

@administracion_bp.post("/api/admin/desaparecidos/<int:reporte_id>/estado")
@jwt_required()
def cambiar_estado_desaparecido(reporte_id):
    usuario_id = _autoridad()
    estado = (request.get_json(silent=True) or {}).get("estado")
    if estado not in ("activo", "encontrado"):
        return jsonify({"error": "El estado debe ser activo o encontrado"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        encontrado = conexion.execute(
            "SELECT admin_cambiar_estado_desaparecido(%s, %s)", (reporte_id, estado)
        ).fetchone()[0]
    if not encontrado:
        return jsonify({"error": "Reporte no encontrado"}), 404
    return jsonify({"mensaje": "Estado actualizado", "estado": estado})


@administracion_bp.post("/api/admin/desaparecidos/<int:reporte_id>/eliminar")
@jwt_required()
def eliminar_desaparecido(reporte_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        encontrado = conexion.execute(
            "SELECT admin_eliminar_desaparecido(%s)", (reporte_id,)
        ).fetchone()[0]
    if not encontrado:
        return jsonify({"error": "Reporte no encontrado"}), 404
    return jsonify({"mensaje": "Reporte retirado"})


# =====================================================================
# Parte 2: solicitudes (cartas), directorio, jornadas y emergencias.
# Requiere backend/migracion_administracion_contenidos.sql.
# =====================================================================

import io
from datetime import datetime, timedelta, timezone

from flask import send_file

ESTADOS_SOLICITUD = ("pendiente", "en_revision", "programada", "en_atencion", "atendida", "cancelada")
GRUPOS_DIRECTORIO = ("emergencias", "estado", "salud", "comunidad")
CATEGORIAS_JORNADA = ("limpieza", "salud", "solidaridad", "apoyo")
ALCANCES_EMERGENCIA = ("departamento", "municipio", "sector")
NIVELES_RIESGO = ("bajo", "medio", "alto", "critico")

TEXTOS_CARTA = {
    "categoria": {
        "alimentos": "Alimentos", "atencion_medica": "Atención médica", "alojamiento": "Alojamiento",
        "transporte": "Transporte", "ropa": "Ropa", "otra": "Otra",
    },
    "motivo": {
        "evaluar_danos": "Evaluar daños", "condiciones_vivienda": "Revisar condiciones de la vivienda",
        "riesgo_estructural": "Riesgo estructural", "encuesta_social": "Encuesta o caracterización del hogar",
        "otra": "Otro motivo",
    },
    "alcance": {"comunidad": "Comunidad o barrio", "familias": "Grupo de familias", "hogar": "Hogar"},
    "urgencia": {"baja": "Baja", "media": "Media", "alta": "Alta", "critica": "Crítica"},
    "franja": {"manana": "mañana (8 a. m. – 12 m.)", "tarde": "tarde (2 p. m. – 5 p. m.)", "cualquiera": "cualquier horario"},
    "estado": {
        "pendiente": "Pendiente", "en_revision": "En revisión", "programada": "Visita programada",
        "en_atencion": "En atención", "atendida": "Atendida", "cancelada": "Cancelada",
    },
}
COLUMNAS_SOLICITUD = (
    "id", "tipo", "alcance", "nombre_comunidad", "categoria", "motivo_visita",
    "fecha_visita_preferida", "franja_horaria", "urgencia", "descripcion",
    "personas_afectadas", "direccion", "latitud", "longitud", "nombre_contacto",
    "telefono_contacto", "adjunto_mime", "estado", "creada_en", "actualizada_en",
    "cuenta_email", "cuenta_nombre",
)
COLUMNAS_DIRECTORIO = ("id", "grupo", "nombre", "detalle", "telefono", "direccion", "web", "orden")
COLUMNAS_JORNADA = ("id", "nombre", "categoria", "descripcion", "fecha_inicio", "fecha_fin", "lugar",
                    "latitud", "longitud", "estado")
# Sin fecha_fin (jornadas anteriores a migracion_fin_jornadas.sql), una jornada
# se da por terminada 12 horas después de empezar.
DURACION_SIN_FIN = timedelta(hours=12)
# Las jornadas terminadas se siguen mostrando a la comunidad durante este tiempo.
MOSTRAR_TERMINADAS = timedelta(days=60)


def _iso(valor):
    return valor.isoformat() if hasattr(valor, "isoformat") else valor


def _coordenadas(datos):
    latitud, longitud = datos.get("latitud"), datos.get("longitud")
    if latitud in (None, "") and longitud in (None, ""):
        return True, None, None
    try:
        latitud, longitud = float(latitud), float(longitud)
    except (TypeError, ValueError):
        return False, None, None
    if not (-90 <= latitud <= 90 and -180 <= longitud <= 180):
        return False, None, None
    return True, latitud, longitud


def _solicitudes(conexion, estado=None):
    filas = conexion.execute(
        f"SELECT {', '.join(COLUMNAS_SOLICITUD)} FROM admin_listar_solicitudes(%s)", (estado,)
    ).fetchall()
    return [{k: _iso(v) for k, v in zip(COLUMNAS_SOLICITUD, fila)} for fila in filas]


# ---------- Solicitudes de ayuda ----------

@administracion_bp.get("/api/admin/solicitudes")
@jwt_required()
def listar_solicitudes_admin():
    usuario_id = _autoridad()
    estado = request.args.get("estado") or None
    if estado is not None and estado not in ESTADOS_SOLICITUD:
        return jsonify({"error": "Estado no válido"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        return jsonify(_solicitudes(conexion, estado))


@administracion_bp.post("/api/admin/solicitudes/<int:solicitud_id>/estado")
@jwt_required()
def cambiar_estado_solicitud(solicitud_id):
    usuario_id = _autoridad()
    estado = (request.get_json(silent=True) or {}).get("estado")
    if estado not in ESTADOS_SOLICITUD:
        return jsonify({"error": "Estado no válido"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        encontrada = conexion.execute(
            "SELECT admin_cambiar_estado_solicitud(%s, %s)", (solicitud_id, estado)
        ).fetchone()[0]
    if not encontrada:
        return jsonify({"error": "Solicitud no encontrada"}), 404
    return jsonify({"mensaje": "Estado actualizado", "estado": estado})


@administracion_bp.get("/api/admin/solicitudes/<int:solicitud_id>/adjunto")
@jwt_required()
def adjunto_solicitud_admin(solicitud_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            "SELECT adjunto, adjunto_mime FROM admin_adjunto_solicitud(%s)", (solicitud_id,)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Adjunto no encontrado"}), 404
    extension = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
                 "application/pdf": "pdf"}.get(fila[1], "bin")
    respuesta = send_file(io.BytesIO(bytes(fila[0])), mimetype=fila[1], as_attachment=True,
                          download_name=f"solicitud-{solicitud_id}-adjunto.{extension}")
    respuesta.headers["Cache-Control"] = "private, no-store"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta


def _fecha_larga(valor):
    meses = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
             "septiembre", "octubre", "noviembre", "diciembre")
    return f"{valor.day} de {meses[valor.month - 1]} de {valor.year}"


def _carta_pdf(s):
    """Carta formal en PDF con los datos de una solicitud."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.utils import simpleSplit
    from reportlab.pdfgen import canvas

    buffer = io.BytesIO()
    ancho, alto = A4
    margen = 64
    pdf = canvas.Canvas(buffer, pagesize=A4)
    pdf.setTitle(f"Solicitud SIGRE N.° {s['id']}")
    pdf.setAuthor("SIGRE")
    t = TEXTOS_CARTA
    es_visita = s["tipo"] == "visita"
    creada = datetime.fromisoformat(s["creada_en"]).astimezone(timezone(timedelta(hours=-5)))
    y = alto - margen

    def linea(texto, fuente="Helvetica", tamano=11, salto=16, sangria=0):
        nonlocal y
        for parte in simpleSplit(texto, fuente, tamano, ancho - 2 * margen - sangria) or [""]:
            if y < margen + 40:
                pdf.showPage()
                y = alto - margen
            pdf.setFont(fuente, tamano)
            pdf.drawString(margen + sangria, y, parte)
            y -= salto

    # Encabezado
    pdf.setFillColorRGB(0.106, 0.286, 0.396)
    pdf.rect(0, alto - 8, ancho, 8, stroke=0, fill=1)
    pdf.setFont("Helvetica-Bold", 16)
    pdf.drawString(margen, y, "SIGRE")
    pdf.setFont("Helvetica", 9)
    pdf.drawString(margen, y - 13, "Sistema Integral de Gestión y Respuesta ante Emergencias · Montería, Córdoba")
    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawRightString(ancho - margen, y, f"Radicado N.° SIGRE-{s['id']:05d}")
    pdf.setFont("Helvetica", 9)
    pdf.drawRightString(ancho - margen, y - 13, f"Estado: {t['estado'].get(s['estado'], s['estado'])}")
    pdf.setFillColorRGB(0, 0, 0)
    y -= 50

    linea(f"Montería, {_fecha_larga(creada)}")
    y -= 10
    linea("Señores")
    linea("Equipo de atención de emergencias", "Helvetica-Bold")
    linea("Montería, Córdoba")
    y -= 12

    asunto = (f"Solicitud de visita a vivienda – {t['motivo'].get(s['motivo_visita'], 'Visita')}"
              if es_visita else
              f"Solicitud de ayuda – {t['categoria'].get(s['categoria'], 'Ayuda')}")
    linea(f"Asunto: {asunto} (urgencia {t['urgencia'].get(s['urgencia'], s['urgencia']).lower()})",
          "Helvetica-Bold")
    y -= 10
    linea("Respetados señores:")
    y -= 6

    beneficiarios = t["alcance"].get(s["alcance"], s["alcance"])
    if s.get("nombre_comunidad"):
        beneficiarios += f" ({s['nombre_comunidad']})"
    a_quien = {"comunidad": "la comunidad", "familias": "un grupo de familias", "hogar": "su hogar"}.get(s["alcance"], "")
    if s.get("nombre_comunidad"):
        a_quien += f" de {s['nombre_comunidad']}"
    personas = s["personas_afectadas"]
    intro = (
        f"Por medio de la presente, {s['nombre_contacto']} solicita "
        f"{'una visita del equipo a la vivienda ubicada en' if es_visita else 'apoyo para'} "
        f"{s['direccion'] if es_visita else a_quien}, "
        + (f"en beneficio de {a_quien}, " if es_visita else f"en {s['direccion']}, ")
        + f"situación que afecta a {personas} {'persona' if personas == 1 else 'personas'}."
    )
    linea(intro, salto=15)
    y -= 6
    linea("Descripción de la situación, en palabras del solicitante:", "Helvetica-Bold")
    linea(s["descripcion"], "Helvetica-Oblique", 11, 15, sangria=12)
    y -= 8

    linea("Datos de la solicitud", "Helvetica-Bold")
    datos = [
        ("Tipo", "Visita a vivienda" if es_visita else "Solicitud de ayuda"),
        ("Motivo" if es_visita else "Categoría",
         t["motivo"].get(s["motivo_visita"]) if es_visita else t["categoria"].get(s["categoria"])),
        ("Urgencia", t["urgencia"].get(s["urgencia"])),
        ("Beneficiarios", beneficiarios),
        ("Personas", str(personas)),
        ("Dirección o sector", s["direccion"]),
    ]
    if s.get("latitud") is not None:
        datos.append(("Ubicación", f"{s['latitud']:.6f}, {s['longitud']:.6f} "
                                   f"(google.com/maps?q={s['latitud']:.6f},{s['longitud']:.6f})"))
    if es_visita and s.get("fecha_visita_preferida"):
        fecha = datetime.fromisoformat(s["fecha_visita_preferida"])
        datos.append(("Fecha preferida", f"{_fecha_larga(fecha)}, en la {t['franja'].get(s['franja_horaria'], '')}"))
    datos += [
        ("Contacto", f"{s['nombre_contacto']} · Tel. {s['telefono_contacto']}"),
        ("Cuenta SIGRE", s["cuenta_email"]),
        ("Adjunto", "Sí (se descarga por separado desde el panel)" if s.get("adjunto_mime") else "No"),
        ("Recibida", creada.strftime("%d/%m/%Y %I:%M %p")),
    ]
    for etiqueta, valor in datos:
        if y < margen + 40:
            pdf.showPage()
            y = alto - margen
        pdf.setFont("Helvetica-Bold", 10)
        pdf.drawString(margen + 12, y, f"{etiqueta}:")
        partes = simpleSplit(str(valor or "—"), "Helvetica", 10, ancho - 2 * margen - 140)
        for i, parte in enumerate(partes or ["—"]):
            pdf.setFont("Helvetica", 10)
            pdf.drawString(margen + 140, y, parte)
            y -= 14
        y -= 2

    y -= 10
    linea("El solicitante autorizó que esta información se comparta con el equipo responsable "
          "de atender la solicitud.", "Helvetica", 10, 14)
    y -= 14
    linea("Atentamente,")
    y -= 24
    linea(s["nombre_contacto"], "Helvetica-Bold")
    linea(f"Tel. {s['telefono_contacto']} · {s['cuenta_email']}", "Helvetica", 10)

    pdf.setFont("Helvetica", 8)
    pdf.setFillColorRGB(0.4, 0.44, 0.52)
    pdf.drawString(margen, 30, f"Documento generado por SIGRE el {_fecha_larga(datetime.now())}. "
                               "Contiene datos personales: compártelo solo con quien vaya a atender la solicitud.")
    pdf.showPage()
    pdf.save()
    buffer.seek(0)
    return buffer


@administracion_bp.get("/api/admin/solicitudes/<int:solicitud_id>/carta")
@jwt_required()
def carta_solicitud(solicitud_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        solicitud = next((s for s in _solicitudes(conexion) if s["id"] == solicitud_id), None)
    if solicitud is None:
        return jsonify({"error": "Solicitud no encontrada"}), 404
    respuesta = send_file(_carta_pdf(solicitud), mimetype="application/pdf", as_attachment=True,
                          download_name=f"SIGRE-solicitud-{solicitud_id:05d}.pdf")
    respuesta.headers["Cache-Control"] = "private, no-store"
    return respuesta


# ---------- Directorio de entidades ----------

def _validar_directorio(datos):
    if not isinstance(datos, dict):
        return None, "Envía los datos como JSON"
    grupo = datos.get("grupo")
    if grupo not in GRUPOS_DIRECTORIO:
        return None, "Elige el grupo de la entidad"
    ok, nombre = _texto(datos.get("nombre"), 2, 120)
    if not ok:
        return None, "Escribe el nombre de la entidad (entre 2 y 120 caracteres)"
    ok, detalle = _texto(datos.get("detalle"), 1, 300, opcional=True)
    if not ok:
        return None, "El detalle puede tener máximo 300 caracteres"
    ok, telefono = _texto(datos.get("telefono"), 3, 20, opcional=True)
    if not ok or (telefono and (not re.fullmatch(r"\+?[0-9 ()-]{3,20}", telefono)
                                or len(re.sub(r"\D", "", telefono)) < 3)):
        return None, "Escribe un teléfono válido (solo números, espacios o guiones) o déjalo vacío"
    ok, direccion = _texto(datos.get("direccion"), 3, 200, opcional=True)
    if not ok:
        return None, "La dirección debe tener entre 3 y 200 caracteres"
    ok, web = _texto(datos.get("web"), 10, 300, opcional=True)
    if not ok or (web and not re.fullmatch(r"https://[^\s<>\"']+", web)):
        return None, "El sitio web debe empezar por https://"
    if not (telefono or direccion or web):
        return None, "Agrega al menos un teléfono, una dirección o un sitio web"
    orden = _entero(datos.get("orden", 100), 0, 10000)
    if orden is None:
        return None, "El orden debe ser un número entre 0 y 10000"
    return {"grupo": grupo, "nombre": nombre, "detalle": detalle, "telefono": telefono,
            "direccion": direccion, "web": web, "orden": orden}, None


@administracion_bp.get("/api/directorio")
def listar_directorio():
    with obtener_conexion() as conexion:
        filas = conexion.execute(
            f"SELECT {', '.join(COLUMNAS_DIRECTORIO)}, "
            "foto IS NOT NULL, extract(epoch FROM foto_actualizada)::BIGINT "
            "FROM directorio_entidades ORDER BY orden, nombre"
        ).fetchall()
    entidades = []
    for fila in filas:
        entidad = dict(zip(COLUMNAS_DIRECTORIO, fila))
        entidad["tiene_foto"] = fila[-2]
        entidad["foto_version"] = fila[-1]   # cambia cada vez que se sube otra foto
        entidades.append(entidad)
    return jsonify(entidades)



@administracion_bp.post("/api/admin/directorio")
@administracion_bp.post("/api/admin/directorio/<int:entidad_id>")
@jwt_required()
def guardar_entidad(entidad_id=None):
    usuario_id = _autoridad()
    entidad, error = _validar_directorio(request.get_json(silent=True))
    if error:
        return jsonify({"error": error}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        if entidad_id is None:
            fila = conexion.execute(
                f"""INSERT INTO directorio_entidades (grupo, nombre, detalle, telefono, direccion, web, orden)
                    VALUES (%(grupo)s, %(nombre)s, %(detalle)s, %(telefono)s, %(direccion)s, %(web)s, %(orden)s)
                    RETURNING {', '.join(COLUMNAS_DIRECTORIO)}""", entidad).fetchone()
        else:
            fila = conexion.execute(
                f"""UPDATE directorio_entidades
                    SET grupo = %(grupo)s, nombre = %(nombre)s, detalle = %(detalle)s, telefono = %(telefono)s,
                        direccion = %(direccion)s, web = %(web)s, orden = %(orden)s, actualizado_en = NOW()
                    WHERE id = %(id)s RETURNING {', '.join(COLUMNAS_DIRECTORIO)}""",
                dict(entidad, id=entidad_id)).fetchone()
    if fila is None:
        return jsonify({"error": "Entidad no encontrada"}), 404
    return jsonify(dict(zip(COLUMNAS_DIRECTORIO, fila))), 201 if entidad_id is None else 200


@administracion_bp.post("/api/admin/directorio/<int:entidad_id>/eliminar")
@jwt_required()
def eliminar_entidad(entidad_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            "DELETE FROM directorio_entidades WHERE id = %s RETURNING id", (entidad_id,)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Entidad no encontrada"}), 404
    return jsonify({"mensaje": "Entidad eliminada"})

# ---------- Directorio: foto o logo ----------

LIMITE_FOTO_DIRECTORIO = 3 * 1024 * 1024   # lo máximo que se acepta al subir
LADO_FOTO_DIRECTORIO = 256                 # se guarda cuadrada de 256 x 256 px


def _tipo_imagen(contenido):
    """Reconoce la imagen por sus primeros bytes, no por el nombre del archivo."""
    if contenido.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if contenido.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if contenido[:4] == b"RIFF" and contenido[8:12] == b"WEBP":
        return "image/webp"
    return None

@administracion_bp.post("/api/admin/directorio/<int:entidad_id>/foto")
@jwt_required()
def subir_foto_entidad(entidad_id):
    usuario_id = _autoridad()
    archivo = request.files.get("foto")
    if archivo is None or not archivo.filename:
        return jsonify({"error": "Selecciona una foto"}), 400
    contenido = archivo.read(LIMITE_FOTO_DIRECTORIO + 1)
    if not contenido or len(contenido) > LIMITE_FOTO_DIRECTORIO:
        return jsonify({"error": "La foto debe pesar máximo 3 MB"}), 400
    if _tipo_imagen(contenido) is None:
        return jsonify({"error": "Usa una foto JPG, PNG o WEBP"}), 400

    # Se achica y se recorta cuadrada para que pese poco y se vea bien en círculo.
    try:
        with Image.open(io.BytesIO(contenido)) as original:
            imagen = ImageOps.exif_transpose(original)   # respeta la orientación de fotos de celular
            if imagen.mode in ("RGBA", "LA", "P"):
                # Los PNG transparentes quedan sobre fondo blanco.
                imagen = imagen.convert("RGBA")
                fondo = Image.new("RGB", imagen.size, "white")
                fondo.paste(imagen, mask=imagen.split()[-1])
                imagen = fondo
            else:
                imagen = imagen.convert("RGB")
            imagen = ImageOps.fit(imagen, (LADO_FOTO_DIRECTORIO, LADO_FOTO_DIRECTORIO))
            salida = io.BytesIO()
            imagen.save(salida, "JPEG", quality=85)
    except Exception:
        return jsonify({"error": "No se pudo leer la imagen. Prueba con otra foto."}), 400

    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            """UPDATE directorio_entidades
               SET foto = %s, foto_mime = 'image/jpeg', foto_actualizada = NOW()
               WHERE id = %s
               RETURNING id""",
            (salida.getvalue(), entidad_id)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Entidad no encontrada"}), 404
    return jsonify({"mensaje": "Foto guardada"})

@administracion_bp.post("/api/admin/directorio/<int:entidad_id>/foto/eliminar")
@jwt_required()
def quitar_foto_entidad(entidad_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            """UPDATE directorio_entidades
               SET foto = NULL, foto_mime = NULL, foto_actualizada = NOW()
               WHERE id = %s
               RETURNING id""",
            (entidad_id,)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Entidad no encontrada"}), 404
    return jsonify({"mensaje": "Foto eliminada"})


@administracion_bp.get("/api/directorio/<int:entidad_id>/foto")
def foto_entidad(entidad_id):
    with obtener_conexion() as conexion:
        fila = conexion.execute(
            "SELECT foto, foto_mime FROM directorio_entidades WHERE id = %s AND foto IS NOT NULL",
            (entidad_id,)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Foto no encontrada"}), 404
    respuesta = send_file(io.BytesIO(bytes(fila[0])), mimetype=fila[1])
    respuesta.headers["Cache-Control"] = "public, max-age=86400"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta

# ---------- Jornadas comunitarias ----------

def _usuario_opcional():
    """Id de la cuenta si la petición trae un token válido; si no, None."""
    try:
        verify_jwt_in_request(optional=True)
        identidad = get_jwt_identity()
        return int(identidad) if identidad is not None else None
    except Exception:
        return None


def _conexion_usuario(usuario_id):
    conexion = obtener_conexion()
    if usuario_id is not None:
        conexion.execute("SELECT set_config('app.user_id', %s, true)", (str(usuario_id),))
    return conexion


def _momento_jornada(jornada, ahora):
    """'proxima', 'en_curso' o 'finalizada', según las fechas de inicio y fin."""
    fin = jornada["fecha_fin"] or jornada["fecha_inicio"] + DURACION_SIN_FIN
    if ahora < jornada["fecha_inicio"]:
        return "proxima"
    return "en_curso" if ahora < fin else "finalizada"


@administracion_bp.get("/api/jornadas")
def listar_jornadas():
    # Por defecto, las publicadas: primero las próximas y en curso, y debajo las
    # finalizadas de los últimos 60 días. ?todas=1 incluye canceladas (para el panel).
    todas = request.args.get("todas") == "1"
    condicion = "" if todas else (
        "WHERE estado = 'publicada' "
        "AND coalesce(fecha_fin, fecha_inicio + %(sin_fin)s) >= NOW() - %(mostrar)s"
    )
    with _conexion_usuario(_usuario_opcional()) as conexion:
        filas = conexion.execute(
            f"SELECT {', '.join(COLUMNAS_JORNADA)} FROM jornadas {condicion} "
            f"ORDER BY fecha_inicio {'DESC' if todas else 'ASC'} LIMIT 200",
            None if todas else {"sin_fin": DURACION_SIN_FIN, "mostrar": MOSTRAR_TERMINADAS}
        ).fetchall()
        ahora = datetime.now(timezone.utc)
        jornadas = []
        for fila in filas:
            jornada = dict(zip(COLUMNAS_JORNADA, fila))
            jornada["momento"] = _momento_jornada(jornada, ahora)
            jornadas.append({k: _iso(v) for k, v in jornada.items()})
        if not todas:
            # Próximas y en curso por fecha; las finalizadas al final, la más reciente primero.
            activas = [j for j in jornadas if j["momento"] != "finalizada"]
            finalizadas = [j for j in jornadas if j["momento"] == "finalizada"]
            jornadas = activas + finalizadas[::-1]
        participacion = {}
        try:
            # Punto de guardado: si falta la migración, la lista sigue funcionando.
            with conexion.transaction():
                participacion = {
                    fila[0]: fila[1:]
                    for fila in conexion.execute(
                        "SELECT jornada_id, total, vista_previa, participo FROM jornadas_participacion(%s)",
                        ([j["id"] for j in jornadas],)
                    ).fetchall()
                }
        except psycopg.errors.UndefinedFunction:
            registro.warning("Falta aplicar backend/migracion_participacion_jornadas.sql")
    for jornada in jornadas:
        total, vista_previa, participo = participacion.get(jornada["id"], (0, [], False))
        jornada.update(participantes=total, vista_previa=vista_previa, participo=participo)
    return jsonify(jornadas)


@administracion_bp.get("/api/jornadas/estadisticas")
def estadisticas_jornadas():
    with obtener_conexion() as conexion:
        filas = conexion.execute(
            "SELECT categoria, jornadas, participantes, promedio FROM jornadas_estadisticas_categoria()"
        ).fetchall()
    return jsonify([
        {"categoria": f[0], "jornadas": f[1], "participantes": f[2], "promedio": float(f[3])}
        for f in filas
    ])


@administracion_bp.post("/api/jornadas/<int:jornada_id>/participar")
@jwt_required()
def participar_jornada(jornada_id):
    usuario_id = _usuario_opcional()
    if usuario_id is None:
        return jsonify({"error": "Inicia sesión para participar"}), 401
    participar = (request.get_json(silent=True) or {}).get("participar")
    if not isinstance(participar, bool):
        return jsonify({"error": "Indica si quieres participar o no"}), 400
    with _conexion_usuario(usuario_id) as conexion:
        total = conexion.execute(
            "SELECT jornada_participar(%s, %s)", (jornada_id, participar)
        ).fetchone()[0]
    return jsonify({
        "participo": participar,
        "participantes": total,
        "mensaje": "¡Te inscribiste en la jornada!" if participar else "Cancelaste tu participación",
    })


@administracion_bp.get("/api/jornadas/<int:jornada_id>/participantes")
@jwt_required()
def participantes_jornada(jornada_id):
    usuario_id = _usuario_opcional()
    if usuario_id is None:
        return jsonify({"error": "Inicia sesión para ver quiénes participan"}), 401
    with _conexion_usuario(usuario_id) as conexion:
        filas = conexion.execute(
            "SELECT nombre, animal, email, telefono, inscrito_en, es_yo FROM jornada_participantes(%s)",
            (jornada_id,)
        ).fetchall()
    return jsonify([
        {"nombre": f[0], "animal": f[1], "email": f[2], "telefono": f[3],
         "inscrito_en": f[4].isoformat(), "es_yo": f[5]}
        for f in filas
    ])


def _validar_jornada(datos):
    """Devuelve (jornada, None) o (None, mensaje de error)."""
    if not isinstance(datos, dict):
        return None, "Envía los datos como JSON"
    ok, nombre = _texto(datos.get("nombre"), 3, 120)
    if not ok:
        return None, "Escribe el nombre de la jornada (entre 3 y 120 caracteres)"
    categoria = datos.get("categoria")
    if categoria not in CATEGORIAS_JORNADA:
        return None, "Elige una categoría válida"
    ok, descripcion = _texto(datos.get("descripcion"), 10, 600)
    if not ok:
        return None, "Describe la jornada (entre 10 y 600 caracteres)"
    ok, lugar = _texto(datos.get("lugar"), 3, 200)
    if not ok:
        return None, "Escribe el lugar (entre 3 y 200 caracteres)"
    try:
        # El formulario envía la hora local de Colombia (UTC-5) sin zona.
        fecha = datetime.fromisoformat(str(datos.get("fecha_inicio")))
        if fecha.tzinfo is None:
            fecha = fecha.replace(tzinfo=timezone(timedelta(hours=-5)))
    except ValueError:
        return None, "Elige la fecha y la hora de la jornada"
    ahora = datetime.now(timezone.utc)
    if not ahora - timedelta(hours=1) <= fecha <= ahora + timedelta(days=366):
        return None, "La fecha debe estar entre hoy y el próximo año"

    # Fin opcional: sin ella, la jornada se da por terminada 12 horas después de empezar.
    fecha_fin = None
    if datos.get("fecha_fin"):
        try:
            fecha_fin = datetime.fromisoformat(str(datos.get("fecha_fin")))
            if fecha_fin.tzinfo is None:
                fecha_fin = fecha_fin.replace(tzinfo=timezone(timedelta(hours=-5)))
        except ValueError:
            return None, "La fecha de fin no es válida"
        if fecha_fin <= fecha:
            return None, "La fecha de fin debe ser después del inicio"
        if fecha_fin - fecha > timedelta(days=7):
            return None, "Una jornada puede durar máximo 7 días"

    ok, latitud, longitud = _coordenadas(datos)
    if not ok:
        return None, "La ubicación en el mapa no es válida"
    return {"nombre": nombre, "categoria": categoria, "descripcion": descripcion,
            "fecha_inicio": fecha, "fecha_fin": fecha_fin, "lugar": lugar,
            "latitud": latitud, "longitud": longitud}, None


@administracion_bp.post("/api/admin/jornadas")
@administracion_bp.post("/api/admin/jornadas/<int:jornada_id>")
@jwt_required()
def guardar_jornada(jornada_id=None):
    usuario_id = _autoridad()
    jornada, error = _validar_jornada(request.get_json(silent=True))
    if error:
        return jsonify({"error": error}), 400

    with _conexion_autoridad(usuario_id) as conexion:
        if jornada_id is None:
            fila = conexion.execute(
                f"""INSERT INTO jornadas (nombre, categoria, descripcion, fecha_inicio, fecha_fin, lugar,
                                          latitud, longitud, creada_por)
                    VALUES (%(nombre)s, %(categoria)s, %(descripcion)s, %(fecha_inicio)s, %(fecha_fin)s,
                            %(lugar)s, %(latitud)s, %(longitud)s, %(creada_por)s)
                    RETURNING {', '.join(COLUMNAS_JORNADA)}""",
                dict(jornada, creada_por=usuario_id)
            ).fetchone()
        else:
            fila = conexion.execute(
                f"""UPDATE jornadas
                    SET nombre = %(nombre)s, categoria = %(categoria)s, descripcion = %(descripcion)s,
                        fecha_inicio = %(fecha_inicio)s, fecha_fin = %(fecha_fin)s, lugar = %(lugar)s,
                        latitud = %(latitud)s, longitud = %(longitud)s
                    WHERE id = %(id)s
                    RETURNING {', '.join(COLUMNAS_JORNADA)}""",
                dict(jornada, id=jornada_id)
            ).fetchone()
    if fila is None:
        return jsonify({"error": "Jornada no encontrada"}), 404
    return jsonify({k: _iso(v) for k, v in zip(COLUMNAS_JORNADA, fila)}), 201 if jornada_id is None else 200


@administracion_bp.post("/api/admin/jornadas/<int:jornada_id>/estado")
@jwt_required()
def cambiar_estado_jornada(jornada_id):
    usuario_id = _autoridad()
    estado = (request.get_json(silent=True) or {}).get("estado")
    if estado not in ("publicada", "cancelada"):
        return jsonify({"error": "Estado no válido"}), 400
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute(
            "UPDATE jornadas SET estado = %s WHERE id = %s RETURNING id", (estado, jornada_id)
        ).fetchone()
    if fila is None:
        return jsonify({"error": "Jornada no encontrada"}), 404
    return jsonify({"mensaje": "Jornada actualizada", "estado": estado})


@administracion_bp.post("/api/admin/jornadas/<int:jornada_id>/eliminar")
@jwt_required()
def eliminar_jornada(jornada_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        fila = conexion.execute("DELETE FROM jornadas WHERE id = %s RETURNING id", (jornada_id,)).fetchone()
    if fila is None:
        return jsonify({"error": "Jornada no encontrada"}), 404
    return jsonify({"mensaje": "Jornada eliminada"})


# ---------- Emergencias ----------

COLUMNAS_EMERGENCIA_PUBLICA = ("id", "tipo", "descripcion", "alcance", "departamento",
                               "municipio", "sector", "nivel_riesgo", "creada_en")
COLUMNAS_EMERGENCIA_ADMIN = COLUMNAS_EMERGENCIA_PUBLICA[:-1] + ("estado", "creada_en", "finalizada_en")


@administracion_bp.get("/api/emergencias/activa")
def emergencia_activa():
    with obtener_conexion() as conexion:
        fila = conexion.execute(
            f"SELECT {', '.join(COLUMNAS_EMERGENCIA_PUBLICA)} FROM emergencia_activa_publica()"
        ).fetchone()
    if fila is None:
        return jsonify({"activa": False})
    return jsonify(dict({k: _iso(v) for k, v in zip(COLUMNAS_EMERGENCIA_PUBLICA, fila)}, activa=True))


@administracion_bp.get("/api/admin/emergencias")
@jwt_required()
def listar_emergencias_admin():
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        filas = conexion.execute(
            f"SELECT {', '.join(COLUMNAS_EMERGENCIA_ADMIN)} FROM admin_listar_emergencias()"
        ).fetchall()
    return jsonify([{k: _iso(v) for k, v in zip(COLUMNAS_EMERGENCIA_ADMIN, fila)} for fila in filas])


@administracion_bp.post("/api/admin/emergencias")
@jwt_required()
def crear_emergencia():
    usuario_id = _autoridad()
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400
    ok, tipo = _texto(datos.get("tipo"), 3, 80)
    if not ok:
        return jsonify({"error": "Escribe el tipo de emergencia (ej. Inundación)"}), 400
    ok, descripcion = _texto(datos.get("descripcion"), 10, 600)
    if not ok:
        return jsonify({"error": "Describe la emergencia (entre 10 y 600 caracteres)"}), 400
    alcance = datos.get("alcance")
    if alcance not in ALCANCES_EMERGENCIA:
        return jsonify({"error": "Elige el alcance: departamento, municipio o sector"}), 400
    nivel = datos.get("nivel_riesgo")
    if nivel not in NIVELES_RIESGO:
        return jsonify({"error": "Elige el nivel de riesgo"}), 400
    ok, departamento = _texto(datos.get("departamento") or "Córdoba", 3, 80)
    ok_m, municipio = _texto(datos.get("municipio"), 2, 80, opcional=True)
    ok_s, sector = _texto(datos.get("sector"), 2, 120, opcional=True)
    if not (ok and ok_m and ok_s):
        return jsonify({"error": "Revisa el departamento, municipio y sector"}), 400
    if alcance in ("municipio", "sector") and not municipio:
        return jsonify({"error": "Escribe el municipio afectado"}), 400
    if alcance == "sector" and not sector:
        return jsonify({"error": "Escribe el sector o barrio afectado"}), 400
    ok, latitud, longitud = _coordenadas(datos)
    if not ok:
        return jsonify({"error": "La ubicación en el mapa no es válida"}), 400

    with _conexion_autoridad(usuario_id) as conexion:
        nuevo_id = conexion.execute(
            "SELECT admin_crear_emergencia(%s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (tipo, descripcion, alcance, departamento, municipio, sector, nivel, latitud, longitud)
        ).fetchone()[0]
    return jsonify({"mensaje": "Emergencia publicada", "id": nuevo_id}), 201


@administracion_bp.post("/api/admin/emergencias/<int:emergencia_id>/finalizar")
@jwt_required()
def finalizar_emergencia(emergencia_id):
    usuario_id = _autoridad()
    with _conexion_autoridad(usuario_id) as conexion:
        finalizada = conexion.execute(
            "SELECT admin_finalizar_emergencia(%s)", (emergencia_id,)
        ).fetchone()[0]
    if not finalizada:
        return jsonify({"error": "La emergencia no existe o ya estaba finalizada"}), 404
    return jsonify({"mensaje": "Emergencia finalizada"})
