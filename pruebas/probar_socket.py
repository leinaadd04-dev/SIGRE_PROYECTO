"""Prueba la conexión Socket.IO de SIGRE: sin token, con token falso y con una cuenta real.

Uso:
    python pruebas\\probar_socket.py                             (servidor local)
    python pruebas\\probar_socket.py https://sigre.onrender.com  (servidor publicado)
"""
import getpass
import sys

import requests
import socketio

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"


def intentar(nombre, auth, transporte):
    cliente = socketio.Client(reconnection=False)
    try:
        cliente.connect(BASE, auth=auth, transports=[transporte], wait_timeout=15)
        print(f"[CONECTA] {nombre} por {transporte}")
        cliente.disconnect()
    except socketio.exceptions.ConnectionError as error:
        print(f"[RECHAZA] {nombre} por {transporte}: {error}")


correo = input("Correo de una cuenta verificada: ")
clave = getpass.getpass("Contraseña (no se ve al escribir): ")

respuesta = requests.post(
    f"{BASE}/api/auth/login",
    json={"email": correo, "password": clave},
    timeout=90,
)

# 200 = login correcto, 401 = datos incorrectos, 403 = correo sin verificar.
if respuesta.status_code != 200:
    print("El inicio de sesión falló:", respuesta.status_code, respuesta.text)
    sys.exit(1)

# El token se queda en memoria; nunca se imprime.
token = respuesta.json()["access_token"]

for transporte in ("polling", "websocket"):
    intentar("sin token", None, transporte)
    intentar("token falso", {"token": "abc.def.ghi"}, transporte)
    intentar("token válido", {"token": token}, transporte)
