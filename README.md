# SIGRE

Prototipo académico para registrar y consultar emergencias y explorar rutas en Montería. El proyecto forma parte de una iniciativa relacionada con el ODS 11.

## Componentes

- `backend/`: API desarrollada con Flask y conexión a PostgreSQL.
- `Interfaz/`: archivos de la interfaz web.
- `datos/`: datos de referencia del proyecto.
- `rutas_eva_corregido.ipynb`: notebook para explorar rutas peatonales con OpenStreetMap y visualizar zonas aproximadas.
- `mapa_rutas.html`: mapa generado por el notebook.

## Funciones actuales de la API

- `GET /salud`: comprueba que la aplicación responde.
- `GET /api/salud`: comprueba la conexión con PostgreSQL.
- `POST /api/auth/registro`: registra una cuenta ciudadana.
- `POST /api/auth/login`: inicia sesión y devuelve un token.
- `POST /api/auth/google`: verifica una credencial de Google y crea o inicia la cuenta ciudadana.
- `GET /api/auth/google/config`: entrega al frontend el Client ID público de Google configurado en el backend.
- `GET /api/desaparecidos/<id>/comentarios` y `POST /api/desaparecidos/<id>/comentarios`: muestran o guardan comentarios de testigos; para publicar uno se requiere iniciar sesión y confirmar veracidad y autorización para compartir el teléfono con quien publicó el reporte.
- `GET /api/notificaciones/comentarios/mias`: lista avisos privados de comentarios para la cuenta autenticada.
- `POST /api/notificaciones/comentarios/<id>/leida`: marca como leída una notificación propia.
- `GET /api/mi-cuenta`: devuelve los datos de la cuenta autenticada.
- `GET /api/emergencias`: consulta emergencias con autenticación.
- `POST /api/solicitudes-ayuda`: crea una solicitud de ayuda (comunitaria, para un grupo de familias o un hogar) o una solicitud de visita a vivienda de la cuenta autenticada (requiere `backend/migracion_solicitudes_ayuda.sql`).
- `GET /api/solicitudes-ayuda/mias`: lista solo las solicitudes de la cuenta autenticada.
- `GET /api/solicitudes-ayuda/<id>/adjunto`: descarga el adjunto de una solicitud propia.
- `GET /api/mi-cuenta/avatar` y `GET /api/mi-cuenta/avatar/foto`: consultan el avatar de la cuenta autenticada (requiere `backend/migracion_avatares.sql`).
- `POST /api/mi-cuenta/avatar`: guarda un animalito de la galería, una foto propia o quita el avatar.
- `GET /api/estadisticas/usuarios`: total de usuarios registrados para el dashboard, sin datos personales (requiere `backend/migracion_estadisticas.sql`).
- `GET /api/rutas/estado`, `GET /api/rutas/zonas` y `POST /api/rutas/calcular`: preparan la red peatonal de Montería (OpenStreetMap) y calculan la ruta más corta y la más segura (código en `backend/rutas.py`).
- `GET /api/rutas/buscar?q=`: busca direcciones dentro de Montería con Nominatim.
- `GET /api/rutas/guardadas`, `POST /api/rutas/guardadas` y `POST /api/rutas/guardadas/<id>/eliminar`: rutas guardadas de la cuenta autenticada (requiere `backend/migracion_rutas.sql`).
- `GET /api/centros`: centros de acopio y albergues registrados por las entidades (público).
- `GET /api/admin/resumen`, `GET /api/admin/usuarios`, `POST /api/admin/usuarios/<id>/rol`: panel de administración (solo rol `autoridad`; requiere `backend/migracion_administracion.sql`).
- `POST /api/admin/centros`, `POST /api/admin/centros/<id>` y `POST /api/admin/centros/<id>/eliminar`: crear, editar y eliminar centros.
- `POST /api/admin/desaparecidos/<id>/estado` y `POST /api/admin/desaparecidos/<id>/eliminar`: marcar un reporte como encontrado o retirarlo.
- `GET /api/admin/solicitudes`, `POST /api/admin/solicitudes/<id>/estado`, `GET /api/admin/solicitudes/<id>/carta` (PDF) y `/adjunto`: solicitudes de ayuda en el panel (requiere `backend/migracion_administracion_contenidos.sql`).
- `GET /api/notificaciones`, `POST /api/notificaciones/<id>/leida` y `POST /api/notificaciones/leidas`: campana de notificaciones de la cuenta autenticada; las notificaciones las crean disparadores en la base (requiere `backend/migracion_notificaciones.sql`, después de las demás).
- `POST /api/jornadas/<id>/participar`, `GET /api/jornadas/<id>/participantes` y `GET /api/jornadas/estadisticas`: inscripción en jornadas, lista de quienes van (con correo y teléfono solo para autoridades) y gráfica por categoría (requiere `backend/migracion_participacion_jornadas.sql`).
- `GET /api/centros/inventario` (público) y `POST /api/admin/inventario`, `/api/admin/inventario/<id>`, `/<id>/cantidad`, `/<id>/eliminar` (solo autoridad): inventario por centro y categoría (requiere `backend/migracion_inventario_centros.sql`).
- `GET /api/mi-perfil` y `PUT /api/mi-perfil`: identificación, datos médicos y contacto de emergencia de la cuenta autenticada (requiere `backend/migracion_perfil_completo.sql`).
- `POST /api/auth/recuperar` y `POST /api/auth/restablecer`: recuperar la contraseña con un enlace por correo (requiere `backend/migracion_recuperacion_contrasenas.sql` y las variables `MAIL_USERNAME`, `MAIL_APP_PASSWORD` —contraseña de aplicación de Gmail— y `FRONTEND_URL` en `backend/.env`).
- `POST /api/auth/verificar` y `POST /api/auth/reenviar-codigo`: verificación del correo con un código de 6 números al registrarse; sin verificar no se puede iniciar sesión (requiere `backend/migracion_verificacion_correo.sql`; las cuentas que ya existían quedan verificadas).
- `GET /api/directorio` (público) y `POST /api/admin/directorio[/<id>[/eliminar]]`: directorio de entidades.
- `GET /api/jornadas` (público) y `POST /api/admin/jornadas`, `/<id>/estado`, `/<id>/eliminar`: jornadas comunitarias.
- `GET /api/emergencias/activa` (público), `GET/POST /api/admin/emergencias` y `POST /api/admin/emergencias/<id>/finalizar`: emergencias.
- `GET /api/desaparecidos/<id>/cartel`: descarga un cartel PDF tamaño A4, listo para guardar o imprimir, con la foto y los datos del reporte.
- `POST /api/desaparecidos`: crea un reporte nuevo asociado a la cuenta que inició sesión.
- `GET /api/desaparecidos/<id>/comentarios` y `POST /api/desaparecidos/<id>/comentarios`: muestran o guardan comentarios de testigos; para publicar uno se requiere iniciar sesión y confirmar veracidad y autorización para compartir el teléfono con quien publicó el reporte.
- `GET /api/notificaciones/comentarios/mias`: lista avisos privados de comentarios para la cuenta autenticada.
- `POST /api/notificaciones/comentarios/<id>/leida`: marca como leída una notificación propia.

