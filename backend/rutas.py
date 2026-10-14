"""SIGRE · Rutas de evacuación.

Lleva a Flask el algoritmo de rutas_eva_corregido.ipynb:
- Las redes de calles de Montería se preparan una vez en el computador de
  desarrollo (python rutas.py) y se guardan livianas en backend/datos_rutas/
  (*.json.gz). El servidor solo las lee: no necesita osmnx, geopandas ni
  scikit-learn, que ocupan cientos de MB de memoria.
- Penaliza los tramos que cruzan zonas de riesgo y compara la ruta más
  corta con la ruta más segura.
- Busca direcciones con Nominatim (OpenStreetMap), limitado a Montería.
- Guarda las rutas de cada cuenta (requiere backend/migracion_rutas.sql).

Las zonas son aproximaciones académicas: no son cartografía oficial.
"""

import gzip
import json
import logging
import math
import os
import threading
import unicodedata
from functools import lru_cache
from pathlib import Path

import psycopg
import requests
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from database import obtener_conexion

# En equipos con poca RAM, OpenBLAS (usado por numpy/scikit-learn) reserva memoria
# para muchos hilos y falla con "Memory allocation still failed". Con un hilo basta.
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

rutas_bp = Blueprint("rutas", __name__)
registro = logging.getLogger(__name__)

CIUDAD = "Montería, Córdoba, Colombia"
FACTOR_RIESGO = 100
METROS_POR_MINUTO_A_PIE = 75  # caminando a 4,5 km/h
DISTANCIA_MAXIMA_A_CALLE_M = 1500
MAXIMO_PUNTOS_GEOMETRIA = 5000

# Límites aproximados de Montería para validar puntos y búsquedas.
LIMITES = {"lat_min": 8.60, "lat_max": 8.95, "lon_min": -76.05, "lon_max": -75.70}

RAIZ_PROYECTO = Path(__file__).resolve().parent.parent
CARPETA_DATOS = Path(__file__).resolve().parent / "datos_rutas"

# Redes de OpenStreetMap. Carro y moto comparten la red vial (respeta los sentidos de
# las calles); el tiempo se estima con los límites de velocidad de OSM, sin tráfico.
# archivo: red completa de OpenStreetMap (solo en desarrollo, no se sube).
# liviano: lo que usa el servidor (esquinas, largo, tiempo, riesgo y trazado).
REDES = {
    "peatonal": {"tipo_osm": "walk",
                 "archivo": CARPETA_DATOS / "monteria_peatonal.graphml",
                 "liviano": CARPETA_DATOS / "monteria_peatonal.json.gz"},
    "vehicular": {"tipo_osm": "drive",
                  "archivo": CARPETA_DATOS / "monteria_vehicular.graphml",
                  "liviano": CARPETA_DATOS / "monteria_vehicular.json.gz"},
}
MODOS = {"pie": "peatonal", "carro": "vehicular", "moto": "vehicular"}

# Mismas zonas del notebook (longitud, latitud). La última es de demostración.
ZONAS = [
    {
        "id": "rio_sinu",
        "nombre": "Margen izquierda del río Sinú",
        "descripcion": "El Dorado, Vallejo, El Poblado y barrios cercanos.",
        "demo": False,
        "coordenadas": [(-75.895, 8.740), (-75.875, 8.740), (-75.875, 8.755), (-75.895, 8.755)],
    },
    {
        "id": "sur",
        "nombre": "Barrios del sur",
        "descripcion": "El Tambo, El Rosario, Alboraya y barrios cercanos.",
        "demo": False,
        "coordenadas": [(-75.870, 8.740), (-75.850, 8.740), (-75.850, 8.755), (-75.870, 8.755)],
    },
    {
        "id": "humedales",
        "nombre": "Zona de humedales",
        "descripcion": "Nuevo Milenio, Playa Brígida y alrededores.",
        "demo": False,
        "coordenadas": [(-75.885, 8.780), (-75.870, 8.780), (-75.870, 8.790), (-75.885, 8.790)],
    },
    {
        "id": "demo_centro",
        "nombre": "Zona de demostración",
        "descripcion": "No es un riesgo real: se usa para mostrar cómo la ruta segura se desvía.",
        "demo": True,
        "coordenadas": [(-75.876, 8.756), (-75.866, 8.756), (-75.866, 8.764), (-75.876, 8.764)],
    },
]

