-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Módulo "Solicitar ayuda"
-- Cada solicitud pertenece a la cuenta autenticada que la creó.
-- Se puede ejecutar varias veces sin duplicar objetos.

CREATE TABLE IF NOT EXISTS solicitudes_ayuda (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    categoria TEXT NOT NULL CHECK (categoria IN (
        'alimentos', 'atencion_medica', 'alojamiento', 'transporte', 'ropa', 'otra'
    )),
    urgencia TEXT NOT NULL CHECK (urgencia IN ('baja', 'media', 'alta', 'critica')),
    descripcion TEXT NOT NULL CHECK (char_length(descripcion) BETWEEN 10 AND 1200),
    personas_afectadas INTEGER NOT NULL CHECK (personas_afectadas BETWEEN 1 AND 10000),
    direccion TEXT NOT NULL CHECK (char_length(direccion) BETWEEN 5 AND 200),
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION,
    nombre_contacto TEXT NOT NULL CHECK (char_length(nombre_contacto) BETWEEN 2 AND 120),
    telefono_contacto TEXT NOT NULL CHECK (char_length(telefono_contacto) BETWEEN 7 AND 20),
    adjunto BYTEA,
    adjunto_mime TEXT CHECK (adjunto_mime IN (
        'image/jpeg', 'image/png', 'image/webp', 'application/pdf'
    )),
    autoriza_compartir BOOLEAN NOT NULL CHECK (autoriza_compartir = TRUE),
    estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN (
        'pendiente', 'en_revision', 'en_atencion', 'atendida', 'cancelada'
    )),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT solicitud_coordenadas_validas CHECK (
        (latitud IS NULL AND longitud IS NULL)
        OR
        (latitud IS NOT NULL AND longitud IS NOT NULL
         AND latitud BETWEEN -90 AND 90
         AND longitud BETWEEN -180 AND 180)
    ),
    CONSTRAINT solicitud_adjunto_consistente CHECK (
        (adjunto IS NULL AND adjunto_mime IS NULL)
        OR
        (adjunto IS NOT NULL AND adjunto_mime IS NOT NULL
         AND octet_length(adjunto) <= 5 * 1024 * 1024)
    )
);

CREATE INDEX IF NOT EXISTS idx_solicitudes_ayuda_usuario_fecha
    ON solicitudes_ayuda (usuario_id, creada_en DESC);

CREATE INDEX IF NOT EXISTS idx_solicitudes_ayuda_estado_urgencia
    ON solicitudes_ayuda (estado, urgencia);

-- Seguridad por filas: la API fija app.user_id y app.user_role en cada
-- transacción (igual que /api/mi-cuenta). Cada cuenta solo ve y crea sus
-- propias solicitudes; la autoridad puede consultarlas para atenderlas.
ALTER TABLE solicitudes_ayuda ENABLE ROW LEVEL SECURITY;
ALTER TABLE solicitudes_ayuda FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS solicitudes_ayuda_ver ON solicitudes_ayuda;
CREATE POLICY solicitudes_ayuda_ver ON solicitudes_ayuda
    FOR SELECT
    USING (
        usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
        OR current_setting('app.user_role', true) = 'autoridad'
    );

DROP POLICY IF EXISTS solicitudes_ayuda_crear ON solicitudes_ayuda;
CREATE POLICY solicitudes_ayuda_crear ON solicitudes_ayuda
    FOR INSERT
    WITH CHECK (
        usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
    );

-- Permisos para el usuario de la aplicación descrito en el README.
-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en ambas líneas.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT ON solicitudes_ayuda TO sigre_app;
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- Ampliación: solicitudes comunitarias y visitas a vivienda.
-- Segura de ejecutar aunque la tabla ya exista con la versión anterior.
-- ---------------------------------------------------------------------

-- 'ayuda' = solicitud de ayuda; 'visita' = visita del equipo a la vivienda.
ALTER TABLE solicitudes_ayuda
    ADD COLUMN IF NOT EXISTS tipo TEXT NOT NULL DEFAULT 'ayuda';

-- A quiénes beneficia: una comunidad o barrio, un grupo de familias o un hogar.
ALTER TABLE solicitudes_ayuda
    ADD COLUMN IF NOT EXISTS alcance TEXT NOT NULL DEFAULT 'hogar';

ALTER TABLE solicitudes_ayuda
    ADD COLUMN IF NOT EXISTS nombre_comunidad TEXT;

ALTER TABLE solicitudes_ayuda
    ADD COLUMN IF NOT EXISTS motivo_visita TEXT;

ALTER TABLE solicitudes_ayuda
    ADD COLUMN IF NOT EXISTS fecha_visita_preferida DATE;

ALTER TABLE solicitudes_ayuda
    ADD COLUMN IF NOT EXISTS franja_horaria TEXT;

-- Las visitas no usan categoría de ayuda.
ALTER TABLE solicitudes_ayuda ALTER COLUMN categoria DROP NOT NULL;

ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitud_tipo_valido;
ALTER TABLE solicitudes_ayuda ADD CONSTRAINT solicitud_tipo_valido
    CHECK (tipo IN ('ayuda', 'visita'));

ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitud_alcance_valido;
ALTER TABLE solicitudes_ayuda ADD CONSTRAINT solicitud_alcance_valido
    CHECK (alcance IN ('comunidad', 'familias', 'hogar'));

ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitud_comunidad_consistente;
ALTER TABLE solicitudes_ayuda ADD CONSTRAINT solicitud_comunidad_consistente
    CHECK (
        (alcance = 'hogar' AND nombre_comunidad IS NULL)
        OR
        (alcance <> 'hogar' AND char_length(nombre_comunidad) BETWEEN 3 AND 120)
    );

ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitud_visita_valida;
ALTER TABLE solicitudes_ayuda ADD CONSTRAINT solicitud_visita_valida
    CHECK (
        (motivo_visita IS NULL OR motivo_visita IN (
            'evaluar_danos', 'condiciones_vivienda', 'riesgo_estructural',
            'encuesta_social', 'otra'
        ))
        AND
        (franja_horaria IS NULL OR franja_horaria IN ('manana', 'tarde', 'cualquiera'))
    );

ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitud_tipo_consistente;
ALTER TABLE solicitudes_ayuda ADD CONSTRAINT solicitud_tipo_consistente
    CHECK (
        (tipo = 'ayuda' AND categoria IS NOT NULL
         AND motivo_visita IS NULL AND fecha_visita_preferida IS NULL
         AND franja_horaria IS NULL)
        OR
        (tipo = 'visita' AND categoria IS NULL
         AND motivo_visita IS NOT NULL AND fecha_visita_preferida IS NOT NULL
         AND franja_horaria IS NOT NULL)
    );

-- Nuevo estado para cuando el equipo agenda la visita.
ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitudes_ayuda_estado_check;
ALTER TABLE solicitudes_ayuda DROP CONSTRAINT IF EXISTS solicitud_estado_valido;
ALTER TABLE solicitudes_ayuda ADD CONSTRAINT solicitud_estado_valido
    CHECK (estado IN (
        'pendiente', 'en_revision', 'programada', 'en_atencion', 'atendida', 'cancelada'
    ));

CREATE INDEX IF NOT EXISTS idx_solicitudes_ayuda_tipo_alcance
    ON solicitudes_ayuda (tipo, alcance);
