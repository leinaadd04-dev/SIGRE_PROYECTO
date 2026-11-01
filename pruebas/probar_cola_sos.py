"""Prueba la cola y la asignación de SOS en vivo contra el servidor local.

Antes de correrla:
    1. psql -U postgres -d sigre -f pruebas\\cuentas_prueba_sos.sql
    2. python backend\\app.py   (en otra terminal)

Uso:
    python pruebas\\probar_cola_sos.py
"""
import sys
import threading
import time

import requests
import socketio

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
CLAVE = "PruebaSOS2026*"
UBICACIONES = [(8.7479, -75.8814), (8.7550, -75.8890), (8.7400, -75.8750)]

resultados = []


def revisar(descripcion, condicion, detalle=""):
    resultados.append(condicion)
    marca = "PASA " if condicion else "FALLA"
    print(f"[{marca}] {descripcion}" + (f"  ({detalle})" if detalle else ""))


def conectar(correo):
    respuesta = requests.post(f"{BASE}/api/auth/login",
                              json={"email": correo, "password": CLAVE}, timeout=30)
    if respuesta.status_code != 200:
        print(f"No se pudo iniciar sesión con {correo}: {respuesta.status_code}. "
              "¿Ejecutaste pruebas\\cuentas_prueba_sos.sql?")
        sys.exit(1)
    cliente = socketio.Client(reconnection=False)
    cliente.connect(BASE, auth={"token": respuesta.json()["access_token"]},
                    transports=["websocket"], wait_timeout=15)
    return cliente


ciudadanos = [conectar(f"ciudadano{n}.sos@sigre.test") for n in (1, 2, 3)]
operadores = [conectar(f"operador{n}.sos@sigre.test") for n in (1, 2)]

# Cada operador anota cuándo le llega cada emergencia nueva.
llegadas = [{}, {}]
for indice, operador in enumerate(operadores):
    operador.on("sos:nueva", lambda datos, i=indice: llegadas[i].__setitem__(datos["sesion"], time.time()))

aceptadas = []
ciudadanos[0].on("sos:aceptada", lambda datos: aceptadas.append(datos["sesion"]))

print("\n1. Tres ciudadanos piden SOS en vivo")
sesiones, enviadas = [], {}
for ciudadano, (lat, lng) in zip(ciudadanos, UBICACIONES):
    inicio = time.time()
    respuesta = ciudadano.call("sos:crear", {"lat": lat, "lng": lng, "precision": 12}, timeout=15)
    if "sesion" not in respuesta:
        print("No se pudo crear la emergencia:", respuesta)
        sys.exit(1)
    sesiones.append(respuesta["sesion"])
    enviadas[respuesta["sesion"]] = inicio
    time.sleep(0.2)
time.sleep(1)

posiciones = [c.call("cola:posicion", {"sesion": s})["posicion"] for c, s in zip(ciudadanos, sesiones)]
revisar("Las posiciones en la cola son 1, 2 y 3", posiciones == [1, 2, 3], f"obtenidas: {posiciones}")

for indice, recibidas in enumerate(llegadas):
    demoras = [recibidas[s] - enviadas[s] for s in sesiones if s in recibidas]
    revisar(f"El operador {indice + 1} recibió las 3 emergencias en menos de 2 s",
            len(demoras) == 3 and max(demoras) < 2,
            f"máxima demora: {max(demoras):.2f} s" if demoras else "no llegó ninguna")

cola = operadores[0].call("sos:cola")["cola"]
revisar("La cola del panel muestra las 3 emergencias en orden",
        [e["sesion"] for e in cola][-3:] == sesiones)

print("\n2. Dos operadores aceptan la primera emergencia al mismo tiempo")
barrera = threading.Barrier(2)
respuestas = [None, None]


def aceptar(indice):
    barrera.wait()
    respuestas[indice] = operadores[indice].call("sos:aceptar", {"sesion": sesiones[0]}, timeout=15)


hilos = [threading.Thread(target=aceptar, args=(i,)) for i in (0, 1)]
for hilo in hilos:
    hilo.start()
for hilo in hilos:
    hilo.join()

ganadores = [r for r in respuestas if r.get("ok")]
perdedores = [r for r in respuestas if r.get("error")]
revisar("Solo un operador obtiene la emergencia", len(ganadores) == 1 and len(perdedores) == 1,
        f"respuestas: {respuestas}")
revisar("El otro ve «ya fue tomada»",
        bool(perdedores) and "ya fue tomada" in perdedores[0]["error"])
revisar("El operador que la toma recibe el nombre y teléfono del ciudadano",
        bool(ganadores) and (ganadores[0].get("contacto") or {}).get("nombre") == "Ciudadano Prueba Uno")
time.sleep(1)
revisar("El ciudadano recibe el aviso sos:aceptada", sesiones[0] in aceptadas)

posiciones = [c.call("cola:posicion", {"sesion": s})["posicion"] for c, s in zip(ciudadanos[1:], sesiones[1:])]
revisar("Las posiciones restantes pasan a 1 y 2", posiciones == [1, 2], f"obtenidas: {posiciones}")

print("\n3. Permisos")
respuesta = ciudadanos[1].call("sos:aceptar", {"sesion": sesiones[2]})
revisar("Un ciudadano no puede aceptar emergencias", "error" in respuesta)
respuesta = ciudadanos[1].call("cola:posicion", {"sesion": sesiones[2]})
revisar("Un ciudadano no ve la posición de una emergencia ajena", respuesta.get("posicion") is None)
respuesta = operadores[0].call("sos:crear", {"lat": 8.75, "lng": -75.88})
revisar("Una autoridad no puede crear un SOS", "error" in respuesta)

print("\n4. Cancelar")
respuesta = ciudadanos[2].call("sos:cancelar", {"sesion": sesiones[2]})
revisar("El ciudadano puede cancelar mientras espera", respuesta.get("ok") is True)
respuesta = ciudadanos[0].call("sos:cancelar", {"sesion": sesiones[0]})
revisar("No se puede cancelar una emergencia ya atendida", "error" in respuesta)
ciudadanos[1].call("sos:cancelar", {"sesion": sesiones[1]})

for cliente in ciudadanos + operadores:
    cliente.disconnect()

print(f"\nResultado: {sum(resultados)} de {len(resultados)} pruebas pasaron.")