_estado = {red: {"grafo": None, "cargando": False, "error": None} for red in REDES}
_candado = threading.Lock()


# ---------- Redes de calles ----------

def construir_red_liviana(red):
    """Descarga o abre la red de OpenStreetMap, marca los tramos en zonas de
    riesgo y guarda la versión liviana. Necesita osmnx (solo en desarrollo)."""
    import osmnx as ox
    from shapely.geometry import LineString, Polygon
    from shapely.ops import unary_union
    from shapely.prepared import prep

    ox.settings.use_cache = True
    ox.settings.cache_folder = str(RAIZ_PROYECTO / "cache")
    ox.settings.log_console = False

    archivo = REDES[red]["archivo"]
    if archivo.exists():
        grafo = ox.load_graphml(archivo)
    else:
        grafo = ox.graph_from_place(CIUDAD, network_type=REDES[red]["tipo_osm"], simplify=True)
        if red == "vehicular":
            grafo = ox.routing.add_edge_speeds(grafo)
            grafo = ox.routing.add_edge_travel_times(grafo)
        CARPETA_DATOS.mkdir(exist_ok=True)
        ox.save_graphml(grafo, archivo)

    reales = prep(unary_union([Polygon(z["coordenadas"]) for z in ZONAS if not z["demo"]]))
    demo = prep(unary_union([Polygon(z["coordenadas"]) for z in ZONAS if z["demo"]]))

    nodos = [[nodo, round(d["x"], 6), round(d["y"], 6)] for nodo, d in grafo.nodes(data=True)]
    aristas = []
    for u, v, datos in grafo.edges(data=True):
        geometria = datos.get("geometry")
        linea = geometria or LineString([
            (grafo.nodes[u]["x"], grafo.nodes[u]["y"]),
            (grafo.nodes[v]["x"], grafo.nodes[v]["y"]),
        ])
        trazado = ([[round(x, 6), round(y, 6)] for x, y in geometria.coords]
                   if geometria is not None else None)
        aristas.append([
            u, v,
            round(float(datos["length"]), 2),
            round(float(datos.get("travel_time", 0.0)), 2),
            bool(reales.intersects(linea)),
            bool(demo.intersects(linea)),
            trazado,
        ])

    with gzip.open(REDES[red]["liviano"], "wt", encoding="utf-8") as salida:
        json.dump({"nodos": nodos, "aristas": aristas}, salida, separators=(",", ":"))
    return REDES[red]["liviano"]


def _preparar_grafo(red):
    estado = _estado[red]
    try:
        import networkx as nx

        liviano = REDES[red]["liviano"]
        if not liviano.exists():
            # En desarrollo se genera; en el servidor debe venir en el repositorio.
            construir_red_liviana(red)

        with gzip.open(liviano, "rt", encoding="utf-8") as entrada:
            datos = json.load(entrada)

        grafo = nx.MultiDiGraph()
        for nodo, x, y in datos["nodos"]:
            grafo.add_node(nodo, x=x, y=y)
        for u, v, largo, tiempo, riesgo_real, riesgo_demo, trazado in datos["aristas"]:
            atributos = {"length": largo, "travel_time": tiempo,
                         "riesgo_real": riesgo_real, "riesgo_demo": riesgo_demo}
            if trazado:
                atributos["trazado"] = [tuple(punto) for punto in trazado]
            grafo.add_edge(u, v, **atributos)
        del datos

        # Coordenadas en listas para buscar rápido la esquina más cercana.
        estado["ids"] = list(grafo.nodes)
        estado["xs"] = [grafo.nodes[n]["x"] for n in estado["ids"]]
        estado["ys"] = [grafo.nodes[n]["y"] for n in estado["ids"]]
        estado["grafo"] = grafo
    except Exception:
        registro.exception("No se pudo preparar la red %s de Montería", red)
        estado["error"] = (
            "No se pudo preparar el mapa de calles. Avísale al equipo de SIGRE: "
            "falta el archivo de la red de calles en el servidor."
        )
    finally:
        estado["cargando"] = False


