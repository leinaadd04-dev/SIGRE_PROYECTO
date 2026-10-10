SET client_encoding = 'UTF8';

ALTER TABLE usuarios
    ADD COLUMN IF NOT EXISTS tipo_documento TEXT,
    ADD COLUMN IF NOT EXISTS numero_documento TEXT,
    ADD COLUMN IF NOT EXISTS fecha_nacimiento DATE,
    ADD COLUMN IF NOT EXISTS tipo_sangre TEXT,
    ADD COLUMN IF NOT EXISTS alergias TEXT,
    ADD COLUMN IF NOT EXISTS condiciones_medicas TEXT,
    ADD COLUMN IF NOT EXISTS medicamentos TEXT,
    ADD COLUMN IF NOT EXISTS contacto_emergencia_nombre TEXT,
    ADD COLUMN IF NOT EXISTS contacto_emergencia_telefono TEXT,
    ADD COLUMN IF NOT EXISTS direccion TEXT,
    ADD COLUMN IF NOT EXISTS comunidad TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_numero_documento
    ON usuarios (numero_documento)
    WHERE numero_documento IS NOT NULL AND numero_documento <> '';
