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

CREATE INDEX IF NOT EXISTS idx_reportes_desaparecidos_estado_fecha
    ON reportes_desaparecidos (estado, creado_en DESC);

CREATE INDEX IF NOT EXISTS idx_reportes_desaparecidos_tipo
    ON reportes_desaparecidos (tipo);