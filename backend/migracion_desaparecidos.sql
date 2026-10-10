-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

CREATE TABLE IF NOT EXISTS reportes_desaparecidos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo TEXT NOT NULL CHECK (tipo IN ('persona', 'animal')),
    nombre TEXT NOT NULL,
    edad TEXT,
    genero TEXT,
    sector TEXT NOT NULL,
    fecha_visto TIMESTAMPTZ,
    descripcion TEXT NOT NULL,
    foto BYTEA NOT NULL,
    foto_mime TEXT NOT NULL CHECK (foto_mime IN ('image/jpeg', 'image/png', 'image/webp')),
    estado TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'encontrado')),
    autoriza_publicacion BOOLEAN NOT NULL CHECK (autoriza_publicacion = TRUE),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Teléfono público de contacto para el reporte y el cartel descargable.
-- También actualiza instalaciones anteriores sin borrar los reportes existentes.
ALTER TABLE reportes_desaparecidos
    ADD COLUMN IF NOT EXISTS telefono_contacto VARCHAR(20);

CREATE INDEX IF NOT EXISTS idx_reportes_desaparecidos_estado_fecha
    ON reportes_desaparecidos (estado, creado_en DESC);

CREATE INDEX IF NOT EXISTS idx_reportes_desaparecidos_tipo
    ON reportes_desaparecidos (tipo);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT (telefono_contacto) ON reportes_desaparecidos TO sigre_app;
        GRANT INSERT (telefono_contacto) ON reportes_desaparecidos TO sigre_app;
    END IF;
END
$$;
