import os
import psycopg
from dotenv import load_dotenv

load_dotenv()

def obtener_conexion():
    return psycopg.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        # En tu PC no hace falta SSL; en internet (Neon) usa DB_SSLMODE=require.
        sslmode=os.getenv("DB_SSLMODE", "prefer"),
    )
