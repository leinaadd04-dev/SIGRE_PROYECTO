-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Panel de administración (rol 'autoridad': administrador o entidad)
--
-- La aplicación se conecta como sigre_app y la tabla usuarios solo deja ver la
-- fila propia. Por eso la administración usa funciones SECURITY DEFINER que:
--   1. comprueban EN LA BASE que la cuenta de la sesión (app.user_id) tiene rol
--      'autoridad' (no basta con lo que diga el token), y
--   2. nunca devuelven el hash de la contraseña.
-- Ejecútala con el usuario dueño de las tablas (postgres). Se puede repetir.

-- ---------- Comprobación de autoridad ----------

CREATE OR REPLACE FUNCTION sigre_usuario_es_autoridad()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.usuarios
        WHERE id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
          AND rol = 'autoridad'
    );
$$;

CREATE OR REPLACE FUNCTION sigre_exigir_autoridad()
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT sigre_usuario_es_autoridad() THEN
        RAISE EXCEPTION 'Se requiere una cuenta de autoridad' USING ERRCODE = '42501';
    END IF;
    RETURN NULLIF(current_setting('app.user_id', true), '')::BIGINT;
END;
$$;

-- ---------- Resumen ----------

CREATE OR REPLACE FUNCTION admin_resumen()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    RETURN jsonb_build_object(
        'usuarios_total', (SELECT count(*) FROM usuarios),
        'ciudadanos', (SELECT count(*) FROM usuarios WHERE rol = 'ciudadano'),
        'voluntarios', (SELECT count(*) FROM usuarios WHERE rol = 'voluntario'),
        'autoridades', (SELECT count(*) FROM usuarios WHERE rol = 'autoridad'),
        'desaparecidos_activos', (SELECT count(*) FROM reportes_desaparecidos WHERE estado = 'activo'),
        'desaparecidos_encontrados', (SELECT count(*) FROM reportes_desaparecidos WHERE estado = 'encontrado'),
        'centros_abiertos', (SELECT count(*) FROM centros_ayuda WHERE estado = 'abierto'),
        'centros_total', (SELECT count(*) FROM centros_ayuda),
        'solicitudes_pendientes', (SELECT count(*) FROM solicitudes_ayuda WHERE estado = 'pendiente')
    );
END;
$$;

-- ---------- Usuarios ----------

