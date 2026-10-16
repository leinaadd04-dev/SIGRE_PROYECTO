-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Recuperación de contraseña por correo.
-- La app (sigre_app) no puede leer ni cambiar usuarios directamente: usa dos
-- funciones SECURITY DEFINER que solo hacen esto. Se puede ejecutar varias veces.

CREATE TABLE IF NOT EXISTS recuperacion_contrasenas (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    -- Se guarda el hash del enlace, nunca el enlace.
    token_hash TEXT NOT NULL UNIQUE CHECK (char_length(token_hash) = 64),
    expira_en TIMESTAMPTZ NOT NULL,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recuperacion_usuario
    ON recuperacion_contrasenas (usuario_id, creado_en DESC);

-- Sin políticas ni permisos: solo las funciones de abajo la usan.
ALTER TABLE recuperacion_contrasenas ENABLE ROW LEVEL SECURITY;

-- Crea un enlace si el correo existe. Devuelve TRUE solo si hay que enviar correo.
CREATE OR REPLACE FUNCTION sigre_crear_recuperacion(p_email TEXT, p_token_hash TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT;
BEGIN
    SELECT id INTO v_usuario FROM usuarios WHERE email = lower(btrim(p_email));
    IF v_usuario IS NULL THEN
        RETURN FALSE;
    END IF;
    -- Máximo 3 correos por hora para la misma cuenta.
    IF (SELECT count(*) FROM recuperacion_contrasenas
        WHERE usuario_id = v_usuario AND creado_en > NOW() - INTERVAL '1 hour') >= 3 THEN
        RETURN FALSE;
    END IF;
    -- Un enlace nuevo anula los anteriores.
    UPDATE recuperacion_contrasenas SET usado = TRUE WHERE usuario_id = v_usuario AND NOT usado;
    INSERT INTO recuperacion_contrasenas (usuario_id, token_hash, expira_en)
    VALUES (v_usuario, p_token_hash, NOW() + INTERVAL '15 minutes');
    RETURN TRUE;
END;
$$;

-- Cambia la contraseña si el enlace es válido. Devuelve FALSE si caducó o ya se usó.
CREATE OR REPLACE FUNCTION sigre_restablecer_contrasena(p_token_hash TEXT, p_password_hash TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id BIGINT;
    v_usuario BIGINT;
BEGIN
    SELECT id, usuario_id INTO v_id, v_usuario
    FROM recuperacion_contrasenas
    WHERE token_hash = p_token_hash AND NOT usado AND expira_en > NOW()
    FOR UPDATE;
    IF v_id IS NULL THEN
        RETURN FALSE;
    END IF;
    UPDATE usuarios SET password_hash = p_password_hash WHERE id = v_usuario;
    UPDATE recuperacion_contrasenas SET usado = TRUE WHERE usuario_id = v_usuario AND NOT usado;
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION sigre_crear_recuperacion(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_restablecer_contrasena(TEXT, TEXT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION sigre_crear_recuperacion(TEXT, TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_restablecer_contrasena(TEXT, TEXT) TO sigre_app;
    END IF;
END
$$;