## Requisitos

- Python
- PostgreSQL
- Git

## Preparación local del backend

Desde la carpeta raíz del proyecto, crea y activa un entorno virtual en PowerShell:

```powershell
py -m venv venv
.\venv\Scripts\Activate.ps1
```

Instala las dependencias del backend:

```powershell
python -m pip install Flask "psycopg[binary]" python-dotenv Flask-JWT-Extended google-auth reportlab Pillow
```

Para el módulo de rutas también se necesitan las librerías del notebook:

```powershell
python -m pip install osmnx networkx shapely scikit-learn requests
```

Crea `backend/.env` con la configuración local de tu computadora:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=sigre
DB_USER=sigre_app
DB_PASSWORD=tu_clave_local
JWT_SECRET_KEY=tu_clave_secreta_local
GOOGLE_CLIENT_ID=tu_client_id_de_aplicacion_web.apps.googleusercontent.com
```

Opcionalmente puedes agregar `JWT_HORAS_SESION=8` para cambiar cuántas horas dura la sesión (8 por defecto).

Para habilitar el botón de Google, crea un cliente OAuth de tipo **Aplicación web** en Google Cloud Console. Registra como orígenes JavaScript autorizados las direcciones de desarrollo, por ejemplo `http://127.0.0.1:5500` y `http://localhost:5500`, y copia el Client ID en `GOOGLE_CLIENT_ID`. No se necesita un secreto OAuth en el frontend. Google no acepta IP sin dominio como origen autorizado; para iniciar sesión desde un celular por Wi-Fi necesitarás servir SIGRE desde un nombre de dominio con HTTPS. Consulta la [configuración oficial de Google Identity Services](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid).

Después de crear la base, aplica las migraciones del backend:

