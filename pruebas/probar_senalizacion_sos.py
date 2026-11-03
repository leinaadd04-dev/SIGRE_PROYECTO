"""Prueba la señalización WebRTC de SOS en vivo contra el servidor local.

Antes de correrla:
    1. psql -U postgres -d sigre -f pruebas\\cuentas_prueba_sos.sql
    2. python backend\\app.py   (en otra terminal)

Uso:
    python pruebas\\probar_senalizacion_sos.py
"""
import sys
import time

import requests
import socketio

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
CLAVE = "PruebaSOS2026*"

resultados = []


def revisar(descripcion, condicion, detalle=""):
    resultados.append(condicion)
    marca = "PASA " if condicion else "FALLA"
    print(f"[{marca}] {descripcion}" + (f"  ({detalle})" if detalle else ""))


def iniciar_sesion(correo):
    respuesta = requests.post(f"{BASE}/api/auth/login",
                              json={"email": correo, "password": CLAVE}, timeout=30)
    if respuesta.status_code != 200:
        print(f"No se pudo iniciar sesión con {correo}: {respuesta.status_code}. "
              "¿Ejecutaste pruebas\\cuentas_prueba_sos.sql?")
        sys.exit(1)
    return respuesta.json()["access_token"]


def conectar(token):
    cliente = socketio.Client(reconnection=False)
    # Cada cliente guarda aquí los mensajes WebRTC que le llegan.
    cliente.recibidos = []
    for evento in ("webrtc:offer", "webrtc:answer", "webrtc:ice"):
        cliente.on(evento, lambda datos, e=evento, c=cliente: c.recibidos.append((e, datos)))
    cliente.connect(BASE, auth={"token": token}, transports=["websocket"], wait_timeout=15)
    return cliente


def llegaron(cliente, evento):
    return [datos for nombre, datos in cliente.recibidos if nombre == evento]


print("\n1. Servidores ICE")
respuesta = requests.get(f"{BASE}/api/sos/ice", timeout=30)
revisar("Sin sesión, /api/sos/ice responde 401", respuesta.status_code == 401,
        f"código: {respuesta.status_code}")

token_ciudadano = iniciar_sesion("ciudadano1.sos@sigre.test")
respuesta = requests.get(f"{BASE}/api/sos/ice",
                         headers={"Authorization": f"Bearer {token_ciudadano}"}, timeout=30)
servidores = respuesta.json().get("iceServers", []) if respuesta.ok else []
direcciones = str([s.get("urls") for s in servidores])
revisar("Con sesión entrega STUN y TURN", "stun:" in direcciones and "turn:" in direcciones,
        f"{len(servidores)} servidores")

ciudadano = conectar(token_ciudadano)
otro_ciudadano = conectar(iniciar_sesion("ciudadano2.sos@sigre.test"))
operador = conectar(iniciar_sesion("operador1.sos@sigre.test"))
otro_operador = conectar(iniciar_sesion("operador2.sos@sigre.test"))

# El ciudadano 1 pide SOS y el operador 1 lo acepta: los dos quedan en la sala.
sesion = ciudadano.call("sos:crear", {"lat": 8.7479, "lng": -75.8814, "precision": 10})["sesion"]
aceptada = operador.call("sos:aceptar", {"sesion": sesion})
if not aceptada.get("ok"):
    print("El operador no pudo aceptar la emergencia:", aceptada)
    sys.exit(1)
time.sleep(0.5)

print("\n2. Señalización entre los participantes")
oferta = {"type": "offer", "sdp": "v=0 oferta-de-prueba"}
respuesta = ciudadano.call("webrtc:offer", {"sesion": sesion, "sdp": oferta})
time.sleep(0.5)
recibidas = llegaron(operador, "webrtc:offer")
revisar("La offer del ciudadano le llega al operador con el mismo contenido",
        respuesta.get("ok") is True and len(recibidas) == 1 and recibidas[0]["sdp"] == oferta,
        f"respuesta: {respuesta}")
revisar("El ciudadano no recibe de vuelta su propia offer", not llegaron(ciudadano, "webrtc:offer"))

contestacion = {"type": "answer", "sdp": "v=0 respuesta-de-prueba"}
operador.call("webrtc:answer", {"sesion": sesion, "sdp": contestacion})
time.sleep(0.5)
recibidas = llegaron(ciudadano, "webrtc:answer")
revisar("La answer del operador le llega al ciudadano",
        len(recibidas) == 1 and recibidas[0]["sdp"] == contestacion)

candidato = {"candidate": "candidate:1 1 udp 2122260223 192.168.1.5 54321 typ host",
             "sdpMid": "0", "sdpMLineIndex": 0}
ciudadano.call("webrtc:ice", {"sesion": sesion, "candidato": candidato})
time.sleep(0.5)
recibidos = llegaron(operador, "webrtc:ice")
revisar("El candidato ICE del ciudadano le llega al operador",
        len(recibidos) == 1 and recibidos[0]["candidato"] == candidato)

print("\n3. Nadie más entra a la llamada")
respuesta = otro_operador.call("webrtc:offer", {"sesion": sesion, "sdp": oferta})
revisar("Otro operador no puede enviar señalización a esa emergencia", "error" in respuesta,
        f"respuesta: {respuesta}")
revisar("Otro operador no recibió ningún mensaje de la llamada", not otro_operador.recibidos)
respuesta = otro_ciudadano.call("webrtc:ice", {"sesion": sesion, "candidato": candidato})
revisar("Otro ciudadano no puede enviar señalización a esa emergencia", "error" in respuesta)

# El ciudadano 2 pide SOS pero nadie lo acepta todavía.
en_espera = otro_ciudadano.call("sos:crear", {"lat": 8.755, "lng": -75.889, "precision": 10})["sesion"]
respuesta = otro_ciudadano.call("webrtc:offer", {"sesion": en_espera, "sdp": oferta})
revisar("Una emergencia sin aceptar no permite señalización", "error" in respuesta)
otro_ciudadano.call("sos:cancelar", {"sesion": en_espera})

for cliente in (ciudadano, otro_ciudadano, operador, otro_operador):
    cliente.disconnect()

print(f"\nResultado: {sum(resultados)} de {len(resultados)} pruebas pasaron.")
