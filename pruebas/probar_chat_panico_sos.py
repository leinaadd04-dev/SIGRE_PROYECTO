"""Prueba el chat de texto y el botón de pánico de SOS en vivo contra el servidor local.

Antes de correrla:
    1. psql -U postgres -d sigre -f pruebas\\cuentas_prueba_sos.sql
    2. python backend\\app.py   (en otra terminal)

Uso:
    python pruebas\\probar_chat_panico_sos.py
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


def conectar(correo):
    cliente = socketio.Client(reconnection=False)
    cliente.recibidos = []
    for evento in ("chat:mensaje", "sos:panico", "sos:ubicacion"):
        cliente.on(evento, lambda datos, e=evento, c=cliente: c.recibidos.append((e, datos)))
    cliente.connect(BASE, auth={"token": iniciar_sesion(correo)}, transports=["websocket"], wait_timeout=15)
    return cliente


def llegaron(cliente, evento):
    return [datos for nombre, datos in cliente.recibidos if nombre == evento]


def limpiar_abiertas(cliente):
    """Cierra la emergencia abierta que haya dejado una prueba anterior."""
    abierta = cliente.call("sos:retomar", {})
    if abierta.get("sesion"):
        if abierta["estado"] == "en_espera":
            cliente.call("sos:cancelar", {"sesion": abierta["sesion"]})
        else:
            cliente.call("sos:finalizar", {"sesion": abierta["sesion"]})


ciudadano = conectar("ciudadano1.sos@sigre.test")
otro_ciudadano = conectar("ciudadano2.sos@sigre.test")
sin_sos = conectar("ciudadano3.sos@sigre.test")
operador = conectar("operador1.sos@sigre.test")
otro_operador = conectar("operador2.sos@sigre.test")
for cliente in (ciudadano, otro_ciudadano, sin_sos):
    limpiar_abiertas(cliente)

sesion = ciudadano.call("sos:crear", {"lat": 8.7479, "lng": -75.8814, "precision": 10})["sesion"]
en_espera = otro_ciudadano.call("sos:crear", {"lat": 8.7500, "lng": -75.8800, "precision": 15})["sesion"]
aceptada = operador.call("sos:aceptar", {"sesion": sesion})
if not aceptada.get("ok"):
    print("El operador no pudo aceptar la emergencia:", aceptada)
    sys.exit(1)
time.sleep(0.5)

print("\n1. Chat de texto durante la llamada")
respuesta = ciudadano.call("chat:enviar", {"sesion": sesion, "texto": "  Hola, necesito ayuda  "})
time.sleep(0.5)
al_operador = llegaron(operador, "chat:mensaje")
revisar("El mensaje del ciudadano le llega al operador, sin espacios sobrantes",
        respuesta.get("ok") is True and len(al_operador) == 1
        and al_operador[0]["texto"] == "Hola, necesito ayuda" and al_operador[0]["de"] == "ciudadano",
        f"respuesta: {respuesta}")
revisar("El ciudadano también recibe su mensaje (para pintarlo)", len(llegaron(ciudadano, "chat:mensaje")) == 1)

time.sleep(0.5)
operador.call("chat:enviar", {"sesion": sesion, "texto": "Te escucho, ya vamos"})
time.sleep(0.5)
del_operador = [m for m in llegaron(ciudadano, "chat:mensaje") if m["de"] == "operador"]
revisar("La respuesta del operador le llega al ciudadano",
        len(del_operador) == 1 and del_operador[0]["texto"] == "Te escucho, ya vamos")

time.sleep(0.5)
larga = ciudadano.call("chat:enviar", {"sesion": sesion, "texto": "a" * 500})
time.sleep(0.5)
ultimo = llegaron(operador, "chat:mensaje")[-1]
revisar("Un mensaje muy largo se recorta a 300 caracteres", larga.get("ok") is True and len(ultimo["texto"]) == 300)

time.sleep(0.5)
vacio = ciudadano.call("chat:enviar", {"sesion": sesion, "texto": "   "})
revisar("No se envía un mensaje vacío", "error" in vacio, f"respuesta: {vacio}")

ajeno = otro_operador.call("chat:enviar", {"sesion": sesion, "texto": "Me meto"})
ajeno_ciudadano = otro_ciudadano.call("chat:enviar", {"sesion": sesion, "texto": "Yo también"})
time.sleep(0.5)
revisar("Quien no participa no puede escribir en la emergencia ajena",
        "error" in ajeno and "error" in ajeno_ciudadano, f"respuesta: {ajeno}")
revisar("Quien no participa no recibe los mensajes",
        not llegaron(otro_operador, "chat:mensaje") and not llegaron(otro_ciudadano, "chat:mensaje"))
sin_atender = otro_ciudadano.call("chat:enviar", {"sesion": en_espera, "texto": "¿Hay alguien?"})
revisar("No hay chat mientras la emergencia sigue en espera", "error" in sin_atender)

print("\n2. Botón de pánico")
panico = otro_ciudadano.call("sos:panico", {"sesion": en_espera, "lat": 8.7512, "lng": -75.8791, "precision": 8})
time.sleep(0.5)
avisos = [a for a in llegaron(operador, "sos:panico") if a["sesion"] == en_espera]
revisar("El operador recibe la alerta de pánico con la ubicación",
        panico.get("ok") is True and len(avisos) == 1 and avisos[0]["ubicacion"]
        and abs(avisos[0]["ubicacion"]["lat"] - 8.7512) < 1e-9, f"respuesta: {panico}")
revisar("La alerta le llega también a los demás operadores",
        any(a["sesion"] == en_espera for a in llegaron(otro_operador, "sos:panico")))
cola = operador.call("sos:cola")["cola"]
marcada = [item for item in cola if item["sesion"] == en_espera]
revisar("La emergencia queda marcada como urgente en la cola",
        len(marcada) == 1 and marcada[0]["urgente"] is True and marcada[0]["lat"] == 8.7512)

respuesta_campana = requests.get(f"{BASE}/api/notificaciones",
                                 headers={"Authorization": f"Bearer {iniciar_sesion('operador2.sos@sigre.test')}"}, timeout=30)
titulos = [n["titulo"] for n in respuesta_campana.json().get("notificaciones", [])] if respuesta_campana.ok else []
revisar("La alerta también llega a la campana de las autoridades (para el push)",
        any(titulo.startswith("PÁNICO") for titulo in titulos),
        "si falla, ejecuta backend/migracion_sos_panico.sql")

repetida = otro_ciudadano.call("sos:panico", {"sesion": en_espera, "lat": 8.7512, "lng": -75.8791})
time.sleep(0.5)
revisar("Pulsarlo varias veces seguidas no repite la alerta",
        repetida.get("ok") is True
        and len([a for a in llegaron(operador, "sos:panico") if a["sesion"] == en_espera]) == 1)

durante = ciudadano.call("sos:panico", {"sesion": sesion, "lat": 8.7480, "lng": -75.8815, "precision": 9})
time.sleep(0.5)
revisar("También funciona durante la videollamada",
        durante.get("ok") is True and any(a["sesion"] == sesion for a in llegaron(operador, "sos:panico"))
        and any(p["sesion"] == sesion and p["lat"] == 8.7480 for p in llegaron(operador, "sos:ubicacion")))

revisar("Un operador no puede mandar una alerta de pánico",
        "error" in operador.call("sos:panico", {"sesion": sesion, "lat": 8.7, "lng": -75.8}))
revisar("Un ciudadano sin emergencia abierta no puede mandarla",
        "error" in sin_sos.call("sos:panico", {"sesion": sesion, "lat": 8.7, "lng": -75.8}))
segunda_conexion = conectar("ciudadano2.sos@sigre.test")
revisar("Un ciudadano no puede mandarla sobre la emergencia de otro",
        "error" in segunda_conexion.call("sos:panico", {"sesion": sesion, "lat": 8.7, "lng": -75.8}))

# Limpieza
operador.call("sos:finalizar", {"sesion": sesion})
otro_ciudadano.call("sos:cancelar", {"sesion": en_espera})
for cliente in (ciudadano, otro_ciudadano, segunda_conexion, sin_sos, operador, otro_operador):
    cliente.disconnect()

aprobadas = sum(resultados)
print(f"\nResultado: {aprobadas} de {len(resultados)} pruebas pasaron.")
sys.exit(0 if aprobadas == len(resultados) else 1)
