-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Avatar de la cuenta
-- Cada cuenta puede elegir un animalito de la galería de SIGRE o subir su foto.
-- Se puede ejecutar varias veces sin duplicar objetos.

CREATE TABLE IF NOT EXISTS avatares_usuario (
    usuario_id BIGINT PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL CHECK (tipo IN ('animal', 'foto')),
    animal TEXT CHECK (animal IN (
        'perro', 'gato', 'zorro', 'panda', 'koala', 'leon',
        'rana', 'mono', 'conejo', 'tigre', 'oso', 'buho'
    )),
    foto BYTEA,
    foto_mime TEXT CHECK (foto_mime IN ('image/jpeg', 'image/png', 'image/webp')),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT avatar_consistente CHECK (
        (tipo = 'animal' AND animal IS NOT NULL AND foto IS NULL AND foto_mime IS NULL)
        OR
        (tipo = 'foto' AND animal IS NULL AND foto IS NOT NULL AND foto_mime IS NOT NULL
         AND octet_length(foto) <= 2 * 1024 * 1024)
    )
);

-- Seguridad por filas: la API fija app.user_id en cada transacción.
-- Cada cuenta solo ve y cambia su propio avatar.
ALTER TABLE avatares_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatares_usuario FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS avatares_usuario_propio ON avatares_usuario;
CREATE POLICY avatares_usuario_propio ON avatares_usuario
    FOR ALL
    USING (usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT)
    WITH CHECK (usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT);

-- Permisos para el usuario de la aplicación descrito en el README.
-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en ambas líneas.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON avatares_usuario TO sigre_app;
    END IF;
END
$$;
