-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Verificación del correo al registrarse (código de 6 números).
-- Se puede ejecutar varias veces.

-- Las cuentas que ya existen quedan verificadas; las nuevas empiezan sin verificar.
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS email_verificado BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE usuarios ALTER COLUMN email_verificado SET DEFAULT FALSE;

-- Un código vigente por cuenta. Se guarda el hash, nunca el código.
CREATE TABLE IF NOT EXISTS codigos_verificacion (
    usuario_id BIGINT PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
    codigo_hash TEXT NOT NULL CHECK (char_length(codigo_hash) = 64),
    expira_en TIMESTAMPTZ NOT NULL,
    intentos INTEGER NOT NULL DEFAULT 0,
    enviado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sin políticas ni permisos: solo las funciones de abajo la usan.
ALTER TABLE codigos_verificacion ENABLE ROW LEVEL SECURITY;

-- Guarda un código nuevo si la cuenta existe y no está verificada.
-- Devuelve TRUE solo si hay que enviar el correo (máximo uno por minuto).
CREATE OR REPLACE FUNCTION sigre_crear_codigo_verificacion(p_email TEXT, p_codigo_hash TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT;
BEGIN
    SELECT id INTO v_usuario FROM usuarios
    WHERE email = lower(btrim(p_email)) AND NOT email_verificado;
    IF v_usuario IS NULL THEN
        RETURN FALSE;
    END IF;
    IF EXISTS (SELECT 1 FROM codigos_verificacion
               WHERE usuario_id = v_usuario AND enviado_en > NOW() - INTERVAL '1 minute') THEN
        RETURN FALSE;
    END IF;
    INSERT INTO codigos_verificacion (usuario_id, codigo_hash, expira_en, intentos, enviado_en)
    VALUES (v_usuario, p_codigo_hash, NOW() + INTERVAL '10 minutes', 0, NOW())
    ON CONFLICT (usuario_id) DO UPDATE
        SET codigo_hash = EXCLUDED.codigo_hash,
            expira_en = EXCLUDED.expira_en,
            intentos = 0,
            enviado_en = NOW();
    RETURN TRUE;
END;
$$;

-- Comprueba el código. Devuelve: ok, invalido, expirado, bloqueado o ya_verificado.
CREATE OR REPLACE FUNCTION sigre_verificar_correo(p_email TEXT, p_codigo_hash TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT;
    v_verificado BOOLEAN;
    v_codigo RECORD;
BEGIN
    SELECT id, email_verificado INTO v_usuario, v_verificado
    FROM usuarios WHERE email = lower(btrim(p_email));
    IF v_usuario IS NULL THEN
        RETURN 'invalido';
    END IF;
    IF v_verificado THEN
        RETURN 'ya_verificado';
    END IF;

    SELECT * INTO v_codigo FROM codigos_verificacion WHERE usuario_id = v_usuario FOR UPDATE;
    IF NOT FOUND OR v_codigo.expira_en < NOW() THEN
        RETURN 'expirado';
    END IF;
    IF v_codigo.intentos >= 5 THEN
        RETURN 'bloqueado';
    END IF;
    IF v_codigo.codigo_hash <> p_codigo_hash THEN
        UPDATE codigos_verificacion SET intentos = intentos + 1 WHERE usuario_id = v_usuario;
        RETURN 'invalido';
    END IF;

    UPDATE usuarios SET email_verificado = TRUE WHERE id = v_usuario;
    DELETE FROM codigos_verificacion WHERE usuario_id = v_usuario;
    RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION sigre_crear_codigo_verificacion(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_verificar_correo(TEXT, TEXT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION sigre_crear_codigo_verificacion(TEXT, TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_verificar_correo(TEXT, TEXT) TO sigre_app;
        -- El login necesita saber si la cuenta ya está verificada.
        GRANT SELECT (email_verificado) ON usuarios TO sigre_app;
    END IF;
END
$$;
