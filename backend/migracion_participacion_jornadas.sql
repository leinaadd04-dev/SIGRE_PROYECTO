-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Participación en jornadas comunitarias
--
-- Cada cuenta puede inscribirse ("Quiero participar") en una jornada publicada.
-- Con esto se calculan los avatares de las tarjetas, la lista de quiénes van y
-- la gráfica "Participación por categoría".
--
-- Privacidad: una cuenta normal ve el nombre corto de quienes van (ej. "Ana M.")
-- y su animalito; una cuenta de autoridad ve además el nombre completo, el
-- correo y el teléfono para coordinar la jornada.
--
-- Requiere migracion_administracion.sql y migracion_administracion_contenidos.sql.
-- Ejecútala con el usuario dueño de las tablas (postgres). Se puede repetir.

CREATE TABLE IF NOT EXISTS participaciones_jornadas (
    jornada_id BIGINT NOT NULL REFERENCES jornadas(id) ON DELETE CASCADE,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (jornada_id, usuario_id)
);

CREATE INDEX IF NOT EXISTS idx_participaciones_jornadas_usuario
    ON participaciones_jornadas (usuario_id);

-- Sin políticas ni permisos: sigre_app solo usa las funciones de abajo.
ALTER TABLE participaciones_jornadas ENABLE ROW LEVEL SECURITY;

