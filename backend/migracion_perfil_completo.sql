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

-- ---------------------------------------------------------------------
-- Permisos y validaciones del perfil (se puede ejecutar varias veces).
--
-- La tabla usuarios tiene seguridad por filas y la aplicación (sigre_app)
-- no puede leer ni cambiar estas columnas directamente. El perfil se lee y
-- se guarda con dos funciones SECURITY DEFINER que solo tocan la fila de la
-- cuenta de la sesión (app.user_id). Así nadie puede ver los datos médicos
-- de otra persona ni cambiar su propio rol.
-- ---------------------------------------------------------------------

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuario_perfil_valido;
ALTER TABLE usuarios ADD CONSTRAINT usuario_perfil_valido CHECK (
    (tipo_documento IS NULL OR tipo_documento IN ('CC', 'TI', 'CE', 'PASAPORTE'))
    AND (numero_documento IS NULL OR char_length(numero_documento) BETWEEN 3 AND 40)
    AND (tipo_sangre IS NULL OR tipo_sangre IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'))
    AND (fecha_nacimiento IS NULL OR fecha_nacimiento >= DATE '1900-01-01')
    AND (alergias IS NULL OR char_length(alergias) <= 3000)
    AND (condiciones_medicas IS NULL OR char_length(condiciones_medicas) <= 3000)
    AND (medicamentos IS NULL OR char_length(medicamentos) <= 3000)
    AND (contacto_emergencia_nombre IS NULL OR char_length(contacto_emergencia_nombre) BETWEEN 2 AND 120)
    AND (contacto_emergencia_telefono IS NULL OR char_length(contacto_emergencia_telefono) BETWEEN 7 AND 30)
    AND (direccion IS NULL OR char_length(direccion) <= 300)
    AND (comunidad IS NULL OR char_length(comunidad) <= 150)
);

CREATE OR REPLACE FUNCTION sigre_mi_perfil()
RETURNS TABLE (
    tipo_documento TEXT, numero_documento TEXT, fecha_nacimiento DATE,
    tipo_sangre TEXT, alergias TEXT, condiciones_medicas TEXT, medicamentos TEXT,
    contacto_emergencia_nombre TEXT, contacto_emergencia_telefono TEXT,
    direccion TEXT, comunidad TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.tipo_documento, u.numero_documento, u.fecha_nacimiento,
           u.tipo_sangre, u.alergias, u.condiciones_medicas, u.medicamentos,
           u.contacto_emergencia_nombre, u.contacto_emergencia_telefono,
           u.direccion, u.comunidad
    FROM usuarios u
    WHERE u.id = NULLIF(current_setting('app.user_id', true), '')::BIGINT;
$$;

CREATE OR REPLACE FUNCTION sigre_guardar_mi_perfil(
    p_tipo_documento TEXT, p_numero_documento TEXT, p_fecha_nacimiento DATE,
    p_tipo_sangre TEXT, p_alergias TEXT, p_condiciones_medicas TEXT, p_medicamentos TEXT,
    p_contacto_emergencia_nombre TEXT, p_contacto_emergencia_telefono TEXT,
    p_direccion TEXT, p_comunidad TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
BEGIN
    IF v_usuario IS NULL THEN
        RAISE EXCEPTION 'Sesión no válida' USING ERRCODE = '42501';
    END IF;
    UPDATE usuarios SET
        tipo_documento = p_tipo_documento,
        numero_documento = p_numero_documento,
        fecha_nacimiento = p_fecha_nacimiento,
        tipo_sangre = p_tipo_sangre,
        alergias = p_alergias,
        condiciones_medicas = p_condiciones_medicas,
        medicamentos = p_medicamentos,
        contacto_emergencia_nombre = p_contacto_emergencia_nombre,
        contacto_emergencia_telefono = p_contacto_emergencia_telefono,
        direccion = p_direccion,
        comunidad = p_comunidad
    WHERE id = v_usuario;
    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION sigre_mi_perfil() FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_guardar_mi_perfil(TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION sigre_mi_perfil() TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_guardar_mi_perfil(TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO sigre_app;
    END IF;
END
$$;