```powershell
psql -U postgres -d sigre -f backend\migracion_usuarios_perfil.sql
psql -U postgres -d sigre -f backend\migracion_desaparecidos.sql
psql -U postgres -d sigre -f backend\migracion_comentarios_desaparecidos.sql
psql -U postgres -d sigre -f backend\migracion_comentarios_desaparecidos.sql
psql -U postgres -d sigre -f backend\migracion_solicitudes_ayuda.sql
psql -U postgres -d sigre -f backend\migracion_avatares.sql
psql -U postgres -d sigre -f backend\migracion_estadisticas.sql
psql -U postgres -d sigre -f backend\migracion_rutas.sql
psql -U postgres -d sigre -f backend\migracion_administracion.sql
psql -U postgres -d sigre -f backend\migracion_administracion_contenidos.sql
psql -U postgres -d sigre -f backend\migracion_notificaciones.sql
psql -U postgres -d sigre -f backend\migracion_participacion_jornadas.sql
psql -U postgres -d sigre -f backend\migracion_inventario_centros.sql
psql -U postgres -d sigre -f backend\migracion_perfil_completo.sql
psql -U postgres -d sigre -f backend\migracion_recuperacion_contrasenas.sql
psql -U postgres -d sigre -f backend\migracion_verificacion_correo.sql
```

Cada integrante debe usar sus propias claves locales. **No subas `backend/.env` a GitHub ni compartas sus contraseñas.**

Cuando PostgreSQL y la base de datos estén configurados, inicia la API desde la raíz del proyecto:

```powershell
python backend\app.py
```

La aplicación se ejecuta localmente en `http://127.0.0.1:5000`.

## Cuenta de administrador o entidad

Por seguridad, nadie puede darse el rol de administrador desde la página. El primer administrador se crea con PostgreSQL (cambia el correo por el de una cuenta ya registrada):

```powershell
psql -U postgres -d sigre -c "UPDATE usuarios SET rol = 'autoridad' WHERE email = 'correo@ejemplo.com';"
```

Después, esa persona cierra sesión y vuelve a entrar: el login la lleva a `dashboard_admin.html`. Desde el panel puede asignar los roles de las demás cuentas.

## Notebook de rutas

El notebook utiliza OpenStreetMap para explorar la red peatonal y generar un mapa. Para ejecutarlo se necesitan las bibliotecas `osmnx`, `networkx`, `geopandas`, `folium` y `shapely`.

Las zonas del mapa son aproximaciones para el prototipo; no son cartografía oficial ni deben usarse para tomar decisiones reales de emergencia.

## Estado

SIGRE está en desarrollo. La configuración completa de PostgreSQL para una computadora nueva todavía debe documentarse junto con el esquema, los permisos y las políticas de seguridad.

## Publicar en internet (Render + Neon)

- **Base de datos:** PostgreSQL en Neon. Se copia la base local con `pg_dump --no-owner` y se carga con `psql`; antes se crea el rol `sigre_app`. El rol dueño debe tener `BYPASSRLS`.
- **Servidor:** Render, *Web Service* con **Root Directory** `backend`, **Build** `pip install -r requirements.txt` y **Start** `gunicorn app:app --workers 1 --threads 4 --timeout 120`.
- **Variables de entorno en Render:** `DB_HOST` (host *-pooler* de Neon), `DB_PORT`, `DB_NAME`, `DB_USER=sigre_app`, `DB_PASSWORD`, `DB_SSLMODE=require`, `JWT_SECRET_KEY` (nueva), `GOOGLE_CLIENT_ID` y `PYTHON_VERSION`.
- Flask entrega también las páginas de `frontend/`, así que todo queda en una sola dirección HTTPS.
- `frontend/js/config.js` decide la dirección de la API: en desarrollo (Live Server, puertos 5500/8000) usa el puerto 5000; publicado, usa la misma dirección de la página.
- SIGRE se instala como app (PWA) con `frontend/manifest.json` y `frontend/service-worker.js`: en Android, menú ⋮ → *Instalar aplicación*; en iPhone, Compartir → *Agregar a inicio*.
- Si agregas una migración nueva, ejecútala también en Neon.
- **Correos en Render:** el plan gratis bloquea el SMTP de Gmail. Los correos (código de verificación y recuperación de contraseña) los envía un Google Apps Script de la cuenta del proyecto; en Render se configuran `MAIL_SCRIPT_URL` y `MAIL_SCRIPT_CLAVE`. En tu PC, sin esas variables, se usa SMTP con `MAIL_USERNAME` y `MAIL_APP_PASSWORD`.
