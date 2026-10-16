-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Notificaciones push (llegan al celular aunque la app esté cerrada).
--
-- Cada celular o navegador que acepta las notificaciones guarda aquí su
-- "dirección" de push. Cuando se crea una notificación (los disparadores de
-- migracion_notificaciones.sql), el servidor la envía a los celulares de las
-- cuentas que deben recibirla y la marca como enviada.
--
-- Requiere migracion_notificaciones.sql. Ejecútala con postgres. Se puede repetir.

CREATE TABLE IF NOT EXISTS suscripciones_push (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL UNIQUE CHECK (char_length(endpoint) BETWEEN 10 AND 1000),
    p256dh TEXT NOT NULL CHECK (char_length(p256dh) BETWEEN 10 AND 200),
    auth TEXT NOT NULL CHECK (char_length(auth) BETWEEN 10 AND 100),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suscripciones_push_usuario ON suscripciones_push (usuario_id);

-- Sin políticas ni permisos: solo las funciones de abajo la usan.
ALTER TABLE suscripciones_push ENABLE ROW LEVEL SECURITY;

-- Las notificaciones que ya existían quedan como enviadas (no se mandan de golpe).
ALTER TABLE notificaciones ADD COLUMN IF NOT EXISTS push_enviada BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE notificaciones ALTER COLUMN push_enviada SET DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_notificaciones_push_pendientes
    ON notificaciones (creada_en) WHERE NOT push_enviada;

-- Guarda el celular de la cuenta de la sesión. Si ese celular ya estaba
-- inscrito con otra cuenta (otra persona inició sesión ahí), pasa a esta.
CREATE OR REPLACE FUNCTION sigre_guardar_suscripcion_push(p_endpoint TEXT, p_p256dh TEXT, p_auth TEXT)
RETURNS VOID
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
    INSERT INTO suscripciones_push (usuario_id, endpoint, p256dh, auth)
    VALUES (v_usuario, p_endpoint, p_p256dh, p_auth)
    ON CONFLICT (endpoint) DO UPDATE
        SET usuario_id = EXCLUDED.usuario_id, p256dh = EXCLUDED.p256dh,
            auth = EXCLUDED.auth, creada_en = NOW();
END;
$$;

-- Quita un celular de la cuenta de la sesión (al desactivar o cerrar sesión).
CREATE OR REPLACE FUNCTION sigre_borrar_suscripcion_push(p_endpoint TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    DELETE FROM suscripciones_push
    WHERE endpoint = p_endpoint
      AND usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT;
$$;

-- El servicio de push avisó que ese celular ya no existe (desinstaló la app).
CREATE OR REPLACE FUNCTION sigre_descartar_suscripcion_push(p_endpoint TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    DELETE FROM suscripciones_push WHERE endpoint = p_endpoint;
$$;

-- Toma las notificaciones de las últimas 24 horas que aún no se enviaron como
-- push, las marca como enviadas y devuelve a qué celulares mandarlas.
-- Mismas reglas que la campana (sigre_mis_notificaciones): las propias de cada
-- cuenta y los avisos generales para su rol, publicados después de crearla.
CREATE OR REPLACE FUNCTION sigre_push_pendientes()
RETURNS TABLE (endpoint TEXT, p256dh TEXT, auth TEXT, tipo TEXT,
               titulo TEXT, mensaje TEXT, enlace TEXT, notificacion_id BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH pendientes AS (
        UPDATE notificaciones SET push_enviada = TRUE
        WHERE NOT push_enviada AND creada_en > NOW() - INTERVAL '1 day'
        RETURNING id, destinatario_id, rol_destino, tipo, titulo, mensaje, enlace, creada_en
    )
    SELECT s.endpoint, s.p256dh, s.auth, p.tipo, p.titulo, p.mensaje, p.enlace, p.id
    FROM pendientes p
    JOIN usuarios u ON (
        u.id = p.destinatario_id
        OR (p.destinatario_id IS NULL
            AND (p.rol_destino IS NULL OR p.rol_destino = u.rol)
            AND u.creado_en <= p.creada_en)
    )
    JOIN suscripciones_push s ON s.usuario_id = u.id;
$$;

REVOKE ALL ON FUNCTION sigre_guardar_suscripcion_push(TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_borrar_suscripcion_push(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_descartar_suscripcion_push(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_push_pendientes() FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION sigre_guardar_suscripcion_push(TEXT, TEXT, TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_borrar_suscripcion_push(TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_descartar_suscripcion_push(TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_push_pendientes() TO sigre_app;
    END IF;
END
$$;