def _metros(lat1, lon1, lat2, lon2):
    """Distancia en metros entre dos puntos (fórmula de haversine)."""
    radio = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radio * math.asin(math.sqrt(a))


def _nodo_mas_cercano(estado, lat, lon):
    """Esquina de la red más cercana al punto. Devuelve (nodo, metros)."""
    # Dentro de una ciudad, comparar en un plano con la longitud corregida por
    # la latitud da el mismo vecino que la distancia real.
    escala = math.cos(math.radians(lat)) ** 2
    xs, ys = estado["xs"], estado["ys"]
    mejor = min(range(len(xs)), key=lambda i: (ys[i] - lat) ** 2 + escala * (xs[i] - lon) ** 2)
    return estado["ids"][mejor], _metros(lat, lon, ys[mejor], xs[mejor])


def _iniciar_carga(red):
    estado = _estado[red]
    with _candado:
        if estado["grafo"] is None and not estado["cargando"] and estado["error"] is None:
            estado["cargando"] = True
            threading.Thread(target=_preparar_grafo, args=(red,), daemon=True).start()


def _modo_valido(valor):
    return valor if valor in MODOS else None


def _punto_valido(punto):
    if not isinstance(punto, dict):
        return None
    try:
        lat = float(punto.get("lat"))
        lon = float(punto.get("lon"))
    except (TypeError, ValueError):
        return None
    if not (LIMITES["lat_min"] <= lat <= LIMITES["lat_max"]
            and LIMITES["lon_min"] <= lon <= LIMITES["lon_max"]):
        return None
    return lat, lon


def _peso(incluir_riesgo, incluir_demo):
    # Ruta segura = distancia + riesgo en conjunto: cada metro dentro de una zona
    # de riesgo cuenta como FACTOR_RIESGO metros, así que solo la cruza si no hay
    # una alternativa razonable.
    def calcular(_u, _v, aristas):
        return min(
            datos["length"] * (
                FACTOR_RIESGO
                if incluir_riesgo and (datos["riesgo_real"] or (incluir_demo and datos["riesgo_demo"]))
                else 1
            )
            for datos in aristas.values()
        )
    return calcular


def _describir_ruta(grafo, nodos, peso, red):
    coordenadas = []
    distancia = metros_riesgo = metros_demo = segundos = 0.0

    for u, v in zip(nodos[:-1], nodos[1:]):
        aristas = grafo[u][v]
        clave = min(aristas, key=lambda k: peso(u, v, {k: aristas[k]}))
        datos = aristas[clave]
        largo = datos["length"]
        distancia += largo
        segundos += datos.get("travel_time", 0.0)
        if datos["riesgo_real"]:
            metros_riesgo += largo
        if datos["riesgo_demo"]:
            metros_demo += largo

        if "trazado" in datos:
            tramo = [(lat, lon) for lon, lat in datos["trazado"]]
            # La geometría puede venir en sentido contrario al recorrido.
            inicio = (grafo.nodes[u]["y"], grafo.nodes[u]["x"])
            if (tramo[0][0] - inicio[0]) ** 2 + (tramo[0][1] - inicio[1]) ** 2 > \
               (tramo[-1][0] - inicio[0]) ** 2 + (tramo[-1][1] - inicio[1]) ** 2:
                tramo.reverse()
        else:
            tramo = [(grafo.nodes[u]["y"], grafo.nodes[u]["x"]),
                     (grafo.nodes[v]["y"], grafo.nodes[v]["x"])]

        if coordenadas and coordenadas[-1] == [round(tramo[0][0], 6), round(tramo[0][1], 6)]:
            tramo = tramo[1:]
        coordenadas.extend([round(lat, 6), round(lon, 6)] for lat, lon in tramo)

    minutos = distancia / METROS_POR_MINUTO_A_PIE if red == "peatonal" else segundos / 60
    return {
        "coordenadas": coordenadas,
        "distancia_m": round(distancia),
        "tiempo_min": max(1, round(minutos)),
        "metros_riesgo": round(metros_riesgo),
        "metros_demo": round(metros_demo),
    }


