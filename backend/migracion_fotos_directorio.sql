-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Foto o logo de las entidades del directorio.
-- Ejecútala con el usuario postgres. Se puede repetir.

ALTER TABLE directorio_entidades ADD COLUMN IF NOT EXISTS foto BYTEA;
ALTER TABLE directorio_entidades ADD COLUMN IF NOT EXISTS foto_mime TEXT;
-- Fecha de la última foto: sirve para que el navegador no muestre la vieja.
ALTER TABLE directorio_entidades ADD COLUMN IF NOT EXISTS foto_actualizada TIMESTAMPTZ;

ALTER TABLE directorio_entidades DROP CONSTRAINT IF EXISTS directorio_foto_valida;
ALTER TABLE directorio_entidades ADD CONSTRAINT directorio_foto_valida CHECK (
    (foto IS NULL AND foto_mime IS NULL)
    OR
    (foto IS NOT NULL
     AND foto_mime IN ('image/jpeg', 'image/png', 'image/webp')
     AND octet_length(foto) <= 1024 * 1024)
);