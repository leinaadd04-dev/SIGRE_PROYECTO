-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Rutas de evacuación guardadas por cada cuenta
-- Se puede ejecutar varias veces sin duplicar objetos.

CREATE TABLE IF NOT EXISTS rutas_guardadas (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    nombre TEXT NOT NULL CHECK (char_length(nombre) BETWEEN 2 AND 80),
    origen_lat DOUBLE PRECISION NOT NULL CHECK (origen_lat BETWEEN -90 AND 90),
    origen_lon DOUBLE PRECISION NOT NULL CHECK (origen_lon BETWEEN -180 AND 180),
    origen_texto TEXT NOT NULL CHECK (char_length(origen_texto) BETWEEN 1 AND 200),
    destino_lat DOUBLE PRECISION NOT NULL CHECK (destino_lat BETWEEN -90 AND 90),
    destino_lon DOUBLE PRECISION NOT NULL CHECK (destino_lon BETWEEN -180 AND 180),
    destino_texto TEXT NOT NULL CHECK (char_length(destino_texto) BETWEEN 1 AND 200),
    incluye_demo BOOLEAN NOT NULL DEFAULT FALSE,
    distancia_m INTEGER NOT NULL CHECK (distancia_m >= 0),
    tiempo_min INTEGER NOT NULL CHECK (tiempo_min >= 0),
    metros_riesgo INTEGER NOT NULL CHECK (metros_riesgo >= 0),
    geometria JSONB NOT NULL CHECK (jsonb_typeof(geometria) = 'array'),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rutas_guardadas_usuario_fecha
    ON rutas_guardadas (usuario_id, creada_en DESC);

-- Seguridad por filas: cada cuenta solo ve, crea y borra sus propias rutas.
ALTER TABLE rutas_guardadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE rutas_guardadas FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rutas_guardadas_propias ON rutas_guardadas;
CREATE POLICY rutas_guardadas_propias ON rutas_guardadas
    FOR ALL
    USING (usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT)
    WITH CHECK (usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT);

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en ambas líneas.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT, DELETE ON rutas_guardadas TO sigre_app;
    END IF;
END
$$;

-- Medio de transporte de la ruta: a pie, en carro o en moto.
ALTER TABLE rutas_guardadas
    ADD COLUMN IF NOT EXISTS modo TEXT NOT NULL DEFAULT 'pie';

ALTER TABLE rutas_guardadas DROP CONSTRAINT IF EXISTS ruta_modo_valido;
ALTER TABLE rutas_guardadas ADD CONSTRAINT ruta_modo_valido
    CHECK (modo IN ('pie', 'carro', 'moto'));
