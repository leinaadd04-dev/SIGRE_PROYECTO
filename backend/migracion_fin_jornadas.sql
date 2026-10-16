-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Fecha y hora de fin de las jornadas comunitarias.
-- Una jornada termina en su fecha_fin; si no tiene (las anteriores a este
-- cambio), se considera terminada 12 horas después de empezar.
-- Requiere migracion_participacion_jornadas.sql. Se puede ejecutar varias veces.

ALTER TABLE jornadas ADD COLUMN IF NOT EXISTS fecha_fin TIMESTAMPTZ;

ALTER TABLE jornadas DROP CONSTRAINT IF EXISTS jornada_fin_valido;
ALTER TABLE jornadas ADD CONSTRAINT jornada_fin_valido
    CHECK (fecha_fin IS NULL OR fecha_fin > fecha_inicio);

-- Inscribe o retira a la cuenta de la sesión. Devuelve el nuevo total.
-- Se puede inscribir antes de que empiece y mientras está en curso, no después.
CREATE OR REPLACE FUNCTION jornada_participar(p_jornada_id BIGINT, p_participar BOOLEAN)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
    v_jornada RECORD;
BEGIN
    IF v_usuario IS NULL THEN
        RAISE EXCEPTION 'Inicia sesión para participar' USING ERRCODE = '22023';
    END IF;
    SELECT j.estado, coalesce(j.fecha_fin, j.fecha_inicio + INTERVAL '12 hours') AS fin
    INTO v_jornada
    FROM jornadas j WHERE j.id = p_jornada_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La jornada no existe' USING ERRCODE = '22023';
    END IF;

    IF p_participar THEN
        IF v_jornada.estado <> 'publicada' THEN
            RAISE EXCEPTION 'Esta jornada fue cancelada' USING ERRCODE = '22023';
        END IF;
        IF v_jornada.fin <= NOW() THEN
            RAISE EXCEPTION 'Esta jornada ya terminó' USING ERRCODE = '22023';
        END IF;
        INSERT INTO participaciones_jornadas (jornada_id, usuario_id)
        VALUES (p_jornada_id, v_usuario)
        ON CONFLICT DO NOTHING;
    ELSE
        DELETE FROM participaciones_jornadas
        WHERE jornada_id = p_jornada_id AND usuario_id = v_usuario;
    END IF;

    RETURN (SELECT count(*) FROM participaciones_jornadas WHERE jornada_id = p_jornada_id);
END;
$$;
