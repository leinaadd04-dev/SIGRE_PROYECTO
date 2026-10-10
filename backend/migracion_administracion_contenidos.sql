-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Panel de administración, parte 2
-- Solicitudes de ayuda (cartas), directorio de entidades, jornadas y emergencias.
-- Requiere migracion_administracion.sql (usa sigre_exigir_autoridad).
-- Ejecútala con el usuario dueño de las tablas (postgres). Se puede repetir.

-- ---------- Solicitudes de ayuda ----------

CREATE OR REPLACE FUNCTION admin_listar_solicitudes(p_estado TEXT)
RETURNS TABLE (
    id BIGINT, tipo TEXT, alcance TEXT, nombre_comunidad TEXT, categoria TEXT,
    motivo_visita TEXT, fecha_visita_preferida DATE, franja_horaria TEXT,
    urgencia TEXT, descripcion TEXT, personas_afectadas INTEGER, direccion TEXT,
    latitud DOUBLE PRECISION, longitud DOUBLE PRECISION,
    nombre_contacto TEXT, telefono_contacto TEXT, adjunto_mime TEXT,
    estado TEXT, creada_en TIMESTAMPTZ, actualizada_en TIMESTAMPTZ,
    cuenta_email TEXT, cuenta_nombre TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    RETURN QUERY
        SELECT s.id, s.tipo, s.alcance, s.nombre_comunidad, s.categoria,
               s.motivo_visita, s.fecha_visita_preferida, s.franja_horaria,
               s.urgencia, s.descripcion, s.personas_afectadas, s.direccion,
               s.latitud, s.longitud, s.nombre_contacto, s.telefono_contacto,
               s.adjunto_mime, s.estado, s.creada_en, s.actualizada_en,
               u.email, u.nombre
        FROM solicitudes_ayuda s
        JOIN usuarios u ON u.id = s.usuario_id
        WHERE p_estado IS NULL OR s.estado = p_estado
        ORDER BY
            CASE s.urgencia WHEN 'critica' THEN 0 WHEN 'alta' THEN 1 WHEN 'media' THEN 2 ELSE 3 END,
            s.creada_en DESC
        LIMIT 300;
END;
$$;

CREATE OR REPLACE FUNCTION admin_cambiar_estado_solicitud(p_solicitud_id BIGINT, p_estado TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    IF p_estado NOT IN ('pendiente', 'en_revision', 'programada', 'en_atencion', 'atendida', 'cancelada') THEN
        RAISE EXCEPTION 'Estado no válido' USING ERRCODE = '22023';
    END IF;
    UPDATE solicitudes_ayuda SET estado = p_estado, actualizada_en = NOW()
    WHERE id = p_solicitud_id;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION admin_adjunto_solicitud(p_solicitud_id BIGINT)
RETURNS TABLE (adjunto BYTEA, adjunto_mime TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    RETURN QUERY
        SELECT s.adjunto, s.adjunto_mime FROM solicitudes_ayuda s
        WHERE s.id = p_solicitud_id AND s.adjunto IS NOT NULL;
END;
$$;

-- ---------- Directorio de entidades ----------

CREATE TABLE IF NOT EXISTS directorio_entidades (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grupo TEXT NOT NULL CHECK (grupo IN ('emergencias', 'estado', 'salud', 'comunidad')),
    nombre TEXT NOT NULL CHECK (char_length(nombre) BETWEEN 2 AND 120),
    detalle TEXT CHECK (detalle IS NULL OR char_length(detalle) <= 300),
    telefono TEXT CHECK (telefono IS NULL OR char_length(telefono) BETWEEN 3 AND 20),
    direccion TEXT CHECK (direccion IS NULL OR char_length(direccion) <= 200),
    web TEXT CHECK (web IS NULL OR (char_length(web) <= 300 AND web ~ '^https://')),
    orden INTEGER NOT NULL DEFAULT 100,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Datos iniciales: los mismos que tenía el directorio del dashboard (revisados en octubre de 2026).
-- Solo se insertan si la tabla está vacía.
INSERT INTO directorio_entidades (grupo, nombre, detalle, telefono, direccion, web, orden)
SELECT * FROM (VALUES
    ('emergencias', 'Línea única de emergencias', 'Policía, ambulancias, bomberos y organismos de socorro.', '123', NULL, NULL, 1),
    ('emergencias', 'Policía Nacional', 'Atención de emergencias y seguridad a través de la línea 123.', '123', NULL, NULL, 2),
    ('emergencias', 'Bomberos', 'Incendios, rescates y materiales peligrosos.', '119', NULL, NULL, 3),
    ('emergencias', 'Cruz Roja Colombiana', 'Atención prehospitalaria y ayuda humanitaria.', '132', NULL, 'https://www.cruzrojacolombiana.org', 4),
    ('emergencias', 'Defensa Civil Colombiana', 'Búsqueda, rescate y apoyo en desastres.', '144', NULL, 'https://www.defensacivil.gov.co', 5),
    ('estado', 'Prosperidad Social', 'Programas sociales y subsidios. Línea gratuita nacional.', '01 8000 951100', NULL, 'https://prosperidadsocial.gov.co', 10),
    ('estado', 'DANE', 'Estadísticas y censos. Línea gratuita nacional, lunes a viernes de 8 a. m. a 5 p. m.', '01 8000 912002', NULL, 'https://www.dane.gov.co', 11),
    ('estado', 'UNGRD · Gestión del riesgo', 'Unidad Nacional para la Gestión del Riesgo de Desastres.', NULL, NULL, 'https://portal.gestiondelriesgo.gov.co', 12),
    ('salud', 'E.S.E. Hospital San Jerónimo de Montería', NULL, NULL, 'Carrera 14 # 22-200', NULL, 20),
    ('salud', 'Clínica Zayma', NULL, NULL, 'Calle 28 # 7-11, Centro', NULL, 21),
    ('salud', 'Clínica Central O.H.L.', NULL, NULL, 'Carrera 6 # 30-36', NULL, 22),
    ('salud', 'Clínica Montería', NULL, NULL, 'Calle 30 # 3-19', NULL, 23),
    ('salud', 'Clínica Materno Infantil Casa del Niño', NULL, NULL, 'Calle 39 # 6-15, Centro', NULL, 24),
    ('salud', 'Clínica Universitaria Medicina Integral', NULL, NULL, 'Calle 42 # 14A-73', NULL, 25)
) AS datos
WHERE NOT EXISTS (SELECT 1 FROM directorio_entidades);

ALTER TABLE directorio_entidades ENABLE ROW LEVEL SECURITY;
ALTER TABLE directorio_entidades FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS directorio_ver ON directorio_entidades;
CREATE POLICY directorio_ver ON directorio_entidades FOR SELECT USING (true);
DROP POLICY IF EXISTS directorio_crear ON directorio_entidades;
CREATE POLICY directorio_crear ON directorio_entidades FOR INSERT WITH CHECK (sigre_usuario_es_autoridad());
DROP POLICY IF EXISTS directorio_editar ON directorio_entidades;
CREATE POLICY directorio_editar ON directorio_entidades FOR UPDATE
    USING (sigre_usuario_es_autoridad()) WITH CHECK (sigre_usuario_es_autoridad());
DROP POLICY IF EXISTS directorio_eliminar ON directorio_entidades;
CREATE POLICY directorio_eliminar ON directorio_entidades FOR DELETE USING (sigre_usuario_es_autoridad());

-- ---------- Jornadas comunitarias ----------

CREATE TABLE IF NOT EXISTS jornadas (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre TEXT NOT NULL CHECK (char_length(nombre) BETWEEN 3 AND 120),
    categoria TEXT NOT NULL CHECK (categoria IN ('limpieza', 'salud', 'solidaridad', 'apoyo')),
    descripcion TEXT NOT NULL CHECK (char_length(descripcion) BETWEEN 10 AND 600),
    fecha_inicio TIMESTAMPTZ NOT NULL,
    lugar TEXT NOT NULL CHECK (char_length(lugar) BETWEEN 3 AND 200),
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION,
    estado TEXT NOT NULL DEFAULT 'publicada' CHECK (estado IN ('publicada', 'cancelada')),
    creada_por BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT jornada_coordenadas_validas CHECK (
        (latitud IS NULL AND longitud IS NULL)
        OR (latitud BETWEEN -90 AND 90 AND longitud BETWEEN -180 AND 180)
    )
);

CREATE INDEX IF NOT EXISTS idx_jornadas_fecha ON jornadas (estado, fecha_inicio);

ALTER TABLE jornadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE jornadas FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS jornadas_ver ON jornadas;
CREATE POLICY jornadas_ver ON jornadas FOR SELECT USING (true);
DROP POLICY IF EXISTS jornadas_crear ON jornadas;
CREATE POLICY jornadas_crear ON jornadas FOR INSERT WITH CHECK (sigre_usuario_es_autoridad());
DROP POLICY IF EXISTS jornadas_editar ON jornadas;
CREATE POLICY jornadas_editar ON jornadas FOR UPDATE
    USING (sigre_usuario_es_autoridad()) WITH CHECK (sigre_usuario_es_autoridad());
DROP POLICY IF EXISTS jornadas_eliminar ON jornadas;
CREATE POLICY jornadas_eliminar ON jornadas FOR DELETE USING (sigre_usuario_es_autoridad());

-- ---------- Emergencias (la tabla ya existe en schema.sql) ----------

-- Emergencia activa más reciente, para la tarjeta del dashboard. Solo datos públicos.
CREATE OR REPLACE FUNCTION emergencia_activa_publica()
RETURNS TABLE (
    id BIGINT, tipo TEXT, descripcion TEXT, alcance TEXT, departamento TEXT,
    municipio TEXT, sector TEXT, nivel_riesgo TEXT, creada_en TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT e.id, e.tipo, e.descripcion, e.alcance, e.departamento, e.municipio,
           e.sector, e.nivel_riesgo, e.creada_en
    FROM emergencias e
    WHERE e.estado = 'activa'
    ORDER BY CASE e.nivel_riesgo WHEN 'critico' THEN 0 WHEN 'alto' THEN 1 WHEN 'medio' THEN 2 ELSE 3 END,
             e.creada_en DESC
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION admin_crear_emergencia(
    p_tipo TEXT, p_descripcion TEXT, p_alcance TEXT, p_departamento TEXT,
    p_municipio TEXT, p_sector TEXT, p_nivel_riesgo TEXT,
    p_latitud DOUBLE PRECISION, p_longitud DOUBLE PRECISION
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin BIGINT := sigre_exigir_autoridad();
    v_id BIGINT;
BEGIN
    INSERT INTO emergencias (tipo, descripcion, alcance, departamento, municipio, sector,
                             nivel_riesgo, latitud, longitud, registrada_por)
    VALUES (p_tipo, p_descripcion, p_alcance, p_departamento, p_municipio, p_sector,
            p_nivel_riesgo, p_latitud, p_longitud, v_admin)
    RETURNING emergencias.id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION admin_finalizar_emergencia(p_emergencia_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin BIGINT := sigre_exigir_autoridad();
BEGIN
    UPDATE emergencias
    SET estado = 'finalizada', finalizada_por = v_admin, finalizada_en = NOW(), actualizada_en = NOW()
    WHERE id = p_emergencia_id AND estado = 'activa';
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION admin_listar_emergencias()
RETURNS TABLE (
    id BIGINT, tipo TEXT, descripcion TEXT, alcance TEXT, departamento TEXT,
    municipio TEXT, sector TEXT, nivel_riesgo TEXT, estado TEXT,
    creada_en TIMESTAMPTZ, finalizada_en TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    RETURN QUERY
        SELECT e.id, e.tipo, e.descripcion, e.alcance, e.departamento, e.municipio,
               e.sector, e.nivel_riesgo, e.estado, e.creada_en, e.finalizada_en
        FROM emergencias e
        ORDER BY (e.estado = 'activa') DESC, e.creada_en DESC
        LIMIT 100;
END;
$$;

-- ---------- Permisos ----------

REVOKE ALL ON FUNCTION admin_listar_solicitudes(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_cambiar_estado_solicitud(BIGINT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_adjunto_solicitud(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION emergencia_activa_publica() FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_crear_emergencia(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_finalizar_emergencia(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_listar_emergencias() FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON directorio_entidades TO sigre_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON jornadas TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_listar_solicitudes(TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_cambiar_estado_solicitud(BIGINT, TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_adjunto_solicitud(BIGINT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION emergencia_activa_publica() TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_crear_emergencia(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_finalizar_emergencia(BIGINT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_listar_emergencias() TO sigre_app;
    END IF;
END
$$;
