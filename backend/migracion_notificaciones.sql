-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Notificaciones de la campana
--
-- Las notificaciones las crean disparadores (triggers) en la base, así que se
-- generan sin importar desde qué parte de la aplicación ocurra el cambio:
--   * Para todas las cuentas: nueva emergencia activa o finalizada, nueva
--     jornada o jornada cancelada, nuevo reporte de desaparecido o reporte
--     encontrado, nuevo centro de acopio o albergue.
--   * Para una cuenta: cambio de estado de su solicitud de ayuda, comentario
--     en su reporte de desaparecido, cambio de su rol.
--   * Para las autoridades: nueva solicitud de ayuda.
--
-- La aplicación (sigre_app) no toca las tablas directamente: lee y marca como
-- leídas con funciones SECURITY DEFINER que usan app.user_id de la sesión.
-- Requiere las migraciones anteriores. Ejecútala con el usuario dueño de las
-- tablas (postgres). Se puede repetir.

CREATE TABLE IF NOT EXISTS notificaciones (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Una cuenta concreta; NULL = aviso general.
    destinatario_id BIGINT REFERENCES usuarios(id) ON DELETE CASCADE,
    -- Solo para avisos generales: limita a un rol ('autoridad'); NULL = todos.
    rol_destino TEXT CHECK (rol_destino IS NULL OR rol_destino IN ('ciudadano', 'voluntario', 'autoridad')),
    tipo TEXT NOT NULL CHECK (tipo IN (
        'emergencia', 'jornada', 'desaparecido', 'solicitud', 'comentario', 'centro', 'cuenta'
    )),
    titulo TEXT NOT NULL CHECK (char_length(titulo) BETWEEN 1 AND 160),
    mensaje TEXT NOT NULL CHECK (char_length(mensaje) BETWEEN 1 AND 600),
    enlace TEXT CHECK (enlace IS NULL OR char_length(enlace) <= 200),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notificaciones_destinatario
    ON notificaciones (destinatario_id, creada_en DESC);
CREATE INDEX IF NOT EXISTS idx_notificaciones_generales
    ON notificaciones (creada_en DESC) WHERE destinatario_id IS NULL;

-- Un aviso general lo ven muchas cuentas, por eso lo leído se guarda aparte.
CREATE TABLE IF NOT EXISTS notificaciones_leidas (
    notificacion_id BIGINT NOT NULL REFERENCES notificaciones(id) ON DELETE CASCADE,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    leida_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (usuario_id, notificacion_id)
);

-- Sin políticas ni permisos: sigre_app no puede leerlas ni escribirlas
-- directamente; solo el dueño (a través de las funciones de abajo).
ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificaciones_leidas ENABLE ROW LEVEL SECURITY;

-- ---------- Crear notificaciones ----------

CREATE OR REPLACE FUNCTION sigre_notificar(
    p_destinatario_id BIGINT, p_rol_destino TEXT, p_tipo TEXT,
    p_titulo TEXT, p_mensaje TEXT, p_enlace TEXT
)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    INSERT INTO notificaciones (destinatario_id, rol_destino, tipo, titulo, mensaje, enlace)
    VALUES (p_destinatario_id, p_rol_destino, p_tipo,
            left(p_titulo, 160), left(coalesce(nullif(p_mensaje, ''), p_titulo), 600), p_enlace);
$$;

-- Emergencias
CREATE OR REPLACE FUNCTION sigre_notificar_emergencia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_lugar TEXT := concat_ws(', ', NEW.sector, NEW.municipio, NEW.departamento);
    v_nivel TEXT := CASE NEW.nivel_riesgo WHEN 'critico' THEN 'crítico' ELSE NEW.nivel_riesgo END;
BEGIN
    IF TG_OP = 'INSERT' AND NEW.estado = 'activa' THEN
        PERFORM sigre_notificar(NULL, NULL, 'emergencia',
            'Nueva emergencia activa: ' || NEW.tipo,
            'Riesgo ' || v_nivel || ' en ' || v_lugar || '. ' || NEW.descripcion,
            'dashboard.html');
    ELSIF TG_OP = 'UPDATE' AND OLD.estado = 'activa' AND NEW.estado = 'finalizada' THEN
        PERFORM sigre_notificar(NULL, NULL, 'emergencia',
            'Emergencia finalizada: ' || NEW.tipo,
            'Las autoridades dieron por terminada la emergencia en ' || v_lugar || '.',
            'dashboard.html');
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_emergencia ON emergencias;
CREATE TRIGGER trg_notificar_emergencia
    AFTER INSERT OR UPDATE OF estado ON emergencias
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_emergencia();

-- Jornadas
CREATE OR REPLACE FUNCTION sigre_notificar_jornada()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_fecha TEXT := to_char(NEW.fecha_inicio AT TIME ZONE 'America/Bogota', 'DD/MM/YYYY HH12:MI AM');
BEGIN
    IF TG_OP = 'INSERT' AND NEW.estado = 'publicada' THEN
        PERFORM sigre_notificar(NULL, NULL, 'jornada',
            'Nueva jornada: ' || NEW.nombre,
            v_fecha || ' · ' || NEW.lugar || '. ' || NEW.descripcion,
            'jornadas.html');
    ELSIF TG_OP = 'UPDATE' AND OLD.estado IS DISTINCT FROM NEW.estado THEN
        PERFORM sigre_notificar(NULL, NULL, 'jornada',
            CASE NEW.estado WHEN 'cancelada' THEN 'Jornada cancelada: ' ELSE 'Jornada publicada de nuevo: ' END || NEW.nombre,
            v_fecha || ' · ' || NEW.lugar || '.',
            'jornadas.html');
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_jornada ON jornadas;
CREATE TRIGGER trg_notificar_jornada
    AFTER INSERT OR UPDATE OF estado ON jornadas
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_jornada();

-- Desaparecidos
CREATE OR REPLACE FUNCTION sigre_notificar_desaparecido()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_que TEXT := CASE NEW.tipo WHEN 'animal' THEN 'mascota' ELSE 'persona' END;
    v_enlace TEXT := 'desaparecidos.html?reporte=' || NEW.id;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM sigre_notificar(NULL, NULL, 'desaparecido',
            'Nuevo reporte de ' || v_que || ' desaparecida: ' || NEW.nombre,
            'Visto por última vez en ' || coalesce(NEW.sector, 'sector sin indicar') ||
                '. Si tienes información, déjala en el reporte.',
            v_enlace);
    ELSIF TG_OP = 'UPDATE' AND OLD.estado = 'activo' AND NEW.estado = 'encontrado' THEN
        PERFORM sigre_notificar(NULL, NULL, 'desaparecido',
            'Encontrado: ' || NEW.nombre,
            'El reporte de ' || v_que || ' desaparecida se marcó como encontrado. Gracias por ayudar.',
            v_enlace);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_desaparecido ON reportes_desaparecidos;
CREATE TRIGGER trg_notificar_desaparecido
    AFTER INSERT OR UPDATE OF estado ON reportes_desaparecidos
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_desaparecido();

-- Comentarios en reportes de desaparecidos (aviso privado a quien publicó)
CREATE OR REPLACE FUNCTION sigre_notificar_comentario()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v RECORD;
BEGIN
    SELECT c.nombre_testigo, c.comentario, r.id AS reporte_id, r.nombre, cc.telefono_testigo
    INTO v
    FROM comentarios_desaparecidos c
    JOIN reportes_desaparecidos r ON r.id = c.reporte_id
    LEFT JOIN contactos_comentarios_desaparecidos cc ON cc.comentario_id = c.id
    WHERE c.id = NEW.comentario_id;
    IF FOUND THEN
        PERFORM sigre_notificar(NEW.destinatario_id, NULL, 'comentario',
            v.nombre_testigo || ' comentó tu reporte de ' || v.nombre,
            '"' || v.comentario || '"' || coalesce(' · Tel. ' || v.telefono_testigo, ''),
            'desaparecidos.html?reporte=' || v.reporte_id);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_comentario ON notificaciones_comentarios_desaparecidos;
CREATE TRIGGER trg_notificar_comentario
    AFTER INSERT ON notificaciones_comentarios_desaparecidos
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_comentario();

-- Solicitudes de ayuda
CREATE OR REPLACE FUNCTION sigre_notificar_solicitud()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_que TEXT := CASE NEW.tipo WHEN 'visita' THEN 'visita a vivienda' ELSE 'solicitud de ayuda' END;
    v_radicado TEXT := 'SIGRE-' || lpad(NEW.id::TEXT, 5, '0');
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM sigre_notificar(NULL, 'autoridad', 'solicitud',
            'Nueva ' || v_que || ' (urgencia ' || CASE NEW.urgencia WHEN 'critica' THEN 'crítica' ELSE NEW.urgencia END || ')',
            v_radicado || ' · ' || NEW.direccion || ' · ' || NEW.personas_afectadas || ' persona(s) afectada(s).',
            'dashboard_admin.html#solicitudes');
    ELSIF TG_OP = 'UPDATE' AND OLD.estado IS DISTINCT FROM NEW.estado THEN
        PERFORM sigre_notificar(NEW.usuario_id, NULL, 'solicitud',
            CASE NEW.estado
                WHEN 'en_revision' THEN 'Tu ' || v_que || ' está en revisión'
                WHEN 'programada' THEN 'Tu visita fue programada'
                WHEN 'en_atencion' THEN 'Tu ' || v_que || ' fue aceptada y está en atención'
                WHEN 'atendida' THEN 'Tu ' || v_que || ' fue atendida'
                WHEN 'cancelada' THEN 'Tu ' || v_que || ' fue cancelada'
                ELSE 'Tu ' || v_que || ' volvió a estado pendiente'
            END,
            'Radicado ' || v_radicado || '. Consulta el detalle en "Mis solicitudes".',
            'solicitar_ayuda.html#seccion-mis-solicitudes');
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_solicitud ON solicitudes_ayuda;
CREATE TRIGGER trg_notificar_solicitud
    AFTER INSERT OR UPDATE OF estado ON solicitudes_ayuda
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_solicitud();

-- Centros de acopio y albergues
CREATE OR REPLACE FUNCTION sigre_notificar_centro()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_que TEXT := CASE NEW.tipo WHEN 'albergue' THEN 'albergue' ELSE 'centro de acopio' END;
BEGIN
    IF NEW.estado = 'abierto' AND (TG_OP = 'INSERT' OR OLD.estado = 'cerrado') THEN
        PERFORM sigre_notificar(NULL, NULL, 'centro',
            CASE WHEN TG_OP = 'INSERT' THEN 'Nuevo ' ELSE 'Reabierto: ' END || v_que || ': ' || NEW.nombre,
            NEW.direccion || coalesce('. Necesidades: ' || NEW.necesidades, '.'),
            'centros.html');
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_centro ON centros_ayuda;
CREATE TRIGGER trg_notificar_centro
    AFTER INSERT OR UPDATE OF estado ON centros_ayuda
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_centro();

-- Cambio de rol de una cuenta
CREATE OR REPLACE FUNCTION sigre_notificar_rol()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.rol IS DISTINCT FROM NEW.rol THEN
        PERFORM sigre_notificar(NEW.id, NULL, 'cuenta',
            'Tu cuenta ahora es ' || CASE NEW.rol WHEN 'autoridad' THEN 'administrador o entidad' ELSE NEW.rol END,
            'Cierra sesión y vuelve a entrar para usar los nuevos permisos.',
            NULL);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_rol ON usuarios;
CREATE TRIGGER trg_notificar_rol
    AFTER UPDATE OF rol ON usuarios
    FOR EACH ROW EXECUTE FUNCTION sigre_notificar_rol();

-- ---------- Consultar y marcar como leídas (las usa la API) ----------

-- Notificaciones visibles para la cuenta de la sesión: las propias y los avisos
-- generales de los últimos 30 días publicados después de crear la cuenta.
CREATE OR REPLACE FUNCTION sigre_mis_notificaciones(p_limite INTEGER)
RETURNS TABLE (
    id BIGINT, tipo TEXT, titulo TEXT, mensaje TEXT, enlace TEXT,
    creada_en TIMESTAMPTZ, leida BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH yo AS (
        SELECT u.id, u.rol, u.creado_en FROM usuarios u
        WHERE u.id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
    )
    SELECT n.id, n.tipo, n.titulo, n.mensaje, n.enlace, n.creada_en,
           (l.notificacion_id IS NOT NULL) AS leida
    FROM notificaciones n
    CROSS JOIN yo
    LEFT JOIN notificaciones_leidas l ON l.notificacion_id = n.id AND l.usuario_id = yo.id
    WHERE n.destinatario_id = yo.id
       OR (n.destinatario_id IS NULL
           AND (n.rol_destino IS NULL OR n.rol_destino = yo.rol)
           AND n.creada_en >= yo.creado_en
           AND n.creada_en >= NOW() - INTERVAL '30 days')
    ORDER BY n.creada_en DESC, n.id DESC
    LIMIT LEAST(GREATEST(p_limite, 1), 100);
$$;

-- p_id NULL marca todas las visibles.
CREATE OR REPLACE FUNCTION sigre_marcar_notificaciones_leidas(p_id BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
    v_total INTEGER;
BEGIN
    IF v_usuario IS NULL THEN
        RAISE EXCEPTION 'Sesión no válida' USING ERRCODE = '42501';
    END IF;
    INSERT INTO notificaciones_leidas (notificacion_id, usuario_id)
    SELECT m.id, v_usuario
    FROM sigre_mis_notificaciones(100) m
    WHERE NOT m.leida AND (p_id IS NULL OR m.id = p_id)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_total = ROW_COUNT;
    RETURN v_total;
END;
$$;

-- ---------- Permisos ----------

REVOKE ALL ON FUNCTION sigre_notificar(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_mis_notificaciones(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_marcar_notificaciones_leidas(BIGINT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION sigre_mis_notificaciones(INTEGER) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_marcar_notificaciones_leidas(BIGINT) TO sigre_app;
    END IF;
END
$$;