@rutas_bp.get("/api/rutas/estado")
def estado_rutas():
    modo = _modo_valido(request.args.get("modo", "pie"))
    if modo is None:
        return jsonify({"error": "Medio de transporte no válido"}), 400
    red = MODOS[modo]
    _iniciar_carga(red)
    estado = _estado[red]
    return jsonify({
        "modo": modo,
        "listo": estado["grafo"] is not None,
        "cargando": estado["cargando"],
        "error": estado["error"],
    })


@rutas_bp.get("/api/rutas/zonas")
def zonas_rutas():
    return jsonify([
        {
            "id": zona["id"],
            "nombre": zona["nombre"],
            "descripcion": zona["descripcion"],
            "demo": zona["demo"],
            "coordenadas": [[lat, lon] for lon, lat in zona["coordenadas"]],
        }
        for zona in ZONAS
    ])


@rutas_bp.post("/api/rutas/calcular")
def calcular_ruta():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    modo = _modo_valido(datos.get("modo", "pie"))
    if modo is None:
        return jsonify({"error": "Elige a pie, carro o moto"}), 400
    red = MODOS[modo]

    _iniciar_carga(red)
    grafo = _estado[red]["grafo"]
    if grafo is None:
        if _estado[red]["error"]:
            return jsonify({"error": _estado[red]["error"]}), 503
        return jsonify({
            "error": "Estamos preparando el mapa de calles de Montería. Intenta de nuevo en unos segundos.",
            "cargando": True,
        }), 503

    origen = _punto_valido(datos.get("origen"))
    destino = _punto_valido(datos.get("destino"))
    if origen is None or destino is None:
        return jsonify({"error": "Elige un punto de partida y un destino dentro de Montería"}), 400
    incluir_demo = datos.get("incluir_demo") is True

    import networkx as nx

    nodo_origen, metros_origen = _nodo_mas_cercano(_estado[red], *origen)
    nodo_destino, metros_destino = _nodo_mas_cercano(_estado[red], *destino)
    nodos = [nodo_origen, nodo_destino]
    if max(metros_origen, metros_destino) > DISTANCIA_MAXIMA_A_CALLE_M:
        return jsonify({"error": "Uno de los puntos está muy lejos de una calle de Montería"}), 400
    if nodos[0] == nodos[1]:
        return jsonify({"error": "La partida y el destino están en el mismo lugar"}), 400

    peso_corto = _peso(False, incluir_demo)
    peso_seguro = _peso(True, incluir_demo)
    try:
        ruta_corta = nx.shortest_path(grafo, nodos[0], nodos[1], weight=peso_corto)
        ruta_segura = nx.shortest_path(grafo, nodos[0], nodos[1], weight=peso_seguro)
    except nx.NetworkXNoPath:
        return jsonify({"error": "No encontramos un camino entre esos puntos para ese medio de transporte"}), 422

    return jsonify({
        "modo": modo,
        "segura": _describir_ruta(grafo, ruta_segura, peso_seguro, red),
        "corta": _describir_ruta(grafo, ruta_corta, peso_corto, red),
        "misma_ruta": ruta_corta == ruta_segura,
        "incluye_demo": incluir_demo,
    })


# ---------- Búsqueda de direcciones ----------

@lru_cache(maxsize=256)
def _buscar_en_nominatim(texto):
    respuesta = requests.get(
        "https://nominatim.openstreetmap.org/search",
        params={
            "q": f"{texto}, Montería, Córdoba",
            "format": "jsonv2",
            "limit": 5,
            "countrycodes": "co",
            "viewbox": f"{LIMITES['lon_min']},{LIMITES['lat_max']},{LIMITES['lon_max']},{LIMITES['lat_min']}",
            "bounded": 1,
            "accept-language": "es",
        },
        headers={"User-Agent": "SIGRE-prototipo-academico/0.1"},
        timeout=8,
    )
    respuesta.raise_for_status()
    return tuple(
        (lugar["display_name"], float(lugar["lat"]), float(lugar["lon"]))
        for lugar in respuesta.json()
    )


