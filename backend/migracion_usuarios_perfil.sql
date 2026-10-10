-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Nombre y teléfono de la cuenta
-- Los pide registro.html y el dashboard muestra el nombre.
-- Se puede ejecutar varias veces sin duplicar objetos.

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS nombre TEXT;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS telefono TEXT;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS google_sub TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_google_sub
    ON usuarios (google_sub) WHERE google_sub IS NOT NULL;

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuario_nombre_valido;
ALTER TABLE usuarios ADD CONSTRAINT usuario_nombre_valido
    CHECK (nombre IS NULL OR char_length(nombre) BETWEEN 2 AND 120);

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuario_telefono_valido;
ALTER TABLE usuarios ADD CONSTRAINT usuario_telefono_valido
    CHECK (telefono IS NULL OR char_length(telefono) BETWEEN 7 AND 20);

-- La aplicación necesita leer y guardar las columnas nuevas.
-- Si los permisos de usuarios se dieron por columna, las nuevas no los tienen.
-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en las dos líneas GRANT.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT INSERT (nombre, telefono) ON usuarios TO sigre_app;
        GRANT SELECT (nombre, telefono, google_sub) ON usuarios TO sigre_app;
        GRANT INSERT (google_sub) ON usuarios TO sigre_app;
        GRANT UPDATE (google_sub) ON usuarios TO sigre_app;
    END IF;
END
$$;
