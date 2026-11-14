SET client_encoding = 'UTF8';

-- SIGRE · Aviso de pánico de SOS en vivo.
-- Cuando el ciudadano pulsa el botón de pánico, las autoridades reciben el aviso
-- en la campana y como notificación push en el celular (aunque la app esté cerrada).
-- Ejecútala con postgres (o neondb_owner en Neon). Se puede ejecutar varias veces.

CREATE OR REPLACE FUNCTION sigre_notificar_panico_sos(p_sesion BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Solo la persona dueña de una emergencia abierta puede dar la alarma.
    IF NOT EXISTS (
        SELECT 1 FROM sesiones_sos
        WHERE id = p_sesion
          AND ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
          AND estado IN ('en_espera', 'en_curso')
    ) THEN
        RETURN;
    END IF;

    PERFORM sigre_notificar(NULL, 'autoridad', 'emergencia',
        'PÁNICO · SOS #' || p_sesion,
        'El ciudadano pulsó el botón de pánico y no puede explicar por llamada. Atiéndelo primero.',
        'dashboard_admin.html#sos');
END;
$$;

REVOKE ALL ON FUNCTION sigre_notificar_panico_sos(BIGINT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION sigre_notificar_panico_sos(BIGINT) TO sigre_app;
    END IF;
END
$$;