@rutas_bp.get("/api/rutas/buscar")
def buscar_direccion():
    texto = " ".join(unicodedata.normalize("NFC", request.args.get("q", "")).split())
    if not 3 <= len(texto) <= 120:
        return jsonify({"error": "Escribe entre 3 y 120 caracteres"}), 400
    try:
        resultados = _buscar_en_nominatim(texto.lower())
    except (requests.RequestException, ValueError, KeyError):
        return jsonify({"error": "No se pudo buscar la dirección. Revisa la conexión a internet."}), 502
    return jsonify([
        {"nombre": nombre, "lat": lat, "lon": lon} for nombre, lat, lon in resultados
    ])


# ---------- Rutas guardadas por cuenta ----------

# Sin este manejador, un error de la base llega al navegador como una página de
# depuración sin permisos CORS y parece que "no hay conexión con el servidor".
@rutas_bp.errorhandler(psycopg.Error)
def error_base_datos(error):
    registro.exception("Error de base de datos en el módulo de rutas")
    if isinstance(error, psycopg.errors.UndefinedTable):
        mensaje = "Falta crear la tabla de rutas guardadas: aplica backend/migracion_rutas.sql."
    elif isinstance(error, psycopg.errors.UndefinedColumn):
        mensaje = "La tabla de rutas guardadas está desactualizada: vuelve a aplicar backend/migracion_rutas.sql."
    elif isinstance(error, psycopg.errors.InsufficientPrivilege):
        mensaje = "La aplicación no tiene permiso sobre la tabla de rutas guardadas: vuelve a aplicar backend/migracion_rutas.sql."
    elif isinstance(error, psycopg.OperationalError):
        mensaje = "No se pudo conectar con la base de datos. Revisa que PostgreSQL esté encendido."
    else:
        mensaje = "La base de datos no pudo completar la operación. Revisa la terminal de Flask."
    return jsonify({"error": mensaje}), 500


def _usuario():
    rol = get_jwt().get("rol")
    try:
        usuario_id = int(get_jwt_identity())
    except (TypeError, ValueError):
        return None, None
    if rol not in ("ciudadano", "voluntario", "autoridad"):
        return None, None
    return usuario_id, rol


def _fijar_contexto(conexion, usuario_id, rol):
    conexion.execute("SELECT set_config('app.user_id', %s, true)", (str(usuario_id),))
    conexion.execute("SELECT set_config('app.user_role', %s, true)", (rol,))


def _texto(valor, minimo, maximo):
    if not isinstance(valor, str):
        return None
    texto = unicodedata.normalize("NFC", valor)
    texto = " ".join("".join(c for c in texto if c.isprintable()).split())
    return texto if minimo <= len(texto) <= maximo else None


def _entero(valor, maximo):
    return valor if isinstance(valor, int) and not isinstance(valor, bool) and 0 <= valor <= maximo else None


@rutas_bp.get("/api/rutas/guardadas")
@jwt_required()
def listar_rutas_guardadas():
    usuario_id, rol = _usuario()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    with obtener_conexion() as conexion:
        _fijar_contexto(conexion, usuario_id, rol)
        filas = conexion.execute(
            """
            SELECT id, nombre, origen_lat, origen_lon, origen_texto,
                   destino_lat, destino_lon, destino_texto, incluye_demo,
                   distancia_m, tiempo_min, metros_riesgo, geometria, creada_en, modo
            FROM rutas_guardadas
            WHERE usuario_id = %s
            ORDER BY creada_en DESC
            LIMIT 50
            """,
            (usuario_id,)
        ).fetchall()

    return jsonify([
        {
            "id": f[0], "nombre": f[1],
            "origen": {"lat": f[2], "lon": f[3], "texto": f[4]},
            "destino": {"lat": f[5], "lon": f[6], "texto": f[7]},
            "incluye_demo": f[8], "distancia_m": f[9], "tiempo_min": f[10],
            "metros_riesgo": f[11], "geometria": f[12], "creada_en": f[13].isoformat(),
            "modo": f[14],
        }
        for f in filas
    ])


