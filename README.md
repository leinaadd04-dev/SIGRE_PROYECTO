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
- `GET /api/mi-cuenta`: devuelve los datos de la cuenta autenticada.
- `GET /api/emergencias`: consulta emergencias con autenticación.

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
python -m pip install Flask "psycopg[binary]" python-dotenv Flask-JWT-Extended
```

Crea `backend/.env` con la configuración local de tu computadora:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=sigre
DB_USER=sigre_app
DB_PASSWORD=tu_clave_local
JWT_SECRET_KEY=tu_clave_secreta_local
```

Cada integrante debe usar sus propias claves locales. **No subas `backend/.env` a GitHub ni compartas sus contraseñas.**

Cuando PostgreSQL y la base de datos estén configurados, inicia la API desde la raíz del proyecto:

```powershell
python backend\app.py
```

La aplicación se ejecuta localmente en `http://127.0.0.1:5000`.

## Notebook de rutas

El notebook utiliza OpenStreetMap para explorar la red peatonal y generar un mapa. Para ejecutarlo se necesitan las bibliotecas `osmnx`, `networkx`, `geopandas`, `folium` y `shapely`.

Las zonas del mapa son aproximaciones para el prototipo; no son cartografía oficial ni deben usarse para tomar decisiones reales de emergencia.

## Estado

SIGRE está en desarrollo. La configuración completa de PostgreSQL para una computadora nueva todavía debe documentarse junto con el esquema, los permisos y las políticas de seguridad.
