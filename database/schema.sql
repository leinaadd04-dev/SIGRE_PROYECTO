-- =====================================================================
-- SIGRE · Esquema completo de la base de datos (PostgreSQL 18)
-- =====================================================================
-- Generado de la base real con:
--   pg_dump -U postgres -d sigre --schema-only --no-owner -f database/schema.sql
-- Contiene solo la estructura, sin datos: 19 tablas con sus llaves primarias,
-- llaves foráneas y restricciones (CHECK, UNIQUE, NOT NULL), índices, funciones
-- (SECURITY DEFINER), disparadores de notificaciones, seguridad por filas
-- (Row Level Security) y permisos del usuario de la aplicación.
--
-- Es el resultado de aplicar, en orden, las migraciones backend/migracion_*.sql.
-- Si cambias una migración, vuelve a generar este archivo con el comando de arriba.
--
-- Para crear una base nueva desde cero:
--   1. Crear la base y el usuario de la aplicación (con el usuario postgres):
--        CREATE DATABASE sigre;
--        CREATE ROLE sigre_app LOGIN PASSWORD 'una-clave-segura';
--   2. Cargar este archivo:
--        psql -U postgres -d sigre -f database/schema.sql
--   3. En backend/.env: DB_USER=sigre_app y DB_PASSWORD=la-clave-de-arriba.
--
-- Tablas principales:
--   usuarios                      cuentas, rol, perfil médico, correo verificado
--   emergencias                   emergencias publicadas por las autoridades
--   solicitudes_ayuda             pedidos de ayuda y de visita a la vivienda
--   reportes_desaparecidos        personas y animales desaparecidos
--   comentarios_desaparecidos     comentarios de testigos (+ contactos y avisos)
--   centros_ayuda                 centros de acopio y albergues
--   inventario_centros            productos de cada centro por categoría
--   jornadas                      jornadas comunitarias (+ participaciones)
--   directorio_entidades          directorio de entidades y líneas de atención
--   rutas_guardadas               rutas de evacuación guardadas por cada cuenta
--   notificaciones                campana (+ leídas y suscripciones push)
--   avatares_usuario              foto o animalito de cada cuenta
--   recuperacion_contrasenas      enlaces para restablecer la contraseña
--   codigos_verificacion          códigos de 6 números para verificar el correo
-- =====================================================================

--
-- PostgreSQL database dump
--