CREATE OR REPLACE FUNCTION admin_listar_usuarios(p_busqueda TEXT)
RETURNS TABLE (
    id BIGINT, email TEXT, nombre TEXT, telefono TEXT, rol TEXT, creado_en TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    RETURN QUERY
        SELECT u.id, u.email, u.nombre, u.telefono, u.rol, u.creado_en
        FROM usuarios u
        WHERE p_busqueda IS NULL
           OR u.email ILIKE '%' || p_busqueda || '%'
           OR u.nombre ILIKE '%' || p_busqueda || '%'
        ORDER BY u.creado_en DESC
        LIMIT 500;
END;
$$;

CREATE OR REPLACE FUNCTION admin_cambiar_rol(p_usuario_id BIGINT, p_rol TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin BIGINT := sigre_exigir_autoridad();
BEGIN
    IF p_rol NOT IN ('ciudadano', 'voluntario', 'autoridad') THEN
        RAISE EXCEPTION 'Rol no válido' USING ERRCODE = '22023';
    END IF;
    -- Evita que el último acceso de administración se quite a sí mismo.
    IF p_usuario_id = v_admin THEN
        RAISE EXCEPTION 'No puedes cambiar tu propio rol' USING ERRCODE = '22023';
    END IF;
    UPDATE usuarios SET rol = p_rol WHERE id = p_usuario_id;
    RETURN FOUND;
END;
$$;

-- ---------- Desaparecidos ----------

CREATE OR REPLACE FUNCTION admin_cambiar_estado_desaparecido(p_reporte_id BIGINT, p_estado TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    IF p_estado NOT IN ('activo', 'encontrado') THEN
        RAISE EXCEPTION 'Estado no válido' USING ERRCODE = '22023';
    END IF;
    UPDATE reportes_desaparecidos
    SET estado = p_estado, actualizado_en = NOW()
    WHERE id = p_reporte_id;
    RETURN FOUND;
END;
$$;

-- Retira el reporte. Sus comentarios, contactos y notificaciones se borran en
-- cascada (claves foráneas ON DELETE CASCADE).
CREATE OR REPLACE FUNCTION admin_eliminar_desaparecido(p_reporte_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    DELETE FROM reportes_desaparecidos WHERE id = p_reporte_id;
    RETURN FOUND;
END;
$$;

-- ---------- Centros de acopio y albergues ----------

CREATE TABLE IF NOT EXISTS centros_ayuda (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre TEXT NOT NULL CHECK (char_length(nombre) BETWEEN 3 AND 120),
    tipo TEXT NOT NULL CHECK (tipo IN ('acopio', 'albergue')),
    direccion TEXT NOT NULL CHECK (char_length(direccion) BETWEEN 3 AND 200),
    descripcion TEXT CHECK (descripcion IS NULL OR char_length(descripcion) <= 600),
    necesidades TEXT CHECK (necesidades IS NULL OR char_length(necesidades) <= 400),
    telefono TEXT CHECK (telefono IS NULL OR char_length(telefono) BETWEEN 7 AND 20),
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION,
    capacidad INTEGER NOT NULL DEFAULT 0 CHECK (capacidad BETWEEN 0 AND 100000),
    ocupados INTEGER NOT NULL DEFAULT 0 CHECK (ocupados >= 0),
    estado TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'cerrado')),
    creado_por BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT centro_ocupacion_valida CHECK (ocupados <= capacidad),
    CONSTRAINT centro_coordenadas_validas CHECK (
        (latitud IS NULL AND longitud IS NULL)
        OR
        (latitud BETWEEN -90 AND 90 AND longitud BETWEEN -180 AND 180)
    )
);

CREATE INDEX IF NOT EXISTS idx_centros_ayuda_tipo_estado ON centros_ayuda (tipo, estado);

-- Todos pueden consultar los centros; solo una autoridad puede crearlos o cambiarlos.
ALTER TABLE centros_ayuda ENABLE ROW LEVEL SECURITY;
ALTER TABLE centros_ayuda FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS centros_ayuda_ver ON centros_ayuda;
CREATE POLICY centros_ayuda_ver ON centros_ayuda
    FOR SELECT USING (true);

DROP POLICY IF EXISTS centros_ayuda_crear ON centros_ayuda;
CREATE POLICY centros_ayuda_crear ON centros_ayuda
    FOR INSERT WITH CHECK (sigre_usuario_es_autoridad());

DROP POLICY IF EXISTS centros_ayuda_editar ON centros_ayuda;
CREATE POLICY centros_ayuda_editar ON centros_ayuda
    FOR UPDATE USING (sigre_usuario_es_autoridad()) WITH CHECK (sigre_usuario_es_autoridad());

DROP POLICY IF EXISTS centros_ayuda_eliminar ON centros_ayuda;
CREATE POLICY centros_ayuda_eliminar ON centros_ayuda
    FOR DELETE USING (sigre_usuario_es_autoridad());

-- ---------- Permisos ----------

REVOKE ALL ON FUNCTION sigre_usuario_es_autoridad() FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_exigir_autoridad() FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_resumen() FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_listar_usuarios(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_cambiar_rol(BIGINT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_cambiar_estado_desaparecido(BIGINT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_eliminar_desaparecido(BIGINT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON centros_ayuda TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_usuario_es_autoridad() TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_exigir_autoridad() TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_resumen() TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_listar_usuarios(TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_cambiar_rol(BIGINT, TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_cambiar_estado_desaparecido(BIGINT, TEXT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION admin_eliminar_desaparecido(BIGINT) TO sigre_app;
    END IF;
END
$$;
