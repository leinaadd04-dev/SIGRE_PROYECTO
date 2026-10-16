# SIGRE

Sistema de Gestión de Riesgos y Emergencias. Prototipo académico para registrar y consultar emergencias, pedir ayuda, encontrar rutas de evacuación y organizar a la comunidad en Montería, Córdoba. El proyecto forma parte de una iniciativa relacionada con el ODS 11.

- **Publicado en:** https://sigre.onrender.com (se puede instalar como app en el celular).
- **Repositorio:** https://github.com/leinaadd04-dev/SIGRE_PROYECTO
- **ODS abordado:** ODS 11 · Ciudades y comunidades sostenibles (meta 11.5: reducir las muertes y personas afectadas por desastres).

## Integrantes

| Nombre | Usuario de GitHub |
|---|---|
| Daniel Gómez Urueta | [danielurueta937-a11y](https://github.com/danielurueta937-a11y) y [leinaadd04-dev](https://github.com/leinaadd04-dev) (cuenta del propietario del repositorio) |
| Fabian Ernesto Muñoz Padilla | [yvlyvlyvl](https://github.com/yvlyvlyvl) |

## Componentes

- `backend/`: API en Flask con PostgreSQL. También entrega las páginas de `frontend/` cuando está publicada.
  - `app.py`: cuentas, perfil, desaparecidos, solicitudes de ayuda y correos.
  - `administracion.py`: panel de administración, centros, inventario, directorio, jornadas y emergencias.
  - `notificaciones.py`: campana de notificaciones.
  - `push.py`: notificaciones push al celular (llegan con la app cerrada).
  - `rutas.py`: rutas de evacuación sobre las calles de Montería.
  - `migracion_*.sql`: cambios de la base de datos (ver más abajo).
  - `datos_rutas/*.json.gz`: redes de calles de Montería ya preparadas para el servidor.
  - `apps_script/correos.gs`: código del Google Apps Script que envía los correos en la versión publicada.
- `frontend/`: páginas web (HTML, CSS y JavaScript).
- `.env.example`: nombres de todas las variables de entorno, sin valores reales.
- `database/`: base de datos: esquema completo (`schema.sql`), datos de demostración (`datos_demo.sql`) y respaldo listo para restaurar (`sigre_demo.sql`).
- `rutas_eva_corregido.ipynb`: notebook para explorar rutas peatonales con OpenStreetMap.
- `mapa_rutas.html`: mapa generado por el notebook.

## Tecnologías utilizadas

| Capa | Tecnología | Para qué se usa |
|---|---|---|
| **Frontend** | HTML5, CSS3 y JavaScript (sin framework) | Todas las páginas, la navegación y la comunicación con la API (`fetch`). |
| | [Leaflet](https://leafletjs.com/) 1.9.4 | Mapas de rutas, centros, jornadas y emergencias. |
| | Mapas de OpenStreetMap, OpenTopoMap y Esri | Capas de calles, relieve y satélite de los mapas. |
| | Font Awesome 6.5 y Lucide | Íconos. |
| | PWA: `manifest.json` y *service worker* | Instalar SIGRE como app en el celular, funcionar con mala conexión y recibir notificaciones push. |
| **Backend** | Python 3.12 y [Flask](https://flask.palletsprojects.com/) 3.1 | API REST y entrega de las páginas. Módulos con *Blueprints*. |
| | Flask-JWT-Extended 4.7 | Sesiones con tokens JWT y roles (ciudadano, voluntario, autoridad). |
| | Werkzeug | Contraseñas guardadas con *hash* seguro (nunca en texto plano). |
| | psycopg 3.3 | Conexión a PostgreSQL con consultas parametrizadas. |
| | NetworkX 3.6 | Cálculo de la ruta más corta y la más segura sobre las calles de Montería. |
| | OSMnx 2.1, Shapely y scikit-learn (solo en desarrollo) | Descargar las calles de OpenStreetMap y marcar las zonas de riesgo. |
| | ReportLab 5.0 y Pillow 12.3 | Cartas y carteles en PDF; recorte y compresión de fotos. |
| | pywebpush 2.5 (VAPID) | Notificaciones push al celular. |
| | Gunicorn | Servidor de producción en Render. |
| **Base de datos** | [PostgreSQL](https://www.postgresql.org/) 18 | Persistencia de todos los datos. Usa seguridad por filas (*Row Level Security*), funciones `SECURITY DEFINER`, disparadores (*triggers*) para las notificaciones y restricciones `CHECK`. |
| **Servicios externos** | Nominatim (OpenStreetMap) | Buscar direcciones dentro de Montería. |
| | Open-Meteo | Clima actual en el dashboard. |
| | [Google Apps Script](https://developers.google.com/apps-script) (`MailApp`) | Envía los correos en la versión publicada (código de verificación y recuperación de contraseña). Render gratis bloquea el SMTP, así que el backend llama al script por HTTPS con una clave secreta. Código en `backend/apps_script/correos.gs`. |
| | Gmail (SMTP con contraseña de aplicación) | Envío de correos en desarrollo local, y cuenta remitente del proyecto (`sigre.oficial@gmail.com`). |
| **Despliegue y trabajo en equipo** | [Render](https://render.com/) | Servidor publicado, conectado a GitHub (cada *push* a `main` se publica solo). |
| | Git y GitHub | Control de versiones y trabajo en equipo. |
| | Visual Studio Code y Live Server | Desarrollo local. |

## Funciones de la página

**Para la comunidad**
- Registro con **verificación del correo** (código de 6 números) e inicio de sesión. Recuperación de contraseña por correo.
- **Dashboard:** emergencia activa, clima, número de usuarios, directorio de entidades (con foto o logo) y rutas guardadas.
- **Rutas de evacuación:** a pie, en carro o en moto; compara la ruta más corta con la más segura (evita zonas de riesgo).
- **Centros de acopio y albergues:** mapa, cupos e inventario por categoría (solo lectura). "Necesita" se calcula del inventario.
- **Solicitar ayuda** (alimentos, salud, alojamiento, ropa, transporte o visita a la vivienda) y seguimiento de "Mis solicitudes".
- **Jornadas comunitarias:** inscripción, quiénes van, gráfica de participación por categoría y "Mis intereses". Las jornadas en curso se marcan "En curso" y las que terminaron quedan al final, bajo "Jornadas finalizadas", sin poder inscribirse.
- **Desaparecidos:** reportes con foto, comentarios de testigos, cartel PDF y enlace para compartir.
- **Mi perfil:** foto o animalito, identificación, datos médicos y contacto de emergencia.
- **Campana de notificaciones** y **avisos push** al celular aunque SIGRE esté cerrada (se activan en el menú ☰), **chatbot** de preguntas frecuentes y botón **SOS** (llama al 123).
- Navegación igual en todas las páginas: cabecera en computador y barra inferior en celular; menú ☰ con las opciones de la cuenta.

**Para administradores (rol `autoridad`)**
- Panel en `dashboard_admin.html`: usuarios y roles, centros y albergues, **inventario** (tabla por categoría, tallas y unidades), desaparecidos, solicitudes (con carta en PDF), emergencias, jornadas (crear y editar) y directorio (con foto o logo).

## Funciones actuales de la API

**Estado**
- `GET /salud` y `GET /api/salud`: comprueban que la aplicación y PostgreSQL responden.

**Cuentas** (`app.py`)
- `POST /api/auth/registro`: crea una cuenta ciudadana sin verificar y envía un código de 6 números al correo. Si el correo ya tenía una cuenta sin verificar, reenvía el código (requiere `migracion_verificacion_correo.sql`).
- `POST /api/auth/verificar` y `POST /api/auth/reenviar-codigo`: verifican el correo con el código (vence en 10 minutos, máximo 5 intentos, un reenvío por minuto).
- `POST /api/auth/login`: inicia sesión y devuelve un token. Si el correo no está verificado, envía un código nuevo y responde 403.
- `POST /api/auth/recuperar` y `POST /api/auth/restablecer`: recuperan la contraseña con un enlace por correo (vence en 15 minutos; requiere `migracion_recuperacion_contrasenas.sql`).
- `POST /api/auth/google` y `GET /api/auth/google/config`: inicio de sesión con Google (el botón está desactivado en la página).
- `GET /api/mi-cuenta`: datos de la cuenta autenticada.
- `GET /api/mi-cuenta/avatar`, `GET /api/mi-cuenta/avatar/foto` y `POST /api/mi-cuenta/avatar`: avatar (animalito o foto propia; requiere `migracion_avatares.sql`).
- `GET /api/mi-perfil` y `PUT /api/mi-perfil`: identificación, datos médicos y contacto de emergencia (requiere `migracion_perfil_completo.sql`).
- `GET /api/estadisticas/usuarios`: total de usuarios registrados, sin datos personales (requiere `migracion_estadisticas.sql`).

**Desaparecidos**
- `GET /api/desaparecidos` y `POST /api/desaparecidos`: lista y crea reportes (crear requiere sesión).
- `GET /api/desaparecidos/<id>/foto` y `GET /api/desaparecidos/<id>/cartel`: foto y cartel PDF tamaño A4.
- `GET` y `POST /api/desaparecidos/<id>/comentarios`: comentarios de testigos (publicar requiere sesión y confirmar veracidad).
- `GET /api/notificaciones/comentarios/mias` y `POST /api/notificaciones/comentarios/<id>/leida`: avisos de comentarios a quien publicó el reporte.

**Solicitudes de ayuda**
- `POST /api/solicitudes-ayuda`: solicitud de ayuda (hogar, grupo de familias o comunidad) o de visita a la vivienda (requiere `migracion_solicitudes_ayuda.sql`).
- `GET /api/solicitudes-ayuda/mias` y `GET /api/solicitudes-ayuda/<id>/adjunto`: solicitudes propias y su adjunto.

**Emergencias y notificaciones**
- `GET /api/emergencias` (con sesión) y `GET /api/emergencias/activa` (público).
- `GET /api/notificaciones`, `POST /api/notificaciones/<id>/leida` y `POST /api/notificaciones/leidas`: campana; las notificaciones las crean disparadores en la base (requiere `migracion_notificaciones.sql`).
- `GET /api/push/clave-publica`, `POST /api/push/suscribir` y `POST /api/push/desuscribir`: inscriben el celular para recibir las mismas notificaciones como push. Después de cada acción (POST/PUT) el servidor envía en segundo plano las notificaciones nuevas (requiere `migracion_push.sql` y las claves VAPID).

**Centros, inventario, directorio y jornadas** (`administracion.py`)
- `GET /api/centros` y `GET /api/centros/inventario`: centros y su inventario (públicos; requiere `migracion_inventario_centros.sql`).
- `GET /api/directorio` y `GET /api/directorio/<id>/foto`: directorio de entidades y su foto o logo (requiere `migracion_fotos_directorio.sql`).
- `GET /api/jornadas` y `GET /api/jornadas/estadisticas`: jornadas publicadas y gráfica por categoría. Cada jornada trae `momento` (`proxima`, `en_curso` o `finalizada`); las finalizadas de los últimos 60 días van al final. Una jornada termina en su `fecha_fin` o, si no tiene, 12 horas después de empezar (requiere `migracion_fin_jornadas.sql`).
- `POST /api/jornadas/<id>/participar` y `GET /api/jornadas/<id>/participantes`: inscripción (hasta que la jornada termina) y lista de quienes van; correo y teléfono solo para administradores (requiere `migracion_participacion_jornadas.sql`).

**Rutas de evacuación** (`rutas.py`)
- `GET /api/rutas/estado`, `GET /api/rutas/zonas` y `POST /api/rutas/calcular`: preparan las redes de calles y calculan la ruta más corta y la más segura.
- `GET /api/rutas/buscar?q=`: busca direcciones dentro de Montería con Nominatim.
- `GET /api/rutas/guardadas`, `POST /api/rutas/guardadas` y `POST /api/rutas/guardadas/<id>/eliminar`: rutas guardadas de la cuenta (requiere `migracion_rutas.sql`).

**Administración** (solo rol `autoridad`; requiere `migracion_administracion.sql` y `migracion_administracion_contenidos.sql`)
- `GET /api/admin/resumen`, `GET /api/admin/usuarios` y `POST /api/admin/usuarios/<id>/rol`.
- `POST /api/admin/centros`, `POST /api/admin/centros/<id>` y `POST /api/admin/centros/<id>/eliminar`.
- `POST /api/admin/inventario`, `POST /api/admin/inventario/<id>`, `/<id>/cantidad` y `/<id>/eliminar`.
- `POST /api/admin/desaparecidos/<id>/estado` y `POST /api/admin/desaparecidos/<id>/eliminar`.
- `GET /api/admin/solicitudes`, `POST /api/admin/solicitudes/<id>/estado`, `GET /api/admin/solicitudes/<id>/carta` (PDF) y `/adjunto`.
- `GET` y `POST /api/admin/emergencias` y `POST /api/admin/emergencias/<id>/finalizar`.
- `POST /api/admin/jornadas`, `POST /api/admin/jornadas/<id>` (editar), `/<id>/estado` y `/<id>/eliminar`.
- `POST /api/admin/directorio`, `POST /api/admin/directorio/<id>`, `/<id>/eliminar`, `/<id>/foto` y `/<id>/foto/eliminar`.

## Requisitos

- Python 3.12 o más reciente
- PostgreSQL 18
- Git

## Preparación local del backend

Desde la carpeta raíz del proyecto, crea y activa un entorno virtual en PowerShell:

```powershell
py -m venv venv
.\venv\Scripts\Activate.ps1
```

Instala las dependencias del backend:

```powershell
python -m pip install -r backend\requirements.txt
```

Para **volver a preparar los mapas de rutas** (solo si cambias las zonas de riesgo) se necesitan además:

```powershell
python -m pip install osmnx==2.1.1 shapely==2.1.2 scikit-learn==1.9.1
```

Crea `backend/.env` a partir de la plantilla [`.env.example`](.env.example), que tiene todas las variables con su explicación, y llena los valores de tu equipo:

```powershell
copy .env.example backend\.env
```

Las mínimas para arrancar son las de la base de datos (`DB_*`) y `JWT_SECRET_KEY`.

- `MAIL_APP_PASSWORD` no es la contraseña normal de Gmail: se crea en https://myaccount.google.com/apppasswords (la cuenta necesita verificación en 2 pasos).
- `FRONTEND_URL` es la dirección donde abres las páginas; se usa para el enlace del correo de recuperación.
- Notificaciones push: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` y `VAPID_CONTACTO=mailto:correo-del-proyecto@gmail.com`. El par de claves se crea con `python backend\push.py`; sin ellas, SIGRE funciona igual pero sin avisos push. Los avisos push solo funcionan en la versión publicada (HTTPS).
- Opcional: `JWT_HORAS_SESION=8` (horas que dura la sesión) y `GOOGLE_CLIENT_ID` (inicio de sesión con Google).

Después de crear la base, aplica las migraciones del backend en este orden (todas se pueden volver a ejecutar sin dañar nada):

```powershell
psql -U postgres -d sigre -f backend\migracion_usuarios_perfil.sql
psql -U postgres -d sigre -f backend\migracion_desaparecidos.sql
psql -U postgres -d sigre -f backend\migracion_comentarios_desaparecidos.sql
psql -U postgres -d sigre -f backend\migracion_solicitudes_ayuda.sql
psql -U postgres -d sigre -f backend\migracion_avatares.sql
psql -U postgres -d sigre -f backend\migracion_estadisticas.sql
psql -U postgres -d sigre -f backend\migracion_rutas.sql
psql -U postgres -d sigre -f backend\migracion_administracion.sql
psql -U postgres -d sigre -f backend\migracion_administracion_contenidos.sql
psql -U postgres -d sigre -f backend\migracion_notificaciones.sql
psql -U postgres -d sigre -f backend\migracion_participacion_jornadas.sql
psql -U postgres -d sigre -f backend\migracion_fin_jornadas.sql
psql -U postgres -d sigre -f backend\migracion_inventario_centros.sql
psql -U postgres -d sigre -f backend\migracion_fotos_directorio.sql
psql -U postgres -d sigre -f backend\migracion_perfil_completo.sql
psql -U postgres -d sigre -f backend\migracion_recuperacion_contrasenas.sql
psql -U postgres -d sigre -f backend\migracion_verificacion_correo.sql
psql -U postgres -d sigre -f backend\migracion_push.sql
psql -U postgres -d sigre -f backend\migracion_reparar_acentos.sql
```

Si `psql` no se reconoce, usa la ruta completa: `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d sigre -f ...`. Ejecuta los comandos **de uno en uno**: el que pide la contraseña no debe pegarse junto con los demás.

`migracion_reparar_acentos.sql` corrige textos con tildes dañadas (por ejemplo "LÃ­nea"); las demás migraciones ya fijan `client_encoding = 'UTF8'` para que no vuelva a pasar.

Cada integrante debe usar sus propias claves locales. **No subas `backend/.env` a GitHub ni compartas sus contraseñas.**

Cuando PostgreSQL y la base de datos estén configurados, inicia la API desde la raíz del proyecto:

```powershell
python backend\app.py
```

La API se ejecuta en `http://127.0.0.1:5000`. Abre las páginas con Live Server (por ejemplo `http://127.0.0.1:5500/frontend/login.html`); `frontend/js/config.js` las conecta solas con el puerto 5000. Deja abierta la terminal de Flask mientras pruebas: si se cierra, la página muestra "No se pudo conectar con el servidor".

## Cuenta de administrador o entidad

Por seguridad, nadie puede darse el rol de administrador desde la página. El primer administrador se crea con PostgreSQL (cambia el correo por el de una cuenta ya registrada):

```powershell
psql -U postgres -d sigre -c "UPDATE usuarios SET rol = 'autoridad' WHERE email = 'correo@ejemplo.com';"
```

Después, esa persona cierra sesión y vuelve a entrar: el login la lleva a `dashboard_admin.html`. Desde el panel puede asignar los roles de las demás cuentas.

## Rutas de evacuación

El servidor calcula rutas sobre las redes de calles ya preparadas en `backend/datos_rutas/monteria_peatonal.json.gz` y `monteria_vehicular.json.gz`, para usar poca memoria (unos 150 MB). Si cambias las `ZONAS` de riesgo en `backend/rutas.py`, vuelve a prepararlas en tu PC y sube los `.json.gz` a GitHub:

```powershell
python backend\rutas.py
```

Las redes completas de OpenStreetMap (`*.graphml`) se descargan solas la primera vez y quedan solo en tu PC (no se suben).

El notebook `rutas_eva_corregido.ipynb` utiliza OpenStreetMap para explorar la red peatonal y generar un mapa. Para ejecutarlo se necesitan las bibliotecas `osmnx`, `networkx`, `geopandas`, `folium` y `shapely`.

Las zonas del mapa son aproximaciones para el prototipo; no son cartografía oficial ni deben usarse para tomar decisiones reales de emergencia.

## Publicar en internet (Render + Neon)

- **Base de datos:** PostgreSQL en Neon. Se copió la base local con `pg_dump --no-owner` y se cargó con `psql`, después de crear el rol `sigre_app`. El rol dueño debe tener `BYPASSRLS`.
- **Servidor:** Render, *Web Service* con **Root Directory** `backend`, **Build** `pip install -r requirements.txt` y **Start** `gunicorn app:app --workers 1 --threads 4 --timeout 120`.
- **Variables de entorno en Render:** `DB_HOST` (host directo de Neon, sin *-pooler*), `DB_PORT`, `DB_NAME`, `DB_USER=sigre_app`, `DB_PASSWORD`, `DB_SSLMODE=require`, `JWT_SECRET_KEY`, `PYTHON_VERSION=3.12.7`, `FRONTEND_URL=https://sigre.onrender.com`, `MAIL_SCRIPT_URL`, `MAIL_SCRIPT_CLAVE`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` y `VAPID_CONTACTO`.
- Flask entrega también las páginas de `frontend/`, así que todo queda en una sola dirección HTTPS.
- `frontend/js/config.js` decide la dirección de la API: en desarrollo (Live Server, puertos 5500/8000) usa el puerto 5000; publicado, usa la misma dirección de la página.
- SIGRE se instala como app (PWA) con `frontend/manifest.json` y `frontend/service-worker.js`: en Android, Chrome → menú ⋮ → *Instalar aplicación*; en iPhone, Safari → Compartir → *Agregar a inicio*.
- **Avisos push:** en Android funcionan en Chrome y en la app instalada; en iPhone solo con SIGRE instalada en la pantalla de inicio (iOS 16.4 o más nuevo). Cada persona los activa en el menú ☰ y se desactivan al cerrar sesión.
- Cada `git push` a `main` publica los cambios solo en unos minutos.
- **Si agregas una migración nueva, ejecútala también en Neon** (`psql "<cadena de Neon>" -f backend\migracion_nueva.sql`). La base de tu PC y la de internet son distintas: las cuentas y los datos no se comparten.
- **Plan gratis:** el servidor se duerme tras unos 15 minutos sin visitas y la primera carga tarda cerca de un minuto. Tiene 512 MB de memoria.

### Correos en Render (Google Apps Script)

El plan gratis de Render bloquea el SMTP de Gmail, así que los correos los envía un Google Apps Script de la cuenta del proyecto (`sigre.oficial@gmail.com`), llamado por HTTPS. Sin `MAIL_SCRIPT_URL` (en tu PC) se usa SMTP con `MAIL_USERNAME` y `MAIL_APP_PASSWORD`. Los correos salen en segundo plano: la página no espera a Gmail.

1. En script.google.com (con la cuenta del proyecto) crea el proyecto **SIGRE correos** y pega el código de [`backend/apps_script/correos.gs`](backend/apps_script/correos.gs): una función `doPost` que lee `{clave, para, asunto, texto}`, comprueba que `clave` sea igual a la propiedad del script `CLAVE_SIGRE` y envía el correo con `MailApp.sendEmail`.
2. En ⚙️ *Configuración del proyecto* → *Propiedades de las secuencias de comandos*, agrega `CLAVE_SIGRE` con una clave aleatoria (`python -c "import secrets; print(secrets.token_urlsafe(32))"`).
3. Ejecuta una vez una función de prueba para autorizar el envío de correos.
4. *Implementar* → *Nueva implementación* → *Aplicación web*, ejecutar como **Yo** y acceso **Cualquier persona**. Copia la URL que termina en `/exec`.
5. En Render: `MAIL_SCRIPT_URL` = esa URL y `MAIL_SCRIPT_CLAVE` = la misma clave de `CLAVE_SIGRE`. Si los registros dicen "no autorizado", las dos claves no coinciden.

## Base de datos

- **Motor:** PostgreSQL 18.
- **Archivos** (carpeta [`database/`](database)):

| Archivo | Qué es |
|---|---|
| [`schema.sql`](database/schema.sql) | Esquema completo, sacado de la base real con `pg_dump --schema-only`: 19 tablas con llaves primarias, llaves foráneas, restricciones, índices, funciones, disparadores y seguridad por filas. Sin datos. |
| [`datos_demo.sql`](database/datos_demo.sql) | Datos de demostración **inventados** (cuentas, emergencia, centros con inventario, jornadas, solicitudes, desaparecidos y directorio). Se carga sobre `schema.sql`. |
| [`sigre_demo.sql`](database/sigre_demo.sql) | Respaldo completo (`pg_dump`) de una base con el esquema y los datos de demostración. Es la forma más rápida de ver el sistema con información. |

**Restaurar la base de demostración** (con el usuario `postgres`):

```powershell
psql -U postgres -c "CREATE ROLE sigre_app LOGIN PASSWORD 'una-clave-segura';"
psql -U postgres -c "CREATE DATABASE sigre_demo;"
psql -U postgres -d sigre_demo -f database\sigre_demo.sql
```

Si el rol `sigre_app` ya existe, omite la primera línea. Luego, en `backend/.env`, usa `DB_NAME=sigre_demo`, `DB_USER=sigre_app` y su clave.

**Crear una base vacía** (sin datos): igual, pero cargando `database/schema.sql` en lugar de `sigre_demo.sql`. Para una base que ya existe, aplica las migraciones `backend/migracion_*.sql` en el orden de arriba: el esquema es el resultado de aplicarlas todas.

### Credenciales de prueba

Las cuentas de la base de demostración ya tienen el correo verificado:

| Rol | Correo | Contraseña |
|---|---|---|
| Administrador (autoridad) | `admin.demo@sigre.co` | `AdminSigre2026*` |
| Usuario (ciudadano) | `usuario.demo@sigre.co` | `UsuarioSigre2026*` |

También hay tres cuentas de participantes de ejemplo (`laura.martinez@sigre.co`, `carlos.perez@sigre.co` y `ana.gomez@sigre.co`) con la contraseña `DemoSigre2026*`. Son datos de prueba: no uses estas contraseñas en cuentas reales.

## Estado

SIGRE está en desarrollo como proyecto académico.