\restrict 1GTnYN6Eu5V8t6JLm4Pejv7I9J865SqJbInc84ZlTmTbzlpZdYnIfQSk7Fk3OZW

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: admin_adjunto_solicitud(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_adjunto_solicitud(p_solicitud_id bigint) RETURNS TABLE(adjunto bytea, adjunto_mime text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    RETURN QUERY
        SELECT s.adjunto, s.adjunto_mime FROM solicitudes_ayuda s
        WHERE s.id = p_solicitud_id AND s.adjunto IS NOT NULL;
END;
$$;


--
-- Name: admin_cambiar_estado_desaparecido(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_cambiar_estado_desaparecido(p_reporte_id bigint, p_estado text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_cambiar_estado_solicitud(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_cambiar_estado_solicitud(p_solicitud_id bigint, p_estado text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_cambiar_rol(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_cambiar_rol(p_usuario_id bigint, p_rol text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_crear_emergencia(text, text, text, text, text, text, text, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_crear_emergencia(p_tipo text, p_descripcion text, p_alcance text, p_departamento text, p_municipio text, p_sector text, p_nivel_riesgo text, p_latitud double precision, p_longitud double precision) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_eliminar_desaparecido(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_eliminar_desaparecido(p_reporte_id bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    PERFORM sigre_exigir_autoridad();
    DELETE FROM reportes_desaparecidos WHERE id = p_reporte_id;
    RETURN FOUND;
END;
$$;


--
-- Name: admin_finalizar_emergencia(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_finalizar_emergencia(p_emergencia_id bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_listar_emergencias(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_listar_emergencias() RETURNS TABLE(id bigint, tipo text, descripcion text, alcance text, departamento text, municipio text, sector text, nivel_riesgo text, estado text, creada_en timestamp with time zone, finalizada_en timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_listar_solicitudes(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_listar_solicitudes(p_estado text) RETURNS TABLE(id bigint, tipo text, alcance text, nombre_comunidad text, categoria text, motivo_visita text, fecha_visita_preferida date, franja_horaria text, urgencia text, descripcion text, personas_afectadas integer, direccion text, latitud double precision, longitud double precision, nombre_contacto text, telefono_contacto text, adjunto_mime text, estado text, creada_en timestamp with time zone, actualizada_en timestamp with time zone, cuenta_email text, cuenta_nombre text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_listar_usuarios(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_listar_usuarios(p_busqueda text) RETURNS TABLE(id bigint, email text, nombre text, telefono text, rol text, creado_en timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: admin_resumen(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_resumen() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: contar_usuarios_registrados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.contar_usuarios_registrados() RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT count(*) FROM public.usuarios;
$$;


--
-- Name: emergencia_activa_publica(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.emergencia_activa_publica() RETURNS TABLE(id bigint, tipo text, descripcion text, alcance text, departamento text, municipio text, sector text, nivel_riesgo text, creada_en timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT e.id, e.tipo, e.descripcion, e.alcance, e.departamento, e.municipio,
           e.sector, e.nivel_riesgo, e.creada_en
    FROM emergencias e
    WHERE e.estado = 'activa'
    ORDER BY CASE e.nivel_riesgo WHEN 'critico' THEN 0 WHEN 'alto' THEN 1 WHEN 'medio' THEN 2 ELSE 3 END,
             e.creada_en DESC
    LIMIT 1;
$$;


--
-- Name: jornada_participantes(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jornada_participantes(p_jornada_id bigint) RETURNS TABLE(nombre text, animal text, email text, telefono text, inscrito_en timestamp with time zone, es_yo boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: jornada_participar(bigint, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jornada_participar(p_jornada_id bigint, p_participar boolean) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: jornadas_estadisticas_categoria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jornadas_estadisticas_categoria() RETURNS TABLE(categoria text, jornadas bigint, participantes bigint, promedio numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: jornadas_participacion(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jornadas_participacion(p_ids bigint[]) RETURNS TABLE(jornada_id bigint, total bigint, vista_previa jsonb, participo boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_borrar_suscripcion_push(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_borrar_suscripcion_push(p_endpoint text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    DELETE FROM suscripciones_push
    WHERE endpoint = p_endpoint
      AND usuario_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT;
$$;


--
-- Name: sigre_crear_codigo_verificacion(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_crear_codigo_verificacion(p_email text, p_codigo_hash text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_crear_recuperacion(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_crear_recuperacion(p_email text, p_token_hash text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_cuenta_sin_verificar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_cuenta_sin_verificar(p_email text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM usuarios
        WHERE email = lower(btrim(p_email)) AND NOT email_verificado
    );
$$;


--
-- Name: sigre_descartar_suscripcion_push(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_descartar_suscripcion_push(p_endpoint text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    DELETE FROM suscripciones_push WHERE endpoint = p_endpoint;
$$;


--
-- Name: sigre_exigir_autoridad(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_exigir_autoridad() RETURNS bigint
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NOT sigre_usuario_es_autoridad() THEN
        RAISE EXCEPTION 'Se requiere una cuenta de autoridad' USING ERRCODE = '42501';
    END IF;
    RETURN NULLIF(current_setting('app.user_id', true), '')::BIGINT;
END;
$$;


--
-- Name: sigre_guardar_mi_perfil(text, text, date, text, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_guardar_mi_perfil(p_tipo_documento text, p_numero_documento text, p_fecha_nacimiento date, p_tipo_sangre text, p_alergias text, p_condiciones_medicas text, p_medicamentos text, p_contacto_emergencia_nombre text, p_contacto_emergencia_telefono text, p_direccion text, p_comunidad text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_guardar_suscripcion_push(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_guardar_suscripcion_push(p_endpoint text, p_p256dh text, p_auth text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_marcar_notificaciones_leidas(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_marcar_notificaciones_leidas(p_id bigint) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_mi_perfil(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_mi_perfil() RETURNS TABLE(tipo_documento text, numero_documento text, fecha_nacimiento date, tipo_sangre text, alergias text, condiciones_medicas text, medicamentos text, contacto_emergencia_nombre text, contacto_emergencia_telefono text, direccion text, comunidad text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT u.tipo_documento, u.numero_documento, u.fecha_nacimiento,
           u.tipo_sangre, u.alergias, u.condiciones_medicas, u.medicamentos,
           u.contacto_emergencia_nombre, u.contacto_emergencia_telefono,
           u.direccion, u.comunidad
    FROM usuarios u
    WHERE u.id = NULLIF(current_setting('app.user_id', true), '')::BIGINT;
$$;


--
-- Name: sigre_mis_notificaciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_mis_notificaciones(p_limite integer) RETURNS TABLE(id bigint, tipo text, titulo text, mensaje text, enlace text, creada_en timestamp with time zone, leida boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_nombre_corto(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_nombre_corto(p_nombre text, p_email text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN coalesce(btrim(p_nombre), '') = '' THEN split_part(coalesce(p_email, 'Participante'), '@', 1)
        WHEN (regexp_split_to_array(btrim(p_nombre), '\s+'))[2] IS NULL THEN btrim(p_nombre)
        ELSE (regexp_split_to_array(btrim(p_nombre), '\s+'))[1] || ' ' ||
             upper(left((regexp_split_to_array(btrim(p_nombre), '\s+'))[2], 1)) || '.'
    END;
$$;


--
-- Name: sigre_notificar(bigint, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar(p_destinatario_id bigint, p_rol_destino text, p_tipo text, p_titulo text, p_mensaje text, p_enlace text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    INSERT INTO notificaciones (destinatario_id, rol_destino, tipo, titulo, mensaje, enlace)
    VALUES (p_destinatario_id, p_rol_destino, p_tipo,
            left(p_titulo, 160), left(coalesce(nullif(p_mensaje, ''), p_titulo), 600), p_enlace);
$$;


--
-- Name: sigre_notificar_centro(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_centro() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_notificar_comentario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_comentario() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_notificar_desaparecido(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_desaparecido() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_notificar_emergencia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_emergencia() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_notificar_jornada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_jornada() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_notificar_rol(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_rol() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_notificar_solicitud(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_notificar_solicitud() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_push_pendientes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_push_pendientes() RETURNS TABLE(endpoint text, p256dh text, auth text, tipo text, titulo text, mensaje text, enlace text, notificacion_id bigint)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_restablecer_contrasena(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_restablecer_contrasena(p_token_hash text, p_password_hash text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sigre_usuario_es_autoridad(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_usuario_es_autoridad() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.usuarios
        WHERE id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
          AND rol = 'autoridad'
    );
$$;


--
-- Name: sigre_verificar_correo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sigre_verificar_correo(p_email text, p_codigo_hash text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: avatares_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.avatares_usuario (
    usuario_id bigint NOT NULL,
    tipo text NOT NULL,
    animal text,
    foto bytea,
    foto_mime text,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT avatar_consistente CHECK ((((tipo = 'animal'::text) AND (animal IS NOT NULL) AND (foto IS NULL) AND (foto_mime IS NULL)) OR ((tipo = 'foto'::text) AND (animal IS NULL) AND (foto IS NOT NULL) AND (foto_mime IS NOT NULL) AND (octet_length(foto) <= ((2 * 1024) * 1024))))),
    CONSTRAINT avatares_usuario_animal_check CHECK ((animal = ANY (ARRAY['perro'::text, 'gato'::text, 'zorro'::text, 'panda'::text, 'koala'::text, 'leon'::text, 'rana'::text, 'mono'::text, 'conejo'::text, 'tigre'::text, 'oso'::text, 'buho'::text]))),
    CONSTRAINT avatares_usuario_foto_mime_check CHECK ((foto_mime = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]))),
    CONSTRAINT avatares_usuario_tipo_check CHECK ((tipo = ANY (ARRAY['animal'::text, 'foto'::text])))
);

ALTER TABLE ONLY public.avatares_usuario FORCE ROW LEVEL SECURITY;


--
-- Name: centros_ayuda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.centros_ayuda (
    id bigint NOT NULL,
    nombre text NOT NULL,
    tipo text NOT NULL,
    direccion text NOT NULL,
    descripcion text,
    necesidades text,
    telefono text,
    latitud double precision,
    longitud double precision,
    capacidad integer DEFAULT 0 NOT NULL,
    ocupados integer DEFAULT 0 NOT NULL,
    estado text DEFAULT 'abierto'::text NOT NULL,
    creado_por bigint,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT centro_coordenadas_validas CHECK ((((latitud IS NULL) AND (longitud IS NULL)) OR (((latitud >= ('-90'::integer)::double precision) AND (latitud <= (90)::double precision)) AND ((longitud >= ('-180'::integer)::double precision) AND (longitud <= (180)::double precision))))),
    CONSTRAINT centro_ocupacion_valida CHECK ((ocupados <= capacidad)),
    CONSTRAINT centros_ayuda_capacidad_check CHECK (((capacidad >= 0) AND (capacidad <= 100000))),
    CONSTRAINT centros_ayuda_descripcion_check CHECK (((descripcion IS NULL) OR (char_length(descripcion) <= 600))),
    CONSTRAINT centros_ayuda_direccion_check CHECK (((char_length(direccion) >= 3) AND (char_length(direccion) <= 200))),
    CONSTRAINT centros_ayuda_estado_check CHECK ((estado = ANY (ARRAY['abierto'::text, 'cerrado'::text]))),
    CONSTRAINT centros_ayuda_necesidades_check CHECK (((necesidades IS NULL) OR (char_length(necesidades) <= 400))),
    CONSTRAINT centros_ayuda_nombre_check CHECK (((char_length(nombre) >= 3) AND (char_length(nombre) <= 120))),
    CONSTRAINT centros_ayuda_ocupados_check CHECK ((ocupados >= 0)),
    CONSTRAINT centros_ayuda_telefono_check CHECK (((telefono IS NULL) OR ((char_length(telefono) >= 7) AND (char_length(telefono) <= 20)))),
    CONSTRAINT centros_ayuda_tipo_check CHECK ((tipo = ANY (ARRAY['acopio'::text, 'albergue'::text])))
);

ALTER TABLE ONLY public.centros_ayuda FORCE ROW LEVEL SECURITY;


--
-- Name: centros_ayuda_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.centros_ayuda ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.centros_ayuda_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: codigos_verificacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.codigos_verificacion (
    usuario_id bigint NOT NULL,
    codigo_hash text NOT NULL,
    expira_en timestamp with time zone NOT NULL,
    intentos integer DEFAULT 0 NOT NULL,
    enviado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT codigos_verificacion_codigo_hash_check CHECK ((char_length(codigo_hash) = 64))
);


--
-- Name: comentarios_desaparecidos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comentarios_desaparecidos (
    id bigint NOT NULL,
    reporte_id bigint NOT NULL,
    usuario_id bigint,
    nombre_testigo text NOT NULL,
    comentario text NOT NULL,
    veracidad_confirmada boolean NOT NULL,
    autoriza_compartir_telefono boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT comentarios_desaparecidos_autoriza_compartir_telefono_check CHECK ((autoriza_compartir_telefono = true)),
    CONSTRAINT comentarios_desaparecidos_comentario_check CHECK (((char_length(comentario) >= 5) AND (char_length(comentario) <= 800))),
    CONSTRAINT comentarios_desaparecidos_nombre_testigo_check CHECK (((char_length(nombre_testigo) >= 2) AND (char_length(nombre_testigo) <= 120))),
    CONSTRAINT comentarios_desaparecidos_veracidad_confirmada_check CHECK ((veracidad_confirmada = true))
);

ALTER TABLE ONLY public.comentarios_desaparecidos FORCE ROW LEVEL SECURITY;


--
-- Name: comentarios_desaparecidos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.comentarios_desaparecidos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.comentarios_desaparecidos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contactos_comentarios_desaparecidos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contactos_comentarios_desaparecidos (
    comentario_id bigint NOT NULL,
    telefono_testigo text NOT NULL,
    CONSTRAINT contactos_comentarios_desaparecidos_telefono_testigo_check CHECK (((char_length(telefono_testigo) >= 7) AND (char_length(telefono_testigo) <= 20)))
);

ALTER TABLE ONLY public.contactos_comentarios_desaparecidos FORCE ROW LEVEL SECURITY;


--
-- Name: directorio_entidades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directorio_entidades (
    id bigint NOT NULL,
    grupo text NOT NULL,
    nombre text NOT NULL,
    detalle text,
    telefono text,
    direccion text,
    web text,
    orden integer DEFAULT 100 NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    foto bytea,
    foto_mime text,
    foto_actualizada timestamp with time zone,
    CONSTRAINT directorio_entidades_detalle_check CHECK (((detalle IS NULL) OR (char_length(detalle) <= 300))),
    CONSTRAINT directorio_entidades_direccion_check CHECK (((direccion IS NULL) OR (char_length(direccion) <= 200))),
    CONSTRAINT directorio_entidades_grupo_check CHECK ((grupo = ANY (ARRAY['emergencias'::text, 'estado'::text, 'salud'::text, 'comunidad'::text]))),
    CONSTRAINT directorio_entidades_nombre_check CHECK (((char_length(nombre) >= 2) AND (char_length(nombre) <= 120))),
    CONSTRAINT directorio_entidades_telefono_check CHECK (((telefono IS NULL) OR ((char_length(telefono) >= 3) AND (char_length(telefono) <= 20)))),
    CONSTRAINT directorio_entidades_web_check CHECK (((web IS NULL) OR ((char_length(web) <= 300) AND (web ~ '^https://'::text)))),
    CONSTRAINT directorio_foto_valida CHECK ((((foto IS NULL) AND (foto_mime IS NULL)) OR ((foto IS NOT NULL) AND (foto_mime = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text])) AND (octet_length(foto) <= (1024 * 1024)))))
);

ALTER TABLE ONLY public.directorio_entidades FORCE ROW LEVEL SECURITY;


--
-- Name: directorio_entidades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.directorio_entidades ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.directorio_entidades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: emergencias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emergencias (
    id bigint NOT NULL,
    tipo text NOT NULL,
    descripcion text NOT NULL,
    alcance text NOT NULL,
    departamento text NOT NULL,
    municipio text,
    sector text,
    latitud double precision,
    longitud double precision,
    nivel_riesgo text NOT NULL,
    estado text DEFAULT 'activa'::text NOT NULL,
    registrada_por bigint CONSTRAINT emergencias_resgistrada_por_not_null NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizada_en timestamp with time zone DEFAULT now() NOT NULL,
    finalizada_por bigint,
    finalizada_en timestamp with time zone,
    CONSTRAINT coordenadas_validas CHECK ((((latitud IS NULL) AND (longitud IS NULL)) OR ((latitud IS NOT NULL) AND (longitud IS NOT NULL) AND ((latitud >= ('-90'::integer)::double precision) AND (latitud <= (90)::double precision)) AND ((longitud >= ('-180'::integer)::double precision) AND (longitud <= (180)::double precision))))),
    CONSTRAINT emergencias_alcance_check CHECK ((alcance = ANY (ARRAY['departamento'::text, 'municipio'::text, 'sector'::text]))),
    CONSTRAINT emergencias_estado_check CHECK ((estado = ANY (ARRAY['activa'::text, 'finalizada'::text]))),
    CONSTRAINT emergencias_nivel_riesgo_check CHECK ((nivel_riesgo = ANY (ARRAY['bajo'::text, 'medio'::text, 'alto'::text, 'critico'::text]))),
    CONSTRAINT finalizacion_consistente CHECK ((((estado = 'activa'::text) AND (finalizada_por IS NULL) AND (finalizada_en IS NULL)) OR ((estado = 'finalizada'::text) AND (finalizada_por IS NOT NULL) AND (finalizada_en IS NOT NULL))))
);

ALTER TABLE ONLY public.emergencias FORCE ROW LEVEL SECURITY;


--
-- Name: emergencias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.emergencias ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.emergencias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_centros; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_centros (
    id bigint NOT NULL,
    centro_id bigint NOT NULL,
    categoria text NOT NULL,
    producto text NOT NULL,
    cantidad integer DEFAULT 0 NOT NULL,
    unidad text DEFAULT 'unidades'::text NOT NULL,
    minimo integer DEFAULT 0 NOT NULL,
    actualizado_por bigint,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    talla text,
    CONSTRAINT inventario_centros_cantidad_check CHECK (((cantidad >= 0) AND (cantidad <= 1000000))),
    CONSTRAINT inventario_centros_categoria_check CHECK ((categoria = ANY (ARRAY['aseo'::text, 'no_perecederos'::text, 'perecederos'::text, 'agua'::text, 'mascotas'::text, 'descanso'::text, 'ropa'::text, 'botiquin'::text, 'bebes'::text, 'otros'::text]))),
    CONSTRAINT inventario_centros_minimo_check CHECK (((minimo >= 0) AND (minimo <= 1000000))),
    CONSTRAINT inventario_centros_producto_check CHECK (((char_length(producto) >= 2) AND (char_length(producto) <= 120))),
    CONSTRAINT inventario_centros_unidad_check CHECK ((unidad = ANY (ARRAY['unidades'::text, 'kg'::text, 'libras'::text, 'litros'::text, 'paquetes'::text, 'cajas'::text, 'bolsas'::text, 'pares'::text]))),
    CONSTRAINT inventario_talla_valida CHECK (((talla IS NULL) OR ((categoria = 'ropa'::text) AND ((char_length(talla) >= 1) AND (char_length(talla) <= 20)))))
);

ALTER TABLE ONLY public.inventario_centros FORCE ROW LEVEL SECURITY;


--
-- Name: inventario_centros_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_centros ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_centros_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: jornadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jornadas (
    id bigint NOT NULL,
    nombre text NOT NULL,
    categoria text NOT NULL,
    descripcion text NOT NULL,
    fecha_inicio timestamp with time zone NOT NULL,
    lugar text NOT NULL,
    latitud double precision,
    longitud double precision,
    estado text DEFAULT 'publicada'::text NOT NULL,
    creada_por bigint,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    fecha_fin timestamp with time zone,
    CONSTRAINT jornada_coordenadas_validas CHECK ((((latitud IS NULL) AND (longitud IS NULL)) OR (((latitud >= ('-90'::integer)::double precision) AND (latitud <= (90)::double precision)) AND ((longitud >= ('-180'::integer)::double precision) AND (longitud <= (180)::double precision))))),
    CONSTRAINT jornada_fin_valido CHECK (((fecha_fin IS NULL) OR (fecha_fin > fecha_inicio))),
    CONSTRAINT jornadas_categoria_check CHECK ((categoria = ANY (ARRAY['limpieza'::text, 'salud'::text, 'solidaridad'::text, 'apoyo'::text]))),
    CONSTRAINT jornadas_descripcion_check CHECK (((char_length(descripcion) >= 10) AND (char_length(descripcion) <= 600))),
    CONSTRAINT jornadas_estado_check CHECK ((estado = ANY (ARRAY['publicada'::text, 'cancelada'::text]))),
    CONSTRAINT jornadas_lugar_check CHECK (((char_length(lugar) >= 3) AND (char_length(lugar) <= 200))),
    CONSTRAINT jornadas_nombre_check CHECK (((char_length(nombre) >= 3) AND (char_length(nombre) <= 120)))
);

ALTER TABLE ONLY public.jornadas FORCE ROW LEVEL SECURITY;


--
-- Name: jornadas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.jornadas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.jornadas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notificaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notificaciones (
    id bigint NOT NULL,
    destinatario_id bigint,
    rol_destino text,
    tipo text NOT NULL,
    titulo text NOT NULL,
    mensaje text NOT NULL,
    enlace text,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    push_enviada boolean DEFAULT false NOT NULL,
    CONSTRAINT notificaciones_enlace_check CHECK (((enlace IS NULL) OR (char_length(enlace) <= 200))),
    CONSTRAINT notificaciones_mensaje_check CHECK (((char_length(mensaje) >= 1) AND (char_length(mensaje) <= 600))),
    CONSTRAINT notificaciones_rol_destino_check CHECK (((rol_destino IS NULL) OR (rol_destino = ANY (ARRAY['ciudadano'::text, 'voluntario'::text, 'autoridad'::text])))),
    CONSTRAINT notificaciones_tipo_check CHECK ((tipo = ANY (ARRAY['emergencia'::text, 'jornada'::text, 'desaparecido'::text, 'solicitud'::text, 'comentario'::text, 'centro'::text, 'cuenta'::text]))),
    CONSTRAINT notificaciones_titulo_check CHECK (((char_length(titulo) >= 1) AND (char_length(titulo) <= 160)))
);


--
-- Name: notificaciones_comentarios_desaparecidos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notificaciones_comentarios_desaparecidos (
    id bigint NOT NULL,
    destinatario_id bigint CONSTRAINT notificaciones_comentarios_desaparecid_destinatario_id_not_null NOT NULL,
    comentario_id bigint NOT NULL,
    leida boolean DEFAULT false NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.notificaciones_comentarios_desaparecidos FORCE ROW LEVEL SECURITY;


--
-- Name: notificaciones_comentarios_desaparecidos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones_comentarios_desaparecidos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.notificaciones_comentarios_desaparecidos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notificaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.notificaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notificaciones_leidas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notificaciones_leidas (
    notificacion_id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    leida_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: participaciones_jornadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.participaciones_jornadas (
    jornada_id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: recuperacion_contrasenas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recuperacion_contrasenas (
    id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    token_hash text NOT NULL,
    expira_en timestamp with time zone NOT NULL,
    usado boolean DEFAULT false NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT recuperacion_contrasenas_token_hash_check CHECK ((char_length(token_hash) = 64))
);


--
-- Name: recuperacion_contrasenas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recuperacion_contrasenas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.recuperacion_contrasenas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reportes_desaparecidos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reportes_desaparecidos (
    id bigint NOT NULL,
    tipo text NOT NULL,
    nombre text NOT NULL,
    edad text,
    genero text,
    sector text NOT NULL,
    fecha_visto timestamp with time zone,
    descripcion text NOT NULL,
    foto bytea NOT NULL,
    foto_mime text NOT NULL,
    estado text DEFAULT 'activo'::text NOT NULL,
    autoriza_publicacion boolean NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    telefono_contacto character varying(20),
    publicado_por bigint,
    CONSTRAINT reportes_desaparecidos_autoriza_publicacion_check CHECK ((autoriza_publicacion = true)),
    CONSTRAINT reportes_desaparecidos_estado_check CHECK ((estado = ANY (ARRAY['activo'::text, 'encontrado'::text]))),
    CONSTRAINT reportes_desaparecidos_foto_mime_check CHECK ((foto_mime = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]))),
    CONSTRAINT reportes_desaparecidos_tipo_check CHECK ((tipo = ANY (ARRAY['persona'::text, 'animal'::text])))
);


--
-- Name: reportes_desaparecidos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reportes_desaparecidos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.reportes_desaparecidos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: rutas_guardadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rutas_guardadas (
    id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    nombre text NOT NULL,
    origen_lat double precision NOT NULL,
    origen_lon double precision NOT NULL,
    origen_texto text NOT NULL,
    destino_lat double precision NOT NULL,
    destino_lon double precision NOT NULL,
    destino_texto text NOT NULL,
    incluye_demo boolean DEFAULT false NOT NULL,
    distancia_m integer NOT NULL,
    tiempo_min integer NOT NULL,
    metros_riesgo integer NOT NULL,
    geometria jsonb NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    modo text DEFAULT 'pie'::text NOT NULL,
    CONSTRAINT ruta_modo_valido CHECK ((modo = ANY (ARRAY['pie'::text, 'carro'::text, 'moto'::text]))),
    CONSTRAINT rutas_guardadas_destino_lat_check CHECK (((destino_lat >= ('-90'::integer)::double precision) AND (destino_lat <= (90)::double precision))),
    CONSTRAINT rutas_guardadas_destino_lon_check CHECK (((destino_lon >= ('-180'::integer)::double precision) AND (destino_lon <= (180)::double precision))),
    CONSTRAINT rutas_guardadas_destino_texto_check CHECK (((char_length(destino_texto) >= 1) AND (char_length(destino_texto) <= 200))),
    CONSTRAINT rutas_guardadas_distancia_m_check CHECK ((distancia_m >= 0)),
    CONSTRAINT rutas_guardadas_geometria_check CHECK ((jsonb_typeof(geometria) = 'array'::text)),
    CONSTRAINT rutas_guardadas_metros_riesgo_check CHECK ((metros_riesgo >= 0)),
    CONSTRAINT rutas_guardadas_nombre_check CHECK (((char_length(nombre) >= 2) AND (char_length(nombre) <= 80))),
    CONSTRAINT rutas_guardadas_origen_lat_check CHECK (((origen_lat >= ('-90'::integer)::double precision) AND (origen_lat <= (90)::double precision))),
    CONSTRAINT rutas_guardadas_origen_lon_check CHECK (((origen_lon >= ('-180'::integer)::double precision) AND (origen_lon <= (180)::double precision))),
    CONSTRAINT rutas_guardadas_origen_texto_check CHECK (((char_length(origen_texto) >= 1) AND (char_length(origen_texto) <= 200))),
    CONSTRAINT rutas_guardadas_tiempo_min_check CHECK ((tiempo_min >= 0))
);

ALTER TABLE ONLY public.rutas_guardadas FORCE ROW LEVEL SECURITY;


--
-- Name: rutas_guardadas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.rutas_guardadas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.rutas_guardadas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: solicitudes_ayuda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solicitudes_ayuda (
    id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    categoria text,
    urgencia text NOT NULL,
    descripcion text NOT NULL,
    personas_afectadas integer NOT NULL,
    direccion text NOT NULL,
    latitud double precision,
    longitud double precision,
    nombre_contacto text NOT NULL,
    telefono_contacto text NOT NULL,
    adjunto bytea,
    adjunto_mime text,
    autoriza_compartir boolean NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizada_en timestamp with time zone DEFAULT now() NOT NULL,
    tipo text DEFAULT 'ayuda'::text NOT NULL,
    alcance text DEFAULT 'hogar'::text NOT NULL,
    nombre_comunidad text,
    motivo_visita text,
    fecha_visita_preferida date,
    franja_horaria text,
    CONSTRAINT solicitud_adjunto_consistente CHECK ((((adjunto IS NULL) AND (adjunto_mime IS NULL)) OR ((adjunto IS NOT NULL) AND (adjunto_mime IS NOT NULL) AND (octet_length(adjunto) <= ((5 * 1024) * 1024))))),
    CONSTRAINT solicitud_alcance_valido CHECK ((alcance = ANY (ARRAY['comunidad'::text, 'familias'::text, 'hogar'::text]))),
    CONSTRAINT solicitud_comunidad_consistente CHECK ((((alcance = 'hogar'::text) AND (nombre_comunidad IS NULL)) OR ((alcance <> 'hogar'::text) AND ((char_length(nombre_comunidad) >= 3) AND (char_length(nombre_comunidad) <= 120))))),
    CONSTRAINT solicitud_coordenadas_validas CHECK ((((latitud IS NULL) AND (longitud IS NULL)) OR ((latitud IS NOT NULL) AND (longitud IS NOT NULL) AND ((latitud >= ('-90'::integer)::double precision) AND (latitud <= (90)::double precision)) AND ((longitud >= ('-180'::integer)::double precision) AND (longitud <= (180)::double precision))))),
    CONSTRAINT solicitud_estado_valido CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_revision'::text, 'programada'::text, 'en_atencion'::text, 'atendida'::text, 'cancelada'::text]))),
    CONSTRAINT solicitud_tipo_consistente CHECK ((((tipo = 'ayuda'::text) AND (categoria IS NOT NULL) AND (motivo_visita IS NULL) AND (fecha_visita_preferida IS NULL) AND (franja_horaria IS NULL)) OR ((tipo = 'visita'::text) AND (categoria IS NULL) AND (motivo_visita IS NOT NULL) AND (fecha_visita_preferida IS NOT NULL) AND (franja_horaria IS NOT NULL)))),
    CONSTRAINT solicitud_tipo_valido CHECK ((tipo = ANY (ARRAY['ayuda'::text, 'visita'::text]))),
    CONSTRAINT solicitud_visita_valida CHECK ((((motivo_visita IS NULL) OR (motivo_visita = ANY (ARRAY['evaluar_danos'::text, 'condiciones_vivienda'::text, 'riesgo_estructural'::text, 'encuesta_social'::text, 'otra'::text]))) AND ((franja_horaria IS NULL) OR (franja_horaria = ANY (ARRAY['manana'::text, 'tarde'::text, 'cualquiera'::text]))))),
    CONSTRAINT solicitudes_ayuda_adjunto_mime_check CHECK ((adjunto_mime = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'application/pdf'::text]))),
    CONSTRAINT solicitudes_ayuda_autoriza_compartir_check CHECK ((autoriza_compartir = true)),
    CONSTRAINT solicitudes_ayuda_categoria_check CHECK ((categoria = ANY (ARRAY['alimentos'::text, 'atencion_medica'::text, 'alojamiento'::text, 'transporte'::text, 'ropa'::text, 'otra'::text]))),
    CONSTRAINT solicitudes_ayuda_descripcion_check CHECK (((char_length(descripcion) >= 10) AND (char_length(descripcion) <= 1200))),
    CONSTRAINT solicitudes_ayuda_direccion_check CHECK (((char_length(direccion) >= 5) AND (char_length(direccion) <= 200))),
    CONSTRAINT solicitudes_ayuda_nombre_contacto_check CHECK (((char_length(nombre_contacto) >= 2) AND (char_length(nombre_contacto) <= 120))),
    CONSTRAINT solicitudes_ayuda_personas_afectadas_check CHECK (((personas_afectadas >= 1) AND (personas_afectadas <= 10000))),
    CONSTRAINT solicitudes_ayuda_telefono_contacto_check CHECK (((char_length(telefono_contacto) >= 7) AND (char_length(telefono_contacto) <= 20))),
    CONSTRAINT solicitudes_ayuda_urgencia_check CHECK ((urgencia = ANY (ARRAY['baja'::text, 'media'::text, 'alta'::text, 'critica'::text])))
);

ALTER TABLE ONLY public.solicitudes_ayuda FORCE ROW LEVEL SECURITY;


--
-- Name: solicitudes_ayuda_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.solicitudes_ayuda ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.solicitudes_ayuda_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: suscripciones_push; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suscripciones_push (
    id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT suscripciones_push_auth_check CHECK (((char_length(auth) >= 10) AND (char_length(auth) <= 100))),
    CONSTRAINT suscripciones_push_endpoint_check CHECK (((char_length(endpoint) >= 10) AND (char_length(endpoint) <= 1000))),
    CONSTRAINT suscripciones_push_p256dh_check CHECK (((char_length(p256dh) >= 10) AND (char_length(p256dh) <= 200)))
);


--
-- Name: suscripciones_push_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.suscripciones_push ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.suscripciones_push_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios (
    id bigint NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    rol text NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    nombre text,
    telefono text,
    tipo_documento text,
    numero_documento text,
    fecha_nacimiento date,
    tipo_sangre text,
    alergias text,
    condiciones_medicas text,
    medicamentos text,
    contacto_emergencia_nombre text,
    contacto_emergencia_telefono text,
    direccion text,
    comunidad text,
    email_verificado boolean DEFAULT false NOT NULL,
    CONSTRAINT usuario_nombre_valido CHECK (((nombre IS NULL) OR ((char_length(nombre) >= 2) AND (char_length(nombre) <= 120)))),
    CONSTRAINT usuario_perfil_valido CHECK ((((tipo_documento IS NULL) OR (tipo_documento = ANY (ARRAY['CC'::text, 'TI'::text, 'CE'::text, 'PASAPORTE'::text]))) AND ((numero_documento IS NULL) OR ((char_length(numero_documento) >= 3) AND (char_length(numero_documento) <= 40))) AND ((tipo_sangre IS NULL) OR (tipo_sangre = ANY (ARRAY['A+'::text, 'A-'::text, 'B+'::text, 'B-'::text, 'AB+'::text, 'AB-'::text, 'O+'::text, 'O-'::text]))) AND ((fecha_nacimiento IS NULL) OR (fecha_nacimiento >= '1900-01-01'::date)) AND ((alergias IS NULL) OR (char_length(alergias) <= 3000)) AND ((condiciones_medicas IS NULL) OR (char_length(condiciones_medicas) <= 3000)) AND ((medicamentos IS NULL) OR (char_length(medicamentos) <= 3000)) AND ((contacto_emergencia_nombre IS NULL) OR ((char_length(contacto_emergencia_nombre) >= 2) AND (char_length(contacto_emergencia_nombre) <= 120))) AND ((contacto_emergencia_telefono IS NULL) OR ((char_length(contacto_emergencia_telefono) >= 7) AND (char_length(contacto_emergencia_telefono) <= 30))) AND ((direccion IS NULL) OR (char_length(direccion) <= 300)) AND ((comunidad IS NULL) OR (char_length(comunidad) <= 150)))),
    CONSTRAINT usuario_telefono_valido CHECK (((telefono IS NULL) OR ((char_length(telefono) >= 7) AND (char_length(telefono) <= 20)))),
    CONSTRAINT usuarios_rol_check CHECK ((rol = ANY (ARRAY['ciudadano'::text, 'voluntario'::text, 'autoridad'::text])))
);

ALTER TABLE ONLY public.usuarios FORCE ROW LEVEL SECURITY;


--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.usuarios ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.usuarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: avatares_usuario avatares_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.avatares_usuario
    ADD CONSTRAINT avatares_usuario_pkey PRIMARY KEY (usuario_id);


--
-- Name: centros_ayuda centros_ayuda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.centros_ayuda
    ADD CONSTRAINT centros_ayuda_pkey PRIMARY KEY (id);


--
-- Name: codigos_verificacion codigos_verificacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.codigos_verificacion
    ADD CONSTRAINT codigos_verificacion_pkey PRIMARY KEY (usuario_id);


--
-- Name: comentarios_desaparecidos comentarios_desaparecidos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comentarios_desaparecidos
    ADD CONSTRAINT comentarios_desaparecidos_pkey PRIMARY KEY (id);


--
-- Name: contactos_comentarios_desaparecidos contactos_comentarios_desaparecidos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contactos_comentarios_desaparecidos
    ADD CONSTRAINT contactos_comentarios_desaparecidos_pkey PRIMARY KEY (comentario_id);


--
-- Name: directorio_entidades directorio_entidades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directorio_entidades
    ADD CONSTRAINT directorio_entidades_pkey PRIMARY KEY (id);


--
-- Name: emergencias emergencias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergencias
    ADD CONSTRAINT emergencias_pkey PRIMARY KEY (id);


--
-- Name: inventario_centros inventario_centros_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_centros
    ADD CONSTRAINT inventario_centros_pkey PRIMARY KEY (id);


--
-- Name: jornadas jornadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jornadas
    ADD CONSTRAINT jornadas_pkey PRIMARY KEY (id);


--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_desaparecidos_comentario_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_comentarios_desaparecidos
    ADD CONSTRAINT notificaciones_comentarios_desaparecidos_comentario_id_key UNIQUE (comentario_id);


--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_desaparecidos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_comentarios_desaparecidos
    ADD CONSTRAINT notificaciones_comentarios_desaparecidos_pkey PRIMARY KEY (id);


--
-- Name: notificaciones_leidas notificaciones_leidas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_leidas
    ADD CONSTRAINT notificaciones_leidas_pkey PRIMARY KEY (usuario_id, notificacion_id);


--
-- Name: notificaciones notificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT notificaciones_pkey PRIMARY KEY (id);


--
-- Name: participaciones_jornadas participaciones_jornadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participaciones_jornadas
    ADD CONSTRAINT participaciones_jornadas_pkey PRIMARY KEY (jornada_id, usuario_id);


--
-- Name: recuperacion_contrasenas recuperacion_contrasenas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasenas
    ADD CONSTRAINT recuperacion_contrasenas_pkey PRIMARY KEY (id);


--
-- Name: recuperacion_contrasenas recuperacion_contrasenas_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasenas
    ADD CONSTRAINT recuperacion_contrasenas_token_hash_key UNIQUE (token_hash);


--
-- Name: reportes_desaparecidos reportes_desaparecidos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reportes_desaparecidos
    ADD CONSTRAINT reportes_desaparecidos_pkey PRIMARY KEY (id);


--
-- Name: rutas_guardadas rutas_guardadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rutas_guardadas
    ADD CONSTRAINT rutas_guardadas_pkey PRIMARY KEY (id);


--
-- Name: solicitudes_ayuda solicitudes_ayuda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitudes_ayuda
    ADD CONSTRAINT solicitudes_ayuda_pkey PRIMARY KEY (id);


--
-- Name: suscripciones_push suscripciones_push_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suscripciones_push
    ADD CONSTRAINT suscripciones_push_endpoint_key UNIQUE (endpoint);


--
-- Name: suscripciones_push suscripciones_push_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suscripciones_push
    ADD CONSTRAINT suscripciones_push_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_email_key UNIQUE (email);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: idx_centros_ayuda_tipo_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_centros_ayuda_tipo_estado ON public.centros_ayuda USING btree (tipo, estado);


--
-- Name: idx_comentarios_desaparecidos_reporte_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comentarios_desaparecidos_reporte_fecha ON public.comentarios_desaparecidos USING btree (reporte_id, creado_en DESC);


--
-- Name: idx_inventario_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventario_categoria ON public.inventario_centros USING btree (categoria);


--
-- Name: idx_inventario_centro_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_inventario_centro_producto ON public.inventario_centros USING btree (centro_id, lower(producto), lower(COALESCE(talla, ''::text)));


--
-- Name: idx_jornadas_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jornadas_fecha ON public.jornadas USING btree (estado, fecha_inicio);


--
-- Name: idx_notificaciones_comentarios_destinatario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notificaciones_comentarios_destinatario ON public.notificaciones_comentarios_desaparecidos USING btree (destinatario_id, leida, creada_en DESC);


--
-- Name: idx_notificaciones_destinatario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notificaciones_destinatario ON public.notificaciones USING btree (destinatario_id, creada_en DESC);


--
-- Name: idx_notificaciones_generales; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notificaciones_generales ON public.notificaciones USING btree (creada_en DESC) WHERE (destinatario_id IS NULL);


--
-- Name: idx_notificaciones_push_pendientes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notificaciones_push_pendientes ON public.notificaciones USING btree (creada_en) WHERE (NOT push_enviada);


--
-- Name: idx_participaciones_jornadas_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_participaciones_jornadas_usuario ON public.participaciones_jornadas USING btree (usuario_id);


--
-- Name: idx_recuperacion_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recuperacion_usuario ON public.recuperacion_contrasenas USING btree (usuario_id, creado_en DESC);


--
-- Name: idx_reportes_desaparecidos_estado_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_desaparecidos_estado_fecha ON public.reportes_desaparecidos USING btree (estado, creado_en DESC);


--
-- Name: idx_reportes_desaparecidos_publicador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_desaparecidos_publicador ON public.reportes_desaparecidos USING btree (publicado_por);


--
-- Name: idx_reportes_desaparecidos_tipo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_desaparecidos_tipo ON public.reportes_desaparecidos USING btree (tipo);


--
-- Name: idx_rutas_guardadas_usuario_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rutas_guardadas_usuario_fecha ON public.rutas_guardadas USING btree (usuario_id, creada_en DESC);


--
-- Name: idx_solicitudes_ayuda_estado_urgencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_solicitudes_ayuda_estado_urgencia ON public.solicitudes_ayuda USING btree (estado, urgencia);


--
-- Name: idx_solicitudes_ayuda_tipo_alcance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_solicitudes_ayuda_tipo_alcance ON public.solicitudes_ayuda USING btree (tipo, alcance);


--
-- Name: idx_solicitudes_ayuda_usuario_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_solicitudes_ayuda_usuario_fecha ON public.solicitudes_ayuda USING btree (usuario_id, creada_en DESC);


--
-- Name: idx_suscripciones_push_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suscripciones_push_usuario ON public.suscripciones_push USING btree (usuario_id);


--
-- Name: idx_usuarios_numero_documento; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_usuarios_numero_documento ON public.usuarios USING btree (numero_documento) WHERE ((numero_documento IS NOT NULL) AND (numero_documento <> ''::text));


--
-- Name: centros_ayuda trg_notificar_centro; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_centro AFTER INSERT OR UPDATE OF estado ON public.centros_ayuda FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_centro();


--
-- Name: notificaciones_comentarios_desaparecidos trg_notificar_comentario; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_comentario AFTER INSERT ON public.notificaciones_comentarios_desaparecidos FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_comentario();


--
-- Name: reportes_desaparecidos trg_notificar_desaparecido; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_desaparecido AFTER INSERT OR UPDATE OF estado ON public.reportes_desaparecidos FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_desaparecido();


--
-- Name: emergencias trg_notificar_emergencia; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_emergencia AFTER INSERT OR UPDATE OF estado ON public.emergencias FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_emergencia();


--
-- Name: jornadas trg_notificar_jornada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_jornada AFTER INSERT OR UPDATE OF estado ON public.jornadas FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_jornada();


--
-- Name: usuarios trg_notificar_rol; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_rol AFTER UPDATE OF rol ON public.usuarios FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_rol();


--
-- Name: solicitudes_ayuda trg_notificar_solicitud; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notificar_solicitud AFTER INSERT OR UPDATE OF estado ON public.solicitudes_ayuda FOR EACH ROW EXECUTE FUNCTION public.sigre_notificar_solicitud();


--
-- Name: avatares_usuario avatares_usuario_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.avatares_usuario
    ADD CONSTRAINT avatares_usuario_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: centros_ayuda centros_ayuda_creado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.centros_ayuda
    ADD CONSTRAINT centros_ayuda_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: codigos_verificacion codigos_verificacion_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.codigos_verificacion
    ADD CONSTRAINT codigos_verificacion_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: comentarios_desaparecidos comentarios_desaparecidos_reporte_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comentarios_desaparecidos
    ADD CONSTRAINT comentarios_desaparecidos_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES public.reportes_desaparecidos(id) ON DELETE CASCADE;


--
-- Name: comentarios_desaparecidos comentarios_desaparecidos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comentarios_desaparecidos
    ADD CONSTRAINT comentarios_desaparecidos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: contactos_comentarios_desaparecidos contactos_comentarios_desaparecidos_comentario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contactos_comentarios_desaparecidos
    ADD CONSTRAINT contactos_comentarios_desaparecidos_comentario_id_fkey FOREIGN KEY (comentario_id) REFERENCES public.comentarios_desaparecidos(id) ON DELETE CASCADE;


--
-- Name: emergencias emergencias_finalizada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergencias
    ADD CONSTRAINT emergencias_finalizada_por_fkey FOREIGN KEY (finalizada_por) REFERENCES public.usuarios(id);


--
-- Name: emergencias emergencias_resgistrada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergencias
    ADD CONSTRAINT emergencias_resgistrada_por_fkey FOREIGN KEY (registrada_por) REFERENCES public.usuarios(id);


--
-- Name: inventario_centros inventario_centros_actualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_centros
    ADD CONSTRAINT inventario_centros_actualizado_por_fkey FOREIGN KEY (actualizado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: inventario_centros inventario_centros_centro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_centros
    ADD CONSTRAINT inventario_centros_centro_id_fkey FOREIGN KEY (centro_id) REFERENCES public.centros_ayuda(id) ON DELETE CASCADE;


--
-- Name: jornadas jornadas_creada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jornadas
    ADD CONSTRAINT jornadas_creada_por_fkey FOREIGN KEY (creada_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_desaparecidos_comentario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_comentarios_desaparecidos
    ADD CONSTRAINT notificaciones_comentarios_desaparecidos_comentario_id_fkey FOREIGN KEY (comentario_id) REFERENCES public.comentarios_desaparecidos(id) ON DELETE CASCADE;


--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_desaparecidos_destinatario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_comentarios_desaparecidos
    ADD CONSTRAINT notificaciones_comentarios_desaparecidos_destinatario_id_fkey FOREIGN KEY (destinatario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: notificaciones notificaciones_destinatario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT notificaciones_destinatario_id_fkey FOREIGN KEY (destinatario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: notificaciones_leidas notificaciones_leidas_notificacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_leidas
    ADD CONSTRAINT notificaciones_leidas_notificacion_id_fkey FOREIGN KEY (notificacion_id) REFERENCES public.notificaciones(id) ON DELETE CASCADE;


--
-- Name: notificaciones_leidas notificaciones_leidas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones_leidas
    ADD CONSTRAINT notificaciones_leidas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: participaciones_jornadas participaciones_jornadas_jornada_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participaciones_jornadas
    ADD CONSTRAINT participaciones_jornadas_jornada_id_fkey FOREIGN KEY (jornada_id) REFERENCES public.jornadas(id) ON DELETE CASCADE;


--
-- Name: participaciones_jornadas participaciones_jornadas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participaciones_jornadas
    ADD CONSTRAINT participaciones_jornadas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: recuperacion_contrasenas recuperacion_contrasenas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasenas
    ADD CONSTRAINT recuperacion_contrasenas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: reportes_desaparecidos reportes_desaparecidos_publicado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reportes_desaparecidos
    ADD CONSTRAINT reportes_desaparecidos_publicado_por_fkey FOREIGN KEY (publicado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: rutas_guardadas rutas_guardadas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rutas_guardadas
    ADD CONSTRAINT rutas_guardadas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: solicitudes_ayuda solicitudes_ayuda_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitudes_ayuda
    ADD CONSTRAINT solicitudes_ayuda_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: suscripciones_push suscripciones_push_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suscripciones_push
    ADD CONSTRAINT suscripciones_push_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: avatares_usuario; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.avatares_usuario ENABLE ROW LEVEL SECURITY;

--
-- Name: avatares_usuario avatares_usuario_propio; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY avatares_usuario_propio ON public.avatares_usuario USING ((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)) WITH CHECK ((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint));


--
-- Name: centros_ayuda; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.centros_ayuda ENABLE ROW LEVEL SECURITY;

--
-- Name: centros_ayuda centros_ayuda_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY centros_ayuda_crear ON public.centros_ayuda FOR INSERT WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: centros_ayuda centros_ayuda_editar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY centros_ayuda_editar ON public.centros_ayuda FOR UPDATE USING (public.sigre_usuario_es_autoridad()) WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: centros_ayuda centros_ayuda_eliminar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY centros_ayuda_eliminar ON public.centros_ayuda FOR DELETE USING (public.sigre_usuario_es_autoridad());


--
-- Name: centros_ayuda centros_ayuda_ver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY centros_ayuda_ver ON public.centros_ayuda FOR SELECT USING (true);


--
-- Name: codigos_verificacion; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.codigos_verificacion ENABLE ROW LEVEL SECURITY;

--
-- Name: comentarios_desaparecidos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.comentarios_desaparecidos ENABLE ROW LEVEL SECURITY;

--
-- Name: comentarios_desaparecidos comentarios_desaparecidos_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY comentarios_desaparecidos_crear ON public.comentarios_desaparecidos FOR INSERT WITH CHECK ((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint));


--
-- Name: comentarios_desaparecidos comentarios_desaparecidos_publicos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY comentarios_desaparecidos_publicos ON public.comentarios_desaparecidos FOR SELECT USING (true);


--
-- Name: contactos_comentarios_desaparecidos contactos_comentarios_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contactos_comentarios_crear ON public.contactos_comentarios_desaparecidos FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.comentarios_desaparecidos c
  WHERE ((c.id = contactos_comentarios_desaparecidos.comentario_id) AND (c.usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)))));


--
-- Name: contactos_comentarios_desaparecidos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contactos_comentarios_desaparecidos ENABLE ROW LEVEL SECURITY;

--
-- Name: contactos_comentarios_desaparecidos contactos_comentarios_privados; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contactos_comentarios_privados ON public.contactos_comentarios_desaparecidos FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.comentarios_desaparecidos c
  WHERE ((c.id = contactos_comentarios_desaparecidos.comentario_id) AND ((c.usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint) OR (EXISTS ( SELECT 1
           FROM public.reportes_desaparecidos r
          WHERE ((r.id = c.reporte_id) AND (r.publicado_por = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)))))))));


--
-- Name: directorio_entidades directorio_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY directorio_crear ON public.directorio_entidades FOR INSERT WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: directorio_entidades directorio_editar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY directorio_editar ON public.directorio_entidades FOR UPDATE USING (public.sigre_usuario_es_autoridad()) WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: directorio_entidades directorio_eliminar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY directorio_eliminar ON public.directorio_entidades FOR DELETE USING (public.sigre_usuario_es_autoridad());


--
-- Name: directorio_entidades; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.directorio_entidades ENABLE ROW LEVEL SECURITY;

--
-- Name: directorio_entidades directorio_ver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY directorio_ver ON public.directorio_entidades FOR SELECT USING (true);


--
-- Name: emergencias; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.emergencias ENABLE ROW LEVEL SECURITY;

--
-- Name: emergencias emergencias_consulta_autenticada; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emergencias_consulta_autenticada ON public.emergencias FOR SELECT TO sigre_app USING ((NULLIF(current_setting('app.user_id'::text, true), ''::text) IS NOT NULL));


--
-- Name: emergencias emergencias_editar_activas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emergencias_editar_activas ON public.emergencias FOR UPDATE TO sigre_app USING (((estado = 'activa'::text) AND ((current_setting('app.user_role'::text, true) = 'autoridad'::text) OR ((current_setting('app.user_role'::text, true) = 'voluntario'::text) AND (registrada_por = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint))))) WITH CHECK (((estado = 'activa'::text) AND ((current_setting('app.user_role'::text, true) = 'autoridad'::text) OR ((current_setting('app.user_role'::text, true) = 'voluntario'::text) AND (registrada_por = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)))));


--
-- Name: emergencias emergencias_finalizar_autoridad; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emergencias_finalizar_autoridad ON public.emergencias FOR UPDATE TO sigre_app USING (((estado = 'activa'::text) AND (current_setting('app.user_role'::text, true) = 'autoridad'::text))) WITH CHECK (((estado = 'finalizada'::text) AND (current_setting('app.user_role'::text, true) = 'autoridad'::text) AND (finalizada_por = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint) AND (finalizada_en IS NOT NULL)));


--
-- Name: emergencias emergencias_registro_autorizado; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emergencias_registro_autorizado ON public.emergencias FOR INSERT TO sigre_app WITH CHECK (((registrada_por = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint) AND (current_setting('app.user_role'::text, true) = ANY (ARRAY['voluntario'::text, 'autoridad'::text]))));


--
-- Name: inventario_centros; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventario_centros ENABLE ROW LEVEL SECURITY;

--
-- Name: inventario_centros inventario_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventario_crear ON public.inventario_centros FOR INSERT WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: inventario_centros inventario_editar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventario_editar ON public.inventario_centros FOR UPDATE USING (public.sigre_usuario_es_autoridad()) WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: inventario_centros inventario_eliminar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventario_eliminar ON public.inventario_centros FOR DELETE USING (public.sigre_usuario_es_autoridad());


--
-- Name: inventario_centros inventario_ver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventario_ver ON public.inventario_centros FOR SELECT USING (true);


--
-- Name: jornadas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.jornadas ENABLE ROW LEVEL SECURITY;

--
-- Name: jornadas jornadas_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jornadas_crear ON public.jornadas FOR INSERT WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: jornadas jornadas_editar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jornadas_editar ON public.jornadas FOR UPDATE USING (public.sigre_usuario_es_autoridad()) WITH CHECK (public.sigre_usuario_es_autoridad());


--
-- Name: jornadas jornadas_eliminar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jornadas_eliminar ON public.jornadas FOR DELETE USING (public.sigre_usuario_es_autoridad());


--
-- Name: jornadas jornadas_ver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jornadas_ver ON public.jornadas FOR SELECT USING (true);


--
-- Name: notificaciones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_actualizar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notificaciones_comentarios_actualizar ON public.notificaciones_comentarios_desaparecidos FOR UPDATE USING ((destinatario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)) WITH CHECK ((destinatario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint));


--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notificaciones_comentarios_crear ON public.notificaciones_comentarios_desaparecidos FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM (public.comentarios_desaparecidos c
     JOIN public.reportes_desaparecidos r ON ((r.id = c.reporte_id)))
  WHERE ((c.id = notificaciones_comentarios_desaparecidos.comentario_id) AND (r.publicado_por = notificaciones_comentarios_desaparecidos.destinatario_id)))));


--
-- Name: notificaciones_comentarios_desaparecidos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones_comentarios_desaparecidos ENABLE ROW LEVEL SECURITY;

--
-- Name: notificaciones_comentarios_desaparecidos notificaciones_comentarios_ver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notificaciones_comentarios_ver ON public.notificaciones_comentarios_desaparecidos FOR SELECT USING ((destinatario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint));


--
-- Name: notificaciones_leidas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones_leidas ENABLE ROW LEVEL SECURITY;

--
-- Name: participaciones_jornadas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.participaciones_jornadas ENABLE ROW LEVEL SECURITY;

--
-- Name: recuperacion_contrasenas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recuperacion_contrasenas ENABLE ROW LEVEL SECURITY;

--
-- Name: rutas_guardadas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rutas_guardadas ENABLE ROW LEVEL SECURITY;

--
-- Name: rutas_guardadas rutas_guardadas_propias; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rutas_guardadas_propias ON public.rutas_guardadas USING ((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)) WITH CHECK ((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint));


--
-- Name: solicitudes_ayuda; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.solicitudes_ayuda ENABLE ROW LEVEL SECURITY;

--
-- Name: solicitudes_ayuda solicitudes_ayuda_crear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY solicitudes_ayuda_crear ON public.solicitudes_ayuda FOR INSERT WITH CHECK ((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint));


--
-- Name: solicitudes_ayuda solicitudes_ayuda_ver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY solicitudes_ayuda_ver ON public.solicitudes_ayuda FOR SELECT USING (((usuario_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint) OR (current_setting('app.user_role'::text, true) = 'autoridad'::text)));


--
-- Name: suscripciones_push; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.suscripciones_push ENABLE ROW LEVEL SECURITY;

--
-- Name: usuarios; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;

--
-- Name: usuarios usuarios_login_o_propio; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY usuarios_login_o_propio ON public.usuarios FOR SELECT TO sigre_app USING (((email = NULLIF(current_setting('app.login_email'::text, true), ''::text)) OR (id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)));


--
-- Name: usuarios usuarios_registro_ciudadano; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY usuarios_registro_ciudadano ON public.usuarios FOR INSERT TO sigre_app WITH CHECK ((rol = 'ciudadano'::text));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO sigre_app;


--
-- Name: FUNCTION admin_adjunto_solicitud(p_solicitud_id bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_adjunto_solicitud(p_solicitud_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_adjunto_solicitud(p_solicitud_id bigint) TO sigre_app;


--
-- Name: FUNCTION admin_cambiar_estado_desaparecido(p_reporte_id bigint, p_estado text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_cambiar_estado_desaparecido(p_reporte_id bigint, p_estado text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_cambiar_estado_desaparecido(p_reporte_id bigint, p_estado text) TO sigre_app;


--
-- Name: FUNCTION admin_cambiar_estado_solicitud(p_solicitud_id bigint, p_estado text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_cambiar_estado_solicitud(p_solicitud_id bigint, p_estado text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_cambiar_estado_solicitud(p_solicitud_id bigint, p_estado text) TO sigre_app;


--
-- Name: FUNCTION admin_cambiar_rol(p_usuario_id bigint, p_rol text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_cambiar_rol(p_usuario_id bigint, p_rol text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_cambiar_rol(p_usuario_id bigint, p_rol text) TO sigre_app;


--
-- Name: FUNCTION admin_crear_emergencia(p_tipo text, p_descripcion text, p_alcance text, p_departamento text, p_municipio text, p_sector text, p_nivel_riesgo text, p_latitud double precision, p_longitud double precision); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_crear_emergencia(p_tipo text, p_descripcion text, p_alcance text, p_departamento text, p_municipio text, p_sector text, p_nivel_riesgo text, p_latitud double precision, p_longitud double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_crear_emergencia(p_tipo text, p_descripcion text, p_alcance text, p_departamento text, p_municipio text, p_sector text, p_nivel_riesgo text, p_latitud double precision, p_longitud double precision) TO sigre_app;


--
-- Name: FUNCTION admin_eliminar_desaparecido(p_reporte_id bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_eliminar_desaparecido(p_reporte_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_eliminar_desaparecido(p_reporte_id bigint) TO sigre_app;


--
-- Name: FUNCTION admin_finalizar_emergencia(p_emergencia_id bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_finalizar_emergencia(p_emergencia_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_finalizar_emergencia(p_emergencia_id bigint) TO sigre_app;


--
-- Name: FUNCTION admin_listar_emergencias(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_listar_emergencias() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_listar_emergencias() TO sigre_app;


--
-- Name: FUNCTION admin_listar_solicitudes(p_estado text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_listar_solicitudes(p_estado text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_listar_solicitudes(p_estado text) TO sigre_app;


--
-- Name: FUNCTION admin_listar_usuarios(p_busqueda text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_listar_usuarios(p_busqueda text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_listar_usuarios(p_busqueda text) TO sigre_app;


--
-- Name: FUNCTION admin_resumen(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_resumen() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_resumen() TO sigre_app;


--
-- Name: FUNCTION contar_usuarios_registrados(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.contar_usuarios_registrados() FROM PUBLIC;
GRANT ALL ON FUNCTION public.contar_usuarios_registrados() TO sigre_app;


--
-- Name: FUNCTION emergencia_activa_publica(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.emergencia_activa_publica() FROM PUBLIC;
GRANT ALL ON FUNCTION public.emergencia_activa_publica() TO sigre_app;


--
-- Name: FUNCTION jornada_participantes(p_jornada_id bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.jornada_participantes(p_jornada_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.jornada_participantes(p_jornada_id bigint) TO sigre_app;


--
-- Name: FUNCTION jornada_participar(p_jornada_id bigint, p_participar boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.jornada_participar(p_jornada_id bigint, p_participar boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.jornada_participar(p_jornada_id bigint, p_participar boolean) TO sigre_app;


--
-- Name: FUNCTION jornadas_estadisticas_categoria(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.jornadas_estadisticas_categoria() FROM PUBLIC;
GRANT ALL ON FUNCTION public.jornadas_estadisticas_categoria() TO sigre_app;


--
-- Name: FUNCTION jornadas_participacion(p_ids bigint[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.jornadas_participacion(p_ids bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.jornadas_participacion(p_ids bigint[]) TO sigre_app;


--
-- Name: FUNCTION sigre_borrar_suscripcion_push(p_endpoint text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_borrar_suscripcion_push(p_endpoint text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_borrar_suscripcion_push(p_endpoint text) TO sigre_app;


--
-- Name: FUNCTION sigre_crear_codigo_verificacion(p_email text, p_codigo_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_crear_codigo_verificacion(p_email text, p_codigo_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_crear_codigo_verificacion(p_email text, p_codigo_hash text) TO sigre_app;


--
-- Name: FUNCTION sigre_crear_recuperacion(p_email text, p_token_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_crear_recuperacion(p_email text, p_token_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_crear_recuperacion(p_email text, p_token_hash text) TO sigre_app;


--
-- Name: FUNCTION sigre_cuenta_sin_verificar(p_email text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_cuenta_sin_verificar(p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_cuenta_sin_verificar(p_email text) TO sigre_app;


--
-- Name: FUNCTION sigre_descartar_suscripcion_push(p_endpoint text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_descartar_suscripcion_push(p_endpoint text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_descartar_suscripcion_push(p_endpoint text) TO sigre_app;


--
-- Name: FUNCTION sigre_exigir_autoridad(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_exigir_autoridad() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_exigir_autoridad() TO sigre_app;


--
-- Name: FUNCTION sigre_guardar_mi_perfil(p_tipo_documento text, p_numero_documento text, p_fecha_nacimiento date, p_tipo_sangre text, p_alergias text, p_condiciones_medicas text, p_medicamentos text, p_contacto_emergencia_nombre text, p_contacto_emergencia_telefono text, p_direccion text, p_comunidad text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_guardar_mi_perfil(p_tipo_documento text, p_numero_documento text, p_fecha_nacimiento date, p_tipo_sangre text, p_alergias text, p_condiciones_medicas text, p_medicamentos text, p_contacto_emergencia_nombre text, p_contacto_emergencia_telefono text, p_direccion text, p_comunidad text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_guardar_mi_perfil(p_tipo_documento text, p_numero_documento text, p_fecha_nacimiento date, p_tipo_sangre text, p_alergias text, p_condiciones_medicas text, p_medicamentos text, p_contacto_emergencia_nombre text, p_contacto_emergencia_telefono text, p_direccion text, p_comunidad text) TO sigre_app;


--
-- Name: FUNCTION sigre_guardar_suscripcion_push(p_endpoint text, p_p256dh text, p_auth text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_guardar_suscripcion_push(p_endpoint text, p_p256dh text, p_auth text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_guardar_suscripcion_push(p_endpoint text, p_p256dh text, p_auth text) TO sigre_app;


--
-- Name: FUNCTION sigre_marcar_notificaciones_leidas(p_id bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_marcar_notificaciones_leidas(p_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_marcar_notificaciones_leidas(p_id bigint) TO sigre_app;


--
-- Name: FUNCTION sigre_mi_perfil(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_mi_perfil() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_mi_perfil() TO sigre_app;


--
-- Name: FUNCTION sigre_mis_notificaciones(p_limite integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_mis_notificaciones(p_limite integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_mis_notificaciones(p_limite integer) TO sigre_app;


--
-- Name: FUNCTION sigre_notificar(p_destinatario_id bigint, p_rol_destino text, p_tipo text, p_titulo text, p_mensaje text, p_enlace text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_notificar(p_destinatario_id bigint, p_rol_destino text, p_tipo text, p_titulo text, p_mensaje text, p_enlace text) FROM PUBLIC;


--
-- Name: FUNCTION sigre_push_pendientes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_push_pendientes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_push_pendientes() TO sigre_app;


--
-- Name: FUNCTION sigre_restablecer_contrasena(p_token_hash text, p_password_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_restablecer_contrasena(p_token_hash text, p_password_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_restablecer_contrasena(p_token_hash text, p_password_hash text) TO sigre_app;


--
-- Name: FUNCTION sigre_usuario_es_autoridad(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_usuario_es_autoridad() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_usuario_es_autoridad() TO sigre_app;


--
-- Name: FUNCTION sigre_verificar_correo(p_email text, p_codigo_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sigre_verificar_correo(p_email text, p_codigo_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sigre_verificar_correo(p_email text, p_codigo_hash text) TO sigre_app;


--
-- Name: TABLE avatares_usuario; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.avatares_usuario TO sigre_app;


--
-- Name: TABLE centros_ayuda; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.centros_ayuda TO sigre_app;


--
-- Name: TABLE comentarios_desaparecidos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.comentarios_desaparecidos TO sigre_app;


--
-- Name: SEQUENCE comentarios_desaparecidos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.comentarios_desaparecidos_id_seq TO sigre_app;


--
-- Name: TABLE contactos_comentarios_desaparecidos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.contactos_comentarios_desaparecidos TO sigre_app;


--
-- Name: TABLE directorio_entidades; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.directorio_entidades TO sigre_app;


--
-- Name: TABLE emergencias; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.tipo; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(tipo) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.descripcion; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(descripcion) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.alcance; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(alcance) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.departamento; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(departamento) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.municipio; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(municipio) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.sector; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(sector) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.latitud; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(latitud) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.longitud; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(longitud) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.nivel_riesgo; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(nivel_riesgo) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.estado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(estado) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.registrada_por; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(registrada_por) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.actualizada_en; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(actualizada_en) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.finalizada_por; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(finalizada_por) ON TABLE public.emergencias TO sigre_app;


--
-- Name: COLUMN emergencias.finalizada_en; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(finalizada_en) ON TABLE public.emergencias TO sigre_app;


--
-- Name: SEQUENCE emergencias_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.emergencias_id_seq TO sigre_app;


--
-- Name: TABLE inventario_centros; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.inventario_centros TO sigre_app;


--
-- Name: TABLE jornadas; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.jornadas TO sigre_app;


--
-- Name: TABLE notificaciones_comentarios_desaparecidos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.notificaciones_comentarios_desaparecidos TO sigre_app;


--
-- Name: SEQUENCE notificaciones_comentarios_desaparecidos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.notificaciones_comentarios_desaparecidos_id_seq TO sigre_app;


--
-- Name: TABLE reportes_desaparecidos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.reportes_desaparecidos TO sigre_app;


--
-- Name: COLUMN reportes_desaparecidos.telefono_contacto; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(telefono_contacto),INSERT(telefono_contacto) ON TABLE public.reportes_desaparecidos TO sigre_app;


--
-- Name: COLUMN reportes_desaparecidos.publicado_por; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(publicado_por),INSERT(publicado_por) ON TABLE public.reportes_desaparecidos TO sigre_app;


--
-- Name: SEQUENCE reportes_desaparecidos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.reportes_desaparecidos_id_seq TO sigre_app;


--
-- Name: TABLE rutas_guardadas; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE ON TABLE public.rutas_guardadas TO sigre_app;


--
-- Name: TABLE solicitudes_ayuda; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.solicitudes_ayuda TO sigre_app;


--
-- Name: TABLE usuarios; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,UPDATE ON TABLE public.usuarios TO sigre_app;


--
-- Name: COLUMN usuarios.email; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(email) ON TABLE public.usuarios TO sigre_app;


--
-- Name: COLUMN usuarios.password_hash; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(password_hash) ON TABLE public.usuarios TO sigre_app;


--
-- Name: COLUMN usuarios.rol; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(rol) ON TABLE public.usuarios TO sigre_app;


--
-- Name: COLUMN usuarios.nombre; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(nombre),INSERT(nombre) ON TABLE public.usuarios TO sigre_app;


--
-- Name: COLUMN usuarios.telefono; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(telefono),INSERT(telefono) ON TABLE public.usuarios TO sigre_app;


--
-- Name: COLUMN usuarios.email_verificado; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(email_verificado) ON TABLE public.usuarios TO sigre_app;


--
-- Name: SEQUENCE usuarios_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.usuarios_id_seq TO sigre_app;


--
-- PostgreSQL database dump complete
--

\unrestrict 1GTnYN6Eu5V8t6JLm4Pejv7I9J865SqJbInc84ZlTmTbzlpZdYnIfQSk7Fk3OZW

