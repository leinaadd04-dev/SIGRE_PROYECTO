CREATE TABLE usuarios(
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    rol TEXT NOT NULL CHECK (rol IN ('ciudadano', 'voluntario','autoridad')),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

CREATE TABLE emergencias(
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    alcance TEXT NOT NULL CHECK (alcance IN('departamento', 'municipio', 'sector')),
    departamento TEXT NOT NULL,
    municipio TEXT,
    sector TEXT,
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION,
    nivel_riesgo TEXT NOT NULL CHECK(niverl_riesgo IN('bajo','medio', 'alto', 'critico')),
    estado TEXT NOT NULL DEFAULT 'activa' CHECK (estado IN('activa','finalizada')),
    resgistrada_por BIGINT NOT NULL REFERENCES usuarios(id),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finalizada_por BIGINT REFERENCES usuarios(id),
    finalizada_en TIMESTAMPTZ,

        CONSTRAINT coordenadas_validas CHECK (
        (latitud IS NULL AND longitud IS NULL)
        OR
        (latitud IS NOT NULL AND longitud IS NOT NULL
         AND latitud BETWEEN -90 AND 90
         AND longitud BETWEEN -180 AND 180)
    ),
    CONSTRAINT finalizacion_consistente CHECK (
        (estado = 'activa' AND finalizada_por IS NULL AND finalizada_en IS NULL)
        OR
        (estado = 'finalizada' AND finalizada_por IS NOT NULL AND finalizada_en IS NOT NULL)
    )
);

CREATE TABLE solicitudes_ayuda (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    usuario_id BIGINT NOT NULL REFERENCES usuarios(id),

    tipo_ayuda TEXT NOT NULL,

    titulo TEXT NOT NULL,

    sector TEXT NOT NULL,

    descripcion TEXT NOT NULL,

    personas_afectadas INTEGER NOT NULL
        CHECK (personas_afectadas > 0),

    urgencia TEXT NOT NULL
        CHECK (urgencia IN ('baja', 'media', 'alta', 'critica')),

    ubicacion TEXT NOT NULL,

    evidencia_url TEXT,

    estado TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'en_proceso', 'resuelto')),

    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    actualizada_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);