@rutas_bp.post("/api/rutas/guardadas")
@jwt_required()
def guardar_ruta():
    usuario_id, rol = _usuario()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return jsonify({"error": "Envía los datos como JSON"}), 400

    nombre = _texto(datos.get("nombre"), 2, 80)
    origen = _punto_valido(datos.get("origen"))
    destino = _punto_valido(datos.get("destino"))
    origen_texto = _texto((datos.get("origen") or {}).get("texto") or "Punto en el mapa", 1, 200)
    destino_texto = _texto((datos.get("destino") or {}).get("texto") or "Punto en el mapa", 1, 200)
    distancia = _entero(datos.get("distancia_m"), 200000)
    tiempo = _entero(datos.get("tiempo_min"), 5000)
    metros_riesgo = _entero(datos.get("metros_riesgo"), 200000)
    geometria = datos.get("geometria")
    modo = _modo_valido(datos.get("modo", "pie"))

    if modo is None:
        return jsonify({"error": "El medio de transporte no es válido"}), 400
    if not nombre:
        return jsonify({"error": "Ponle un nombre a la ruta (entre 2 y 80 caracteres)"}), 400
    if origen is None or destino is None or not origen_texto or not destino_texto:
        return jsonify({"error": "La partida o el destino no son válidos"}), 400
    if distancia is None or tiempo is None or metros_riesgo is None:
        return jsonify({"error": "Los datos de la ruta no son válidos"}), 400
    if (
        not isinstance(geometria, list)
        or not 2 <= len(geometria) <= MAXIMO_PUNTOS_GEOMETRIA
        or any(_punto_valido({"lat": p[0], "lon": p[1]}) is None
               for p in geometria if isinstance(p, list) and len(p) == 2)
        or any(not (isinstance(p, list) and len(p) == 2) for p in geometria)
    ):
        return jsonify({"error": "El trazado de la ruta no es válido"}), 400

    try:
        with obtener_conexion() as conexion:
            _fijar_contexto(conexion, usuario_id, rol)
            fila = conexion.execute(
                """
                INSERT INTO rutas_guardadas
                    (usuario_id, nombre, origen_lat, origen_lon, origen_texto,
                     destino_lat, destino_lon, destino_texto, incluye_demo,
                     distancia_m, tiempo_min, metros_riesgo, geometria, modo)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id, creada_en
                """,
                (
                    usuario_id, nombre, origen[0], origen[1], origen_texto,
                    destino[0], destino[1], destino_texto, datos.get("incluye_demo") is True,
                    distancia, tiempo, metros_riesgo,
                    json.dumps([[round(float(p[0]), 6), round(float(p[1]), 6)] for p in geometria]),
                    modo,
                )
            ).fetchone()
    except psycopg.errors.ForeignKeyViolation:
        return jsonify({"error": "Tu cuenta ya no existe. Inicia sesión de nuevo."}), 401

    return jsonify({"mensaje": "Ruta guardada", "id": fila[0], "creada_en": fila[1].isoformat()}), 201


@rutas_bp.post("/api/rutas/guardadas/<int:ruta_id>/eliminar")
@jwt_required()
def eliminar_ruta(ruta_id):
    usuario_id, rol = _usuario()
    if usuario_id is None:
        return jsonify({"error": "Sesión no válida"}), 403

    with obtener_conexion() as conexion:
        _fijar_contexto(conexion, usuario_id, rol)
        fila = conexion.execute(
            "DELETE FROM rutas_guardadas WHERE id = %s AND usuario_id = %s RETURNING id",
            (ruta_id, usuario_id)
        ).fetchone()

    if fila is None:
        return jsonify({"error": "Ruta no encontrada"}), 404
    return jsonify({"mensaje": "Ruta eliminada"})


if __name__ == "__main__":
    # Prepara las redes livianas en el computador de desarrollo (necesita osmnx):
    #   python rutas.py
    # Ejecútalo de nuevo si cambias las ZONAS de riesgo.
    for nombre_red in REDES:
        print("Preparando", nombre_red, "->", construir_red_liviana(nombre_red))
