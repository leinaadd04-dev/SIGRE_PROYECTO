# SIGRE

Sistema de Gestión de Riesgos y Emergencias. Prototipo académico para registrar y consultar emergencias, pedir ayuda, encontrar rutas de evacuación y organizar a la comunidad en Montería, Córdoba. El proyecto forma parte de una iniciativa relacionada con el ODS 11.

- **Publicado en:** https://sigre.onrender.com (se puede instalar como app en el celular).
- **Repositorio:** https://github.com/leinaadd04-dev/SIGRE_PROYECTO

## Componentes

- `backend/`: API en Flask con PostgreSQL. También entrega las páginas de `frontend/` cuando está publicada.
  - `app.py`: cuentas, perfil, desaparecidos, solicitudes de ayuda y correos.
  - `administracion.py`: panel de administración, centros, inventario, directorio, jornadas y emergencias.
  - `notificaciones.py`: campana de notificaciones.
  - `rutas.py`: rutas de evacuación sobre las calles de Montería.
  - `migracion_*.sql`: cambios de la base de datos (ver más abajo).
  - `datos_rutas/*.json.gz`: redes de calles de Montería ya preparadas para el servidor.
- `frontend/`: páginas web (HTML, CSS y JavaScript).
- `rutas_eva_corregido.ipynb`: notebook para explorar rutas peatonales con OpenStreetMap.
- `mapa_rutas.html`: mapa generado por el notebook.

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
- **Campana de notificaciones**, **chatbot** de preguntas frecuentes y botón **SOS** (llama al 123).
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

Crea `backend/.env` con la configuración local de tu computadora:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=sigre
DB_USER=sigre_app
DB_PASSWORD=tu_clave_local
JWT_SECRET_KEY=tu_clave_secreta_local

# Correos (código de verificación y recuperación de contraseña)
MAIL_USERNAME=correo-del-proyecto@gmail.com
MAIL_APP_PASSWORD=contraseña-de-aplicacion-de-gmail-sin-espacios
FRONTEND_URL=http://127.0.0.1:5500/frontend
```

- `MAIL_APP_PASSWORD` no es la contraseña normal de Gmail: se crea en https://myaccount.google.com/apppasswords (la cuenta necesita verificación en 2 pasos).
- `FRONTEND_URL` es la dirección donde abres las páginas; se usa para el enlace del correo de recuperación.
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
- **Variables de entorno en Render:** `DB_HOST` (host directo de Neon, sin *-pooler*), `DB_PORT`, `DB_NAME`, `DB_USER=sigre_app`, `DB_PASSWORD`, `DB_SSLMODE=require`, `JWT_SECRET_KEY`, `PYTHON_VERSION=3.12.7`, `FRONTEND_URL=https://sigre.onrender.com`, `MAIL_SCRIPT_URL` y `MAIL_SCRIPT_CLAVE`.
- Flask entrega también las páginas de `frontend/`, así que todo queda en una sola dirección HTTPS.
- `frontend/js/config.js` decide la dirección de la API: en desarrollo (Live Server, puertos 5500/8000) usa el puerto 5000; publicado, usa la misma dirección de la página.
- SIGRE se instala como app (PWA) con `frontend/manifest.json` y `frontend/service-worker.js`: en Android, Chrome → menú ⋮ → *Instalar aplicación*; en iPhone, Safari → Compartir → *Agregar a inicio*.
- Cada `git push` a `main` publica los cambios solo en unos minutos.
- **Si agregas una migración nueva, ejecútala también en Neon** (`psql "<cadena de Neon>" -f backend\migracion_nueva.sql`). La base de tu PC y la de internet son distintas: las cuentas y los datos no se comparten.
- **Plan gratis:** el servidor se duerme tras unos 15 minutos sin visitas y la primera carga tarda cerca de un minuto. Tiene 512 MB de memoria.

### Correos en Render (Google Apps Script)

El plan gratis de Render bloquea el SMTP de Gmail, así que los correos los envía un Google Apps Script de la cuenta del proyecto (`sigre.oficial@gmail.com`), llamado por HTTPS. Sin `MAIL_SCRIPT_URL` (en tu PC) se usa SMTP con `MAIL_USERNAME` y `MAIL_APP_PASSWORD`. Los correos salen en segundo plano: la página no espera a Gmail.

1. En script.google.com (con la cuenta del proyecto) crea el proyecto **SIGRE correos** con una función `doPost` que lee `{clave, para, asunto, texto}`, comprueba que `clave` sea igual a la propiedad del script `CLAVE_SIGRE` y envía el correo con `MailApp.sendEmail`.
2. En ⚙️ *Configuración del proyecto* → *Propiedades de las secuencias de comandos*, agrega `CLAVE_SIGRE` con una clave aleatoria (`python -c "import secrets; print(secrets.token_urlsafe(32))"`).
3. Ejecuta una vez una función de prueba para autorizar el envío de correos.
4. *Implementar* → *Nueva implementación* → *Aplicación web*, ejecutar como **Yo** y acceso **Cualquier persona**. Copia la URL que termina en `/exec`.
5. En Render: `MAIL_SCRIPT_URL` = esa URL y `MAIL_SCRIPT_CLAVE` = la misma clave de `CLAVE_SIGRE`. Si los registros dicen "no autorizado", las dos claves no coinciden.

## Estado

SIGRE está en desarrollo. Falta documentar la creación inicial de la base en una computadora nueva (el rol `sigre_app`, sus permisos y las políticas de seguridad de la tabla `usuarios`); mientras tanto, lo más seguro es copiar una base que ya funcione con `pg_dump`.
