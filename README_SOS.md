# SIGRE SOS en vivo — Informe de avance

## 1. Objetivo

Implementar progresivamente el módulo SOS en vivo de SIGRE, integrando comunicación en tiempo real, autenticación, asignación de operadores, videollamada WebRTC y ubicación GPS.

## 2. Avances realizados

- Se instalaron las dependencias `Flask-SocketIO` y `simple-websocket`.
- Se añadió la inicialización de Socket.IO al backend Flask.
- Se corrigió la inicialización duplicada de Socket.IO.
- Se registraron los manejadores `connect` y `disconnect`.
- Se implementó una validación inicial del JWT durante la conexión.
- Se valida que el token incluya una identidad y uno de los roles permitidos: `ciudadano`, `voluntario` o `autoridad`.
- Se guarda temporalmente la identidad y el rol de las conexiones autenticadas en `CONECTADOS`.
- Se modificó el arranque local para utilizar `socketio.run(...)`.

## 3. Pruebas realizadas

| Prueba | Resultado |
|---|---|
| Compilación de `backend/app.py` | Correcta |
| Ruta `/api/salud` | Responde correctamente |
| Conexión a PostgreSQL | Confirmada |
| Registro de manejadores Socket.IO | Confirmado |
| Conexión Socket.IO sin JWT | Rechazada |
| Conexión Socket.IO con JWT válido | Pendiente |
| Transporte WebSocket | Requiere verificación adicional |

## 4. Archivos modificados

- `backend/app.py`
- `backend/requirements.txt`

## 5. Trabajo pendiente

1. Probar la conexión Socket.IO con un JWT válido obtenido mediante el login existente.
2. Revisar el transporte WebSocket y su funcionamiento.
3. Implementar la creación y consulta de sesiones SOS.
4. Implementar la cola de solicitudes y actualización de posiciones.
5. Implementar la asignación atómica de solicitudes a operadores.
6. Implementar la señalización WebRTC y la configuración ICE/STUN/TURN.
7. Implementar el envío periódico de ubicación GPS y su visualización.
8. Implementar el cierre de sesiones, registro de eventos y duración.
9. Aplicar controles de acceso para que solo los participantes autorizados reciban señalización y ubicación.
10. Ejecutar pruebas de concurrencia, permisos y desconexiones.

## 6. Consideraciones técnicas

- No reemplazar ni eliminar las rutas existentes de SIGRE sin revisar sus dependencias.
- No incluir contraseñas, tokens JWT ni archivos `.env` en Git.
- Verificar el despliegue de producción antes de publicar cambios relacionados con Socket.IO.
- `CONECTADOS` es almacenamiento en memoria del proceso; no sustituye una solución compartida si se despliega con varios workers.
- La implementación actual es una base inicial, no el módulo SOS completo.

## 7. Cómo ejecutar localmente

Desde la raíz del proyecto, activar el entorno virtual e instalar las dependencias:

```powershell
python -m pip install -r backend/requirements.txt
```

Arrancar el backend:

```powershell
python backend/app.py
```

Comprobar la salud:

```powershell
Invoke-RestMethod http://127.0.0.1:5000/api/salud
```

**Estado de entrega:** base inicial de Socket.IO implementada. Pendiente validar el acceso con JWT válido y continuar con las funcionalidades SOS.