-- "Ana María Gómez" -> "Ana M."; sin nombre usa el inicio del correo.
CREATE OR REPLACE FUNCTION sigre_nombre_corto(p_nombre TEXT, p_email TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN coalesce(btrim(p_nombre), '') = '' THEN split_part(coalesce(p_email, 'Participante'), '@', 1)
        WHEN (regexp_split_to_array(btrim(p_nombre), '\s+'))[2] IS NULL THEN btrim(p_nombre)
        ELSE (regexp_split_to_array(btrim(p_nombre), '\s+'))[1] || ' ' ||
             upper(left((regexp_split_to_array(btrim(p_nombre), '\s+'))[2], 1)) || '.'
    END;
$$;

-- Inscribe o retira a la cuenta de la sesión. Devuelve el nuevo total.
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
    SELECT j.estado, j.fecha_inicio INTO v_jornada FROM jornadas j WHERE j.id = p_jornada_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La jornada no existe' USING ERRCODE = '22023';
    END IF;

    IF p_participar THEN
        IF v_jornada.estado <> 'publicada' THEN
            RAISE EXCEPTION 'Esta jornada fue cancelada' USING ERRCODE = '22023';
        END IF;
        IF v_jornada.fecha_inicio < NOW() - INTERVAL '12 hours' THEN
            RAISE EXCEPTION 'Esta jornada ya se realizó' USING ERRCODE = '22023';
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

-- Resumen para las tarjetas: total, hasta 4 avatares y si la sesión participa.
-- Sin sesión (app.user_id vacío) no se incluyen nombres.
CREATE OR REPLACE FUNCTION jornadas_participacion(p_ids BIGINT[])
RETURNS TABLE (jornada_id BIGINT, total BIGINT, vista_previa JSONB, participo BOOLEAN)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH yo AS (
        SELECT NULLIF(current_setting('app.user_id', true), '')::BIGINT AS id
    )
    SELECT j.id,
           (SELECT count(*) FROM participaciones_jornadas p WHERE p.jornada_id = j.id),
           CASE WHEN (SELECT id FROM yo) IS NULL THEN '[]'::JSONB ELSE coalesce((
               SELECT jsonb_agg(jsonb_build_object('nombre', v.nombre, 'animal', v.animal) ORDER BY v.creada_en DESC)
               FROM (
                   SELECT sigre_nombre_corto(u.nombre, u.email) AS nombre, a.animal, p.creada_en
                   FROM participaciones_jornadas p
                   JOIN usuarios u ON u.id = p.usuario_id
                   LEFT JOIN avatares_usuario a ON a.usuario_id = u.id AND a.tipo = 'animal'
                   WHERE p.jornada_id = j.id
                   ORDER BY p.creada_en DESC
                   LIMIT 4
               ) v
           ), '[]'::JSONB) END,
           EXISTS (
               SELECT 1 FROM participaciones_jornadas p, yo
               WHERE p.jornada_id = j.id AND p.usuario_id = yo.id
           )
    FROM jornadas j
    WHERE j.id = ANY (p_ids);
$$;

-- Lista completa de quienes van. Contacto solo para autoridades.
CREATE OR REPLACE FUNCTION jornada_participantes(p_jornada_id BIGINT)
RETURNS TABLE (
    nombre TEXT, animal TEXT, email TEXT, telefono TEXT,
    inscrito_en TIMESTAMPTZ, es_yo BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
    v_autoridad BOOLEAN := sigre_usuario_es_autoridad();
BEGIN
    IF v_usuario IS NULL THEN
        RAISE EXCEPTION 'Inicia sesión para ver quiénes participan' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
        SELECT CASE WHEN v_autoridad THEN coalesce(nullif(btrim(u.nombre), ''), u.email)
                    ELSE sigre_nombre_corto(u.nombre, u.email) END,
               a.animal,
               CASE WHEN v_autoridad THEN u.email END,
               CASE WHEN v_autoridad THEN u.telefono END,
               p.creada_en,
               p.usuario_id = v_usuario
        FROM participaciones_jornadas p
        JOIN usuarios u ON u.id = p.usuario_id
        LEFT JOIN avatares_usuario a ON a.usuario_id = u.id AND a.tipo = 'animal'
        WHERE p.jornada_id = p_jornada_id
        ORDER BY p.creada_en
        LIMIT 500;
END;
$$;

-- Gráfica: promedio de personas inscritas por jornada publicada, por categoría.
CREATE OR REPLACE FUNCTION jornadas_estadisticas_categoria()
RETURNS TABLE (categoria TEXT, jornadas BIGINT, participantes BIGINT, promedio NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT c.categoria,
           count(j.id),
           coalesce(sum(t.total), 0)::BIGINT,
           CASE WHEN count(j.id) = 0 THEN 0
                ELSE round(coalesce(sum(t.total), 0)::NUMERIC / count(j.id), 1) END
    FROM (VALUES ('limpieza'), ('salud'), ('solidaridad'), ('apoyo')) AS c(categoria)
    LEFT JOIN jornadas j ON j.categoria = c.categoria AND j.estado = 'publicada'
    LEFT JOIN LATERAL (
        SELECT count(*) AS total FROM participaciones_jornadas p WHERE p.jornada_id = j.id
    ) t ON TRUE
    GROUP BY c.categoria;
$$;

-- Si el admin cambia la fecha o el lugar, avisa a cada persona inscrita.
-- Usa sigre_notificar() de migracion_notificaciones.sql.
CREATE OR REPLACE FUNCTION sigre_notificar_cambio_jornada()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_fecha TEXT := to_char(NEW.fecha_inicio AT TIME ZONE 'America/Bogota', 'DD/MM/YYYY HH12:MI AM');
    v_cambios TEXT;
BEGIN
    IF NEW.estado <> 'publicada'
       OR (OLD.fecha_inicio IS NOT DISTINCT FROM NEW.fecha_inicio AND OLD.lugar IS NOT DISTINCT FROM NEW.lugar) THEN
        RETURN NULL;
    END IF;
    v_cambios := concat_ws(' y ',
        CASE WHEN OLD.fecha_inicio IS DISTINCT FROM NEW.fecha_inicio THEN 'la fecha' END,
        CASE WHEN OLD.lugar IS DISTINCT FROM NEW.lugar THEN 'el lugar' END);
    PERFORM sigre_notificar(p.usuario_id, NULL, 'jornada',
        'Cambió ' || v_cambios || ' de "' || NEW.nombre || '"',
        'Ahora es el ' || v_fecha || ' en ' || NEW.lugar || '. Sigues inscrito.',
        'jornadas.html')
    FROM participaciones_jornadas p
    WHERE p.jornada_id = NEW.id;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_cambio_jornada ON jornadas;
CREATE TRIGGER trg_notificar_cambio_jornada
    AFTER UPDATE OF fecha_inicio, lugar ON jornadas
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_cambio_jornada();

-- ---------- Permisos ----------

REVOKE ALL ON FUNCTION jornada_participar(BIGINT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION jornadas_participacion(BIGINT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION jornada_participantes(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION jornadas_estadisticas_categoria() FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION jornada_participar(BIGINT, BOOLEAN) TO sigre_app;
        GRANT EXECUTE ON FUNCTION jornadas_participacion(BIGINT[]) TO sigre_app;
        GRANT EXECUTE ON FUNCTION jornada_participantes(BIGINT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION jornadas_estadisticas_categoria() TO sigre_app;
    END IF;
END
$$;
