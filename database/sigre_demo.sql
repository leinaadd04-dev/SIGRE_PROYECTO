--
-- PostgreSQL database dump
--

\restrict lzxAvNwDQXMMTahR0DngEaRpMCbxqrxSvUzpP4HPciy2mf03ZaEVGvqmHxJLLlY

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
    CONSTRAINT centro_coordenadas_validas CHECK ((((latitud IS NULL) AND (longitud IS NULL)) OR ((latitud >= ('-90'::integer)::double precision) AND (latitud <= (90)::double precision) AND ((longitud >= ('-180'::integer)::double precision) AND (longitud <= (180)::double precision))))),
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
    CONSTRAINT jornada_coordenadas_validas CHECK ((((latitud IS NULL) AND (longitud IS NULL)) OR ((latitud >= ('-90'::integer)::double precision) AND (latitud <= (90)::double precision) AND ((longitud >= ('-180'::integer)::double precision) AND (longitud <= (180)::double precision))))),
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
-- Data for Name: avatares_usuario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.avatares_usuario (usuario_id, tipo, animal, foto, foto_mime, actualizado_en) FROM stdin;
1	animal	buho	\N	\N	2026-10-15 23:29:30.986653-05
2	animal	perro	\N	\N	2026-10-15 23:29:30.986653-05
\.


--
-- Data for Name: centros_ayuda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.centros_ayuda (id, nombre, tipo, direccion, descripcion, necesidades, telefono, latitud, longitud, capacidad, ocupados, estado, creado_por, creado_en, actualizado_en) FROM stdin;
1	Coliseo Miguel "Happy" Lora	albergue	Carrera 13 # 22A-48, Montería	Albergue temporal cubierto para familias afectadas por la inundación. Atención 24 horas.	\N	3108236523	8.7565	-75.877	650	240	abierto	1	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05
2	Centro de Acopio Alcaldía	acopio	Calle 27 # 3-16, Centro, Montería	Recepción de donaciones de alimentos, aseo y ropa, de lunes a sábado de 8 a. m. a 5 p. m.	\N	3128407352	8.752	-75.882	0	0	abierto	1	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05
3	Institución Educativa La Ribera	albergue	Barrio La Ribera, Montería	Albergue de apoyo para familias del sur de la ciudad.	\N	\N	8.741	-75.864	180	175	abierto	1	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05
\.


--
-- Data for Name: codigos_verificacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.codigos_verificacion (usuario_id, codigo_hash, expira_en, intentos, enviado_en) FROM stdin;
\.


--
-- Data for Name: comentarios_desaparecidos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.comentarios_desaparecidos (id, reporte_id, usuario_id, nombre_testigo, comentario, veracidad_confirmada, autoriza_compartir_telefono, creado_en) FROM stdin;
1	2	5	Ana Gómez	Vi un perro con collar rojo cerca del parque de La Granja esta mañana.	t	t	2026-10-15 23:29:30.986653-05
\.


--
-- Data for Name: contactos_comentarios_desaparecidos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contactos_comentarios_desaparecidos (comentario_id, telefono_testigo) FROM stdin;
1	3033334455
\.


--
-- Data for Name: directorio_entidades; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.directorio_entidades (id, grupo, nombre, detalle, telefono, direccion, web, orden, actualizado_en, foto, foto_mime, foto_actualizada) FROM stdin;
1	emergencias	Línea única de emergencias	Policía, ambulancias, bomberos y organismos de socorro.	123	\N	\N	1	2026-10-15 23:29:30.986653-05	\N	\N	\N
2	emergencias	Policía Nacional	Atención de emergencias y seguridad a través de la línea 123.	123	\N	\N	2	2026-10-15 23:29:30.986653-05	\N	\N	\N
3	emergencias	Bomberos	Incendios, rescates y materiales peligrosos.	119	\N	\N	3	2026-10-15 23:29:30.986653-05	\N	\N	\N
4	emergencias	Cruz Roja Colombiana	Atención prehospitalaria y ayuda humanitaria.	132	\N	https://www.cruzrojacolombiana.org	4	2026-10-15 23:29:30.986653-05	\N	\N	\N
5	emergencias	Defensa Civil Colombiana	Búsqueda, rescate y apoyo en desastres.	144	\N	https://www.defensacivil.gov.co	5	2026-10-15 23:29:30.986653-05	\N	\N	\N
6	estado	Prosperidad Social	Programas sociales y subsidios. Línea gratuita nacional.	01 8000 951100	\N	https://prosperidadsocial.gov.co	10	2026-10-15 23:29:30.986653-05	\N	\N	\N
7	estado	UNGRD · Gestión del riesgo	Unidad Nacional para la Gestión del Riesgo de Desastres.	\N	\N	https://portal.gestiondelriesgo.gov.co	12	2026-10-15 23:29:30.986653-05	\N	\N	\N
8	salud	E.S.E. Hospital San Jerónimo de Montería	\N	\N	Carrera 14 # 22-200	\N	20	2026-10-15 23:29:30.986653-05	\N	\N	\N
9	salud	Clínica Montería	\N	\N	Calle 30 # 3-19	\N	23	2026-10-15 23:29:30.986653-05	\N	\N	\N
\.


--
-- Data for Name: emergencias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.emergencias (id, tipo, descripcion, alcance, departamento, municipio, sector, latitud, longitud, nivel_riesgo, estado, registrada_por, creada_en, actualizada_en, finalizada_por, finalizada_en) FROM stdin;
1	Inundación	Creciente del río Sinú. Se recomienda a las familias de la margen izquierda ubicarse en zonas altas y seguir las rutas de evacuación.	sector	Córdoba	Montería	Margen izquierda del río Sinú	8.748	-75.885	alto	activa	1	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	\N	\N
\.


--
-- Data for Name: inventario_centros; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_centros (id, centro_id, categoria, producto, cantidad, unidad, minimo, actualizado_por, actualizado_en, talla) FROM stdin;
1	1	no_perecederos	Arroz	120	kg	50	1	2026-10-15 23:29:30.986653-05	\N
2	1	agua	Botellas de agua	30	litros	100	1	2026-10-15 23:29:30.986653-05	\N
3	1	descanso	Colchonetas	0	unidades	20	1	2026-10-15 23:29:30.986653-05	\N
4	1	aseo	Papel higiénico	60	paquetes	20	1	2026-10-15 23:29:30.986653-05	\N
5	1	ropa	Zapatos niño	4	pares	5	1	2026-10-15 23:29:30.986653-05	28
6	1	bebes	Pañales	15	paquetes	10	1	2026-10-15 23:29:30.986653-05	\N
7	2	no_perecederos	Fríjol	80	kg	30	1	2026-10-15 23:29:30.986653-05	\N
8	2	aseo	Jabón de baño	200	unidades	50	1	2026-10-15 23:29:30.986653-05	\N
9	2	mascotas	Concentrado para perro	25	kg	10	1	2026-10-15 23:29:30.986653-05	\N
10	3	botiquin	Suero oral	8	unidades	20	1	2026-10-15 23:29:30.986653-05	\N
11	3	descanso	Cobijas	90	unidades	30	1	2026-10-15 23:29:30.986653-05	\N
\.


--
-- Data for Name: jornadas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.jornadas (id, nombre, categoria, descripcion, fecha_inicio, lugar, latitud, longitud, estado, creada_por, creada_en, fecha_fin) FROM stdin;
1	Recolecta de mercados para familias damnificadas	solidaridad	Recibiremos alimentos no perecederos, agua y artículos de aseo para las familias afectadas por las lluvias. Se necesitan voluntarios para empacar.	2026-12-05 08:00:00-05	Parque Simón Bolívar, Montería	8.7505	-75.88	publicada	1	2026-10-15 23:29:30.986653-05	2026-12-05 12:00:00-05
2	Limpieza del caño de La Ribera	limpieza	Jornada para retirar basuras y escombros del caño y evitar nuevas inundaciones. Lleva guantes y botas.	2026-12-12 07:00:00-05	Barrio La Ribera, Montería	8.742	-75.865	publicada	1	2026-10-15 23:29:30.986653-05	2026-12-12 11:00:00-05
3	Brigada de salud y vacunación	salud	Consulta médica general, vacunación y entrega de medicamentos básicos para las familias albergadas.	2026-09-20 08:00:00-05	Coliseo Miguel "Happy" Lora, Montería	8.7565	-75.877	publicada	1	2026-10-15 23:29:30.986653-05	2026-09-20 14:00:00-05
\.


--
-- Data for Name: notificaciones; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notificaciones (id, destinatario_id, rol_destino, tipo, titulo, mensaje, enlace, creada_en, push_enviada) FROM stdin;
1	\N	\N	emergencia	Nueva emergencia activa: Inundación	Riesgo alto en Margen izquierda del río Sinú, Montería, Córdoba. Creciente del río Sinú. Se recomienda a las familias de la margen izquierda ubicarse en zonas altas y seguir las rutas de evacuación.	dashboard.html	2026-10-15 23:29:30.986653-05	t
2	\N	\N	centro	Nuevo albergue: Coliseo Miguel "Happy" Lora	Carrera 13 # 22A-48, Montería.	centros.html	2026-10-15 23:29:30.986653-05	t
3	\N	\N	centro	Nuevo centro de acopio: Centro de Acopio Alcaldía	Calle 27 # 3-16, Centro, Montería.	centros.html	2026-10-15 23:29:30.986653-05	t
4	\N	\N	centro	Nuevo albergue: Institución Educativa La Ribera	Barrio La Ribera, Montería.	centros.html	2026-10-15 23:29:30.986653-05	t
5	\N	\N	jornada	Nueva jornada: Recolecta de mercados para familias damnificadas	05/12/2026 08:00 AM · Parque Simón Bolívar, Montería. Recibiremos alimentos no perecederos, agua y artículos de aseo para las familias afectadas por las lluvias. Se necesitan voluntarios para empacar.	jornadas.html	2026-10-15 23:29:30.986653-05	t
6	\N	\N	jornada	Nueva jornada: Limpieza del caño de La Ribera	12/12/2026 07:00 AM · Barrio La Ribera, Montería. Jornada para retirar basuras y escombros del caño y evitar nuevas inundaciones. Lleva guantes y botas.	jornadas.html	2026-10-15 23:29:30.986653-05	t
7	\N	\N	jornada	Nueva jornada: Brigada de salud y vacunación	20/09/2026 08:00 AM · Coliseo Miguel "Happy" Lora, Montería. Consulta médica general, vacunación y entrega de medicamentos básicos para las familias albergadas.	jornadas.html	2026-10-15 23:29:30.986653-05	t
8	\N	autoridad	solicitud	Nueva solicitud de ayuda (urgencia alta)	SIGRE-00001 · Calle 30 # 5-20, Barrio La Granja · 4 persona(s) afectada(s).	dashboard_admin.html#solicitudes	2026-10-15 23:29:30.986653-05	t
9	\N	autoridad	solicitud	Nueva solicitud de ayuda (urgencia media)	SIGRE-00002 · Barrio El Dorado, margen izquierda · 35 persona(s) afectada(s).	dashboard_admin.html#solicitudes	2026-10-15 23:29:30.986653-05	t
10	\N	autoridad	solicitud	Nueva visita a vivienda (urgencia alta)	SIGRE-00003 · Carrera 2 # 41-15, Barrio Montería Moderno · 5 persona(s) afectada(s).	dashboard_admin.html#solicitudes	2026-10-15 23:29:30.986653-05	t
11	\N	\N	desaparecido	Nuevo reporte de persona desaparecida: Pedro Ramírez	Visto por última vez en Barrio Mocarí. Si tienes información, déjala en el reporte.	desaparecidos.html?reporte=1	2026-10-15 23:29:30.986653-05	t
12	\N	\N	desaparecido	Nuevo reporte de mascota desaparecida: Firulais	Visto por última vez en Barrio La Granja. Si tienes información, déjala en el reporte.	desaparecidos.html?reporte=2	2026-10-15 23:29:30.986653-05	t
13	\N	\N	desaparecido	Nuevo reporte de persona desaparecida: Sofía Herrera	Visto por última vez en Barrio Cantaclaro. Si tienes información, déjala en el reporte.	desaparecidos.html?reporte=3	2026-10-15 23:29:30.986653-05	t
14	2	\N	comentario	Ana Gómez comentó tu reporte de Firulais	"Vi un perro con collar rojo cerca del parque de La Granja esta mañana." · Tel. 3033334455	desaparecidos.html?reporte=2	2026-10-15 23:29:30.986653-05	t
\.


--
-- Data for Name: notificaciones_comentarios_desaparecidos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notificaciones_comentarios_desaparecidos (id, destinatario_id, comentario_id, leida, creada_en) FROM stdin;
1	2	1	f	2026-10-15 23:29:30.986653-05
\.


--
-- Data for Name: notificaciones_leidas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notificaciones_leidas (notificacion_id, usuario_id, leida_en) FROM stdin;
\.


--
-- Data for Name: participaciones_jornadas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.participaciones_jornadas (jornada_id, usuario_id, creada_en) FROM stdin;
1	3	2026-10-15 23:29:30.986653-05
3	3	2026-10-15 23:29:30.986653-05
1	4	2026-10-15 23:29:30.986653-05
2	4	2026-10-15 23:29:30.986653-05
2	5	2026-10-15 23:29:30.986653-05
3	5	2026-10-15 23:29:30.986653-05
1	2	2026-10-15 23:29:30.986653-05
3	2	2026-10-15 23:29:30.986653-05
\.


--
-- Data for Name: recuperacion_contrasenas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recuperacion_contrasenas (id, usuario_id, token_hash, expira_en, usado, creado_en) FROM stdin;
\.


--
-- Data for Name: reportes_desaparecidos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reportes_desaparecidos (id, tipo, nombre, edad, genero, sector, fecha_visto, descripcion, foto, foto_mime, estado, autoriza_publicacion, creado_en, actualizado_en, telefono_contacto, publicado_por) FROM stdin;
1	persona	Pedro Ramírez	72 años	Masculino	Barrio Mocarí	2026-10-12 17:30:00-05	Adulto mayor con camisa azul y pantalón gris. Usa bastón. Fue visto por última vez cerca de la iglesia del barrio.	\\xffd8ffe000104a46494600010100000100010000ffdb0043000a07070807060a0808080b0a0a0b0e18100e0d0d0e1d15161118231f2524221f2221262b372f26293429212230413134393b3e3e3e252e4449433c48373d3e3bffdb0043010a0b0b0e0d0e1c10101c3b2822283b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3bffc00011080140014003012200021101031101ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc4001f0100030101010101010101010000000000000102030405060708090a0bffc400b51100020102040403040705040400010277000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c03010002110311003f00f19a28ae96d3cb83c1704eb369b04d25edd2b1bab312c92858e02155bcb6c60b3752396a00e6a8aec6e63886b3aae91f61b54d3ecade5920985ba07011774521931b9b79da39241f3381d31289c4da55ace6c34f79d74692ed516c215f325175247b8ed519db182d8e9f2720f3401c4d15d769b041a86abe14babbb3b7596f352114d12c0a91cd12c9185628005e4b3a9c0c1d9eb9a9fc38b0ea96cd7d7f6d6114d09b858656b3458d80b499c96455c36c658dbee93f377e28038aa2ba5d1bcbbaf15379d369b70a96574c254b30b002b6f232b18fcb19da403f70f4ef4ba3d9b6a1e2fd36694595ed9aea16b0cef6f6e2385b7b67694d8b9c856cfcbdbe9401ccd15d2dff00976fe15d27cb9b4d85a7b2769227b30d3ca7ed132ee1279671c281f7c7ddaea353d234c8bc45e20bc4d3ed96da5b5bcb7b78044a1219638e7cb28c6011f67078e9e60a00f32a2bd0ad23d246bba3e9f731e9d30b85d2c456b1d98122bb081a4691f600c194c991b9b25c71c71cb69016df46d4b518e0867ba81e1441344b2ac71b6fdcfb581079545c9071bfd714018d456deb3690492d8cced6f6135cd889e74d8ca81f730185453b772856c600f9bb0c569688da75af86ec2eafcd8885b51b85b9496d04935c46b1c07623ec3b4fccd83b9705b3401c9515dd2436c7c4de1db12da53c133699e6598b11e69df1c458b3f97860c4927e639ddcd45e1c58754b66bebfb6b08a684dc2c32b59a2c6c05a4ce4b22ae1b632c6df749f9bbf1401c5515db6b7e4e99a0e9fa8d95ae9f737570765cdd259a342c072852365c2eecb29f9412613ef98e1b2b4b5d635fd8b656a62d361987daa0f3a3b695e4b7debb4ab9e0bba742450071b4577eda469cd35fdbbad94736a3b6ded079273248b0ab16870a42092568c8cedf9491ea2af69da46992f887c3d78da7db35b456d676f730189764d2c890619863049fb413cf5f2cd00799515e8da2e89a3bde69a1b4680b32e9cecccf23125e5803b32962a55c3b8c631c37b557b786d5b469eeda5d1dee16ca5717c2c0790bfe916ca14c7e567780cfcece920e7d00381a2ba5d32f1acbedda9dc47a75d5b44fb6306c22293cc46142864055401b880074c70585735400514514005145140051451400514514005145140051451400514514005145140053ccd2b40b0191cc48c5d632c76ab1001207a90ab9fa0f4aeeffe104d2ffe7e2eff00efb5ff00e268ff0084134bff009f8bbffbed7ff89ae8fab5431f6d038b9354d425b25b192fee5ed531b606998c6b8e985ce2a38ef6ee2920923ba991ed862165908310c93853db96278ee4fad771ff00082697ff003f177ff7daff00f1347fc209a5ff00cfc5dffdf6bffc4d1f56a81eda071526a57f35ea5f4b7d7125d46559276958c8a47421b3918ed5236b7ab3ddc776daa5e35cc4a56398dc39740410406ce40209fcebb1ff0084134bff009f8bbffbed7ff89a3fe104d2ff00e7e2effefb5ffe268fab540f6d038d3ac6a86f96f8ea5766ed14aadc79ede600410406ce718247e2694eb7ab34d24cdaa5e19658fcb77370fb9d3fba4e791ed5d8ff00c209a5ff00cfc5dffdf6bffc4d1ff082697ff3f177ff007dafff001347d5aa07b681c6aeb1aa258fd85752bb5b40a57ece27611e09248db9c60924fe34d7d535190b17bfb96dcd239cccc72d20c487af561c31ee3ad769ff00082697ff003f177ff7daff00f1347fc209a5ff00cfc5dffdf6bffc4d1f56a81eda070e2f2e85cc7742e6613c3b3cb9439de9b000983d4600007a605596d7b596b84b96d5ef8cd182a921b97dca0f500e7201aebffe104d2ffe7e2eff00efb5ff00e268ff0084134bff009f8bbffbed7ff89a3ead503db40e1279e6ba9de7b899e695ce5e4918b331f524f5a0cd2b40b0191cc48c5d632c76ab1001207a90ab9fa0f4aeeffe104d2ffe7e2eff00efb5ff00e268ff0084134bff009f8bbffbed7ff89a3ead503db40e43fb7b59f2a28bfb5afbcb80a1893ed0f88f6636ed19e31818c74c0a8e7d5b52ba984d71a8dd4d22a3461e4999982b0219724f42090477c9aecffe104d2ffe7e2eff00efb5ff00e268ff0084134bff009f8bbffbed7ff89a3ead503db40e32db57d4ecb6fd9351bbb7da9e5af953b2e1725b6f07a64938f526a017138f3b13483cf1b65c31fde0c86c37af201e7b806bbaff0084134bff009f8bbffbed7ff89a3fe104d2ff00e7e2effefb5ffe268fab540f6d03897d42f5e48247bc9d9ed828858cac4c41718da73c630318f4a72eaba92b065d42e810f1b82266e1a3188cf5eaa3807b0e95da7fc209a5ff00cfc5dffdf6bffc4d1ff082697ff3f177ff007dafff001347d5aa07b681c8af8835a589225d5efc471840882e5f0a10829819e3695523d3031d2a1b4d5752b05db65a85d5b0f9b886664fbdb73d0f7d8b9ff747a0aed3fe104d2ffe7e2eff00efb5ff00e268ff0084134bff009f8bbffbed7ff89a3ead503db40e463f10eb916ff2f59bf4f31f7bedb971b9b0064f3c9c0033ec2b3ebbeff84134bff9f8bbff00bed7ff0089a3fe104d2ffe7e2eff00efb5ff00e268fab540f6d0381a2bbeff0084134bff009f8bbffbed7ff89a3fe104d2ff00e7e2effefb5ffe268fab540f6d0381a2bbeff84134bff9f8bbff00bed7ff0089a3fe104d2ffe7e2eff00efb5ff00e268fab540f6d0381a2bbeff0084134bff009f8bbffbed7ff89a3fe104d2ff00e7e2effefb5ffe268fab540f6d0381a2bbeff84134bff9f8bbff00bed7ff0089a3fe104d2ffe7e2eff00efb5ff00e268fab540f6d0381a2bbeff0084134bff009f8bbffbed7ff89a3fe104d2ff00e7e2effefb5ffe268fab540f6d0381a2bbeff84134bff9f8bbff00bed7ff0089a3fe104d2ffe7e2eff00efb5ff00e268fab540f6d0381a2bbeff0084134bff009f8bbffbed7ff89a3fe104d2ff00e7e2effefb5ffe268fab540f6d0381a2bbeff84134bff9f8bbff00bed7ff0089a3fe104d2ffe7e2eff00efb5ff00e268fab540f6d03a5a28a2bd238828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a29f0c32dc4a2282279646e888a589fc052019456fd9f82b59ba8f7b471db02015f39f04e7d80247e38ad44f878e635326a615f0370583201f63b867f2acdd6a6b7668a9cdf438ca2bb4ff008577ff00515ffc97ff00ecab36e3c0dacc31868c417049c6d8e4c11eff00300292ad4df5074a6ba1ced152dc5adc5a4823b982485c8c85910a923d706a2ad4cc28a28a60145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014515dbf83bc351ac516ad78bb9dbe682361c28ecc73d4f71f9fa633a93505765420e4ec8cdd03c1d36a51a5ddeb182d5c12aabfeb1fd08c8c01efedd39cd77563a6d9699118ecad92153d48e4b75ea4f27a9eb56a8af3aa5594f73b614e31d828a28ac8d028a28a0082eecedafe0305dc093467b30ce0e3191e879ea2b8cd77c10f086b9d28991002cd031cb0e7f87d78ec79e3be6bbaa2b4854941e844a1196e78b515e8be2bf0d47a940f7d6cbb6f235c90a33e7003a607f17a7e5e98f3aaf469d45515d1c538383b30a28a2b52028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00ddf0968abab6a7be619b7b6c3b8c0218e78520f63839e3b63bd7a6564f86b4d1a66870445489241e6cbb81077301c107a60607e15ad5e5d69f3cbc8efa50e58851451589a05145140051451400514514005701e38d156d2e975384623b96c48b8002be3a8fae09fa83cf35dfd55d4ac63d4f4e9eca438595700ff0074f507df04035a529f24ae4548f346c790514ae8f148d1c8a51d490cac30411d88a4af58f3c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a002ade936c2f357b4b768cc8924ca1d46795cfcdd3db3552b6bc1ff00f23459ff00c0ff00f406a89bb45b2a2af248f4fa28a2bc83d10a28a2800a28a2800a28a2800a28a2800a28a2803cbbc596c2d7c497416328921122e73f3640248cff00b59ac7ae9fc7ff00f21d87febd97ff00426ae62bd6a4ef0479f515a4c28a28ad080a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800ad7f0acd1c1e25b2791b6a96280e33cb2951fa9159152dadc3da5dc3731805e1915d4374241cf3532578b438bb34cf64a2a38668ee208e789b7472287438c64119152578e7a4145145001451450014514500145145001451450079d78ee68e5f102a2365a28151c63a1c96fe44573757f5cbe1a96b57576a4147930840232a3853cfb01542bd7a6b96091e74dde4d8514515648514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051451401e83e07d5bed7a73584af99ad7ee64f2d19e9dfb1e3d00db5d45790e97a94da56a115dc0c7e53f3a838debdd4fd7ffaf5eab617d0ea56315e5b926394646e18239c107e841af3b114f965ccb6676d19dd58b345145731b051451400514514005145140056278af56fecad1dfcb7db713feee2c1c11eadd41e0771d0915af3cd1dbc124f2b6d8e352ee719c00326bcb7c41ad49ad6a2d365d604e218d8fdd1ebc773d7f4cf15bd0a7cf2bf4465567cb1f33328a28af4ce10a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800ad8f0f78866d0ee707325a487f7917a7fb4beffcff002231e8a994549598d369dd1ebfa76a36daa59a5d5abee46e083d54f70476356abc7ac6feeb4db917167318a4008c8c1c83d883c1aecf4bf1e5bcb88f5387c86ff9eb102c9dfa8ea3b0eff857054c3ca3ac75475c2b27b9d75155acf50b3d423df69731cc0004ec6c95cf4c8ea3f1ab35ced5b737dc28a2a2b8bab7b48c49733c70a1380d238504fa64d2025a8ae6e61b3b67b8b8904714632cc7b5737a9f8eac608f6e9e86ea42386605117af5cf27b71efd6b8cd5357bdd62712de4bbb6e7620185404f403faf5e057453c3ca5be88c675a2b6d4d4f1278a64d6716d6c1e1b318255b8690fbe3b0ec3f1f4c73d4515e8462a2ac8e3949c9dd8514515420a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a2ad58e9b7ba9ca63b2b67998752380bd7a93c0e87ad75363f0f9c90da85e80013948067231c7cc7a73ec6b39d48c3765c61296c8e328af4b87c17a1c51047b67998757795813f9103f4a7ff00c21fa0ff00cf87fe467ffe2ab1fad43ccd3d848f31a2bd3bfe10fd07fe7c3ff233ff00f1547fc21fa0ff00cf87fe467ffe2a8fad43b30f6123cc6ada6afa9c51ac71ea37488a00555998000760335e87ff00087e83ff003e1ff919ff00f8aa3fe10fd07fe7c3ff00233fff001549e269bdd0fd84d753cfbfb6b55ffa09de7fdff6ff001aa55e9dff00087e83ff003e1ff919ff00f8aa3fe10fd07fe7c3ff00233fff001542c4d35b207426fa9e63457a77fc21fa0ffcf87fe467ff00e2a8ff00843f41ff009f0ffc8cff00fc553fad43b317b091e63457a77fc21fa0ff00cf87fe467ffe2a91fc1ba13c6cab665090406595f2bee327147d6a1d987b091e654576d7df0f9082da7de90401849c67273cfcc3a71ec6b98d4f45d4348936dddb954ce1655e51baf43f81383cfb56b0ab09eccce54e51dd1428a28ad480a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800adff000f78566d647da267305a0380d8cb49cf217f5e7d7d79c50d0f499359d4e3b55e107cf2b670550119c7bf381f5af54b6b686ced92dede311c518c2a8ed5cd5eaf268b737a54f9b57b0db4b3b6b0804169024318eca31938c64fa9e3a9a9e8a2bcebdcec0a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a8e6862b888c53c492c6dd51d4303f81a928a00f3ff0011f83df4f8e4bdb0264b704978b196897d73dc75f703d7935cb57b3ba24b1b472287460432b0c820f622bccbc51a1ff636a3fba5c5acf9687e6c918c641fa13f911ce735df42b397bb2dce4ab4f975462d14515d6738514514005145140051451400514514005145140051451400514514005145140051451401e87e05b116fa2b5d9037dd484e413f757800fe3bbf3ae9aa0b2b7fb1d8dbdaefdfe4c4b1eec633818ce2a7af2272e69367a315cb14828a28a82828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a002b1bc57622fbc3d723037c03ce424918dbd7a7fb3b87e35b345545f2b4c4d5d58f16a2a6bdb7fb1df5c5aefdfe4cad1eec633838ce2a1af5d6a79a145145300a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803da68a28af14f4c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f23d6bfe43b7fff005f327fe846a955dd6bfe43b7ff00f5f327fe846a957b11f851e6cb7614514550828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f69a28a2bc53d30a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803c8f5aff90edfff00d7cc9ffa11aa55775aff0090edff00fd7cc9ff00a11aa55ec47e1479b2dd8514515420a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803da68a28af14f4c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f23d6bfe43b7ff00f5f327fe846a955dd6bfe43b7fff005f327fe846a957b11f851e6cb7614514550828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f69a2aae9977f6fd32daec942d2c4acdb0f01b1c8fc0e455aaf19ab3b1e9a770a28a290051451400514514005145140051451400514514005145140051451400514535dd228da4918222825998e0003b93401e4bad7fc876ff00febe64ff00d08d52a96eae1eeeee6b99000f348cec17a024e78a8abd94ac8f35ee1451453105145140051451400514514005145140051451400514514005145140051451401df780f5159b4e934f77fde5bb1645381f21f4ee70d9cfd457575e43a5ea53695a84577031f94fcea0e37af753f5ff00ebd7aad85f43a958c5796e498e5191b8608e7041fa106bcec453e597374676519dd58b345145731b851451400514514005145140051451400514514005145140051451400560f8c7515b1d0a5895f6cd75fba40304e3f8b83db1919f715b53cd1dbc124f2b6d8e352ee719c00326bcb7c41ad49ad6a2d365d604e218d8fdd1ebc773d7f4cf15bd0a7cd2bf4465567cb1b199451457a670851451400514514005145140051451400514514005145140051451400514514005145140056ae89e21bcd0e4610e2581c82f0bf4fa8f438e33fa1c0acaa2a5c549598d369dd1eb9a5eaf65ac4065b39776dc6f4230c848e847f5e9c1abb5e330cd2dbca2582578a45e8e8c548fc4574563e3ad4edc817691dda649391b1ba740471d7d8d714f0cd7c27546bafb47a2515ca43f1034f68819ed2e524eea9b580fc491fca9ff00f09fe95ff3ef79ff007c2fff001558fb1a9d8d3da43b9d4515cbff00c27fa57fcfbde7fdf0bffc551ff09fe95ff3ef79ff007c2fff001547b1a9d83da43b9d4515cbff00c27fa57fcfbde7fdf0bffc551ff09fe95ff3ef79ff007c2fff001547b1a9d83da43b9d4515cbff00c27fa57fcfbde7fdf0bffc551ff09fe95ff3ef79ff007c2fff001547b1a9d83da43b9d4515cbff00c27fa57fcfbde7fdf0bffc551ff09fe95ff3ef79ff007c2fff001547b1a9d83da43b9d4515cbff00c27fa57fcfbde7fdf0bffc5523f8ff004c11b18ed6e99f0768655009f73b8e3f2a3d8d4ec1ed21dcea6ab5f5fdae9b6c6e2f2611460819393927b003935c45f78f7509c15b3823b5040f98fef181cf6278f6e95ce5dde5cdfce67bb9de690f7639c0ce703d073d056b0c349fc4672ae96c6bf883c5373aceeb78c793661b2107de71db77f3c0fd700d61514577462a2ac8e5949c9dd8514515420a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803fffd9	image/jpeg	activo	t	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	3044445566	2
2	animal	Firulais	3 años	Macho	Barrio La Granja	2026-10-12 17:30:00-05	Perro criollo color café con collar rojo. Se asustó con la tormenta y salió corriendo.	\\xffd8ffe000104a46494600010100000100010000ffdb0043000a07070807060a0808080b0a0a0b0e18100e0d0d0e1d15161118231f2524221f2221262b372f26293429212230413134393b3e3e3e252e4449433c48373d3e3bffdb0043010a0b0b0e0d0e1c10101c3b2822283b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3bffc00011080140014003012200021101031101ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc4001f0100030101010101010101010000000000000102030405060708090a0bffc400b51100020102040403040705040400010277000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c03010002110311003f00f19a28ae96d3cb83c1704eb369b04d25edd2b1bab312c92858e02155bcb6c60b3752396a00e6a8aec6e63886b3aae91f61b54d3ecade5920985ba07011774521931b9b79da39241f3381d31289c4da55ace6c34f79d74692ed516c215f325175247b8ed519db182d8e9f2720f3401c4d15d769b041a86abe14babbb3b7596f352114d12c0a91cd12c9185628005e4b3a9c0c1d9eb9a9fc38b0ea96cd7d7f6d6114d09b858656b3458d80b499c96455c36c658dbee93f377e28038aa2ba5d1bcbbaf15379d369b70a96574c254b30b002b6f232b18fcb19da403f70f4ef4ba3d9b6a1e2fd36694595ed9aea16b0cef6f6e2385b7b67694d8b9c856cfcbdbe9401ccd15d2dff00976fe15d27cb9b4d85a7b2769227b30d3ca7ed132ee1279671c281f7c7ddaea353d234c8bc45e20bc4d3ed96da5b5bcb7b78044a1219638e7cb28c6011f67078e9e60a00f32a2bd0ad23d246bba3e9f731e9d30b85d2c456b1d98122bb081a4691f600c194c991b9b25c71c71cb69016df46d4b518e0867ba81e1441344b2ac71b6fdcfb581079545c9071bfd714018d456deb3690492d8cced6f6135cd889e74d8ca81f730185453b772856c600f9bb0c55ab4f2e0f05c13acda6c13497b74ac6eacc4b24a163808556f2db182cdd48e5a8039aa2bbd8aced6282e0c6da5d939fec8512de598957f7968cce00d8d82cc0313c671c9a86f6c2c46b10793a72416e74bd49cc4e8094656bb09b8f765c4601ebc2fb500711456eea7a6adcf892c74fb64487ed36b623e5500067b788b31c7b9249fa9ad9d5acb4cb9b5d5352d3a3b492de4d3b6c46088aac5225dc2bc065521bca74c9c725dbae4d0071345753e2686de4b1967b4b68608adef042d03da8867b5255b11b11c483e43f3125be5e719ae5a800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a799a56816032398918bac658ed56200240f521573f41e95deff00c203a57fcfc5e7fdf6bffc4d1ff080e95ff3f179ff007dafff00135cff0059a66ff5799c4c9aa6a12d92d8c97f72f6a98db034cc635c74c2e7151c77b771490491dd4c8f6c310b2c84188649c29edcb13c7727d6bbaff84074aff9f8bcff00bed7ff0089a3fe101d2bfe7e2f3fefb5ff00e268facd30fabcce224d4afe6bd4be96fae24ba8cab24ed2b19148e84367231daa46d6f567bb8eedb54bc6b9894ac731b872e8082080d9c80413f9d767ff00080e95ff003f179ff7daff00f1347fc203a57fcfc5e7fdf6bffc4d1f59a61f5799c59d635437cb7c752bb3768a556e3cf6f3002082036738c123f134a75bd59a69266d52f0cb2c7e5bb9b87dce9fdd273c8f6aecff00e101d2bfe7e2f3fefb5ffe268ff84074aff9f8bcff00bed7ff0089a3eb34c3eaf338b5d63544b1fb0aea576b6814afd9c4ec23c12491b738c1249fc69afaa6a32162f7f72db9a4739998e5a41890f5eac3863dc75aedbfe101d2bfe7e2f3fefb5ffe268ff84074aff9f8bcff00bed7ff0089a3eb34c3eaf3385179742e63ba173309e1d9e5ca1cef4d8004c1ea300003d302acb6bdacb5c25cb6af7c668c15490dcbee507a8073900d763ff080e95ff3f179ff007dafff001347fc203a57fcfc5e7fdf6bff00c4d1f59a61f5799c14f3cd753bcf7133cd2b9cbc92316663ea49eb419a56816032398918bac658ed56200240f521573f41e95deffc203a57fcfc5e7fdf6bff00c4d1ff00080e95ff003f179ff7daff00f1347d66987d5e670b25e5d4b198e4b999d1b66559c90762ed4e3fd95240f40702a57d5b529209a07d42e9a2b87324d19998ac8c4e4b30cf249ee6bb5ff84074aff9f8bcff00bed7ff0089a3fe101d2bfe7e2f3fefb5ff00e268facd30fabcce38ebdac1b74b73ab5f1851422c66e1f6aa818000ce00038aac979751db3db25ccab03e77441c856c952723a1e514ff00c047a0aeebfe101d2bfe7e2f3fefb5ff00e268ff0084074aff009f8bcffbed7ff89a3eb34c3eaf3387b9d46faf638e3bbbdb8b8488623596566083d813c74155ebd03fe101d2bfe7e2f3fefb5ffe268ff84074aff9f8bcff00bed7ff0089a3eb34c3eaf33cfe8af40ff84074aff9f8bcff00bed7ff0089a3fe101d2bfe7e2f3fefb5ff00e268facd30fabccf3fa2bd03fe101d2bfe7e2f3fefb5ff00e268ff0084074aff009f8bcffbed7ff89a3eb34c3eaf33cfe8af40ff0084074aff009f8bcffbed7ff89a3fe101d2bfe7e2f3fefb5ffe268facd30fabccf3fa2bd03fe101d2bfe7e2f3fefb5ffe268ff84074aff9f8bcff00bed7ff0089a3eb34c3eaf33cfe8af40ff84074aff9f8bcff00bed7ff0089a3fe101d2bfe7e2f3fefb5ff00e268facd30fabccf3fa2bd03fe101d2bfe7e2f3fefb5ff00e268ff0084074aff009f8bcffbed7ff89a3eb34c3eaf33cfe8af40ff0084074aff009f8bcffbed7ff89a3fe101d2bfe7e2f3fefb5ffe268facd30fabccf3fa2bd03fe101d2bfe7e2f3fefb5ffe268ff84074aff9f8bcff00bed7ff0089a3eb34c3eaf33cfe8af40ff84074aff9f8bcff00bed7ff0089a3fe101d2bfe7e2f3fefb5ff00e268facd30fabccf3fa2bd03fe101d2bfe7e2f3fefb5ff00e268ff0084074aff009f8bcffbed7ff89a3eb34c3eaf33a7a28a2bcd3d00a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a7c30cb71288a089e591ba2229627f01400ca2b7ad3c19ac5d26f68e3b604023ce7c139f60091f8e2b4d3e1f3945326a615f0370587201f63b867f2ad551a8f6466eac17538ea2bb2ff00857dff00514ffc97ff00ecab3ae3c11ac4281a3104e49c6d8e4c11eff30028746a2e8255a0fa9cf5152dc5b5c5ab88ee60921723216442a48f5e6a2ac8d428a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a2bb5f087872358a3d56f1773b7cd046c3851d98e7a9ee3f3fa5d3a6e72b222735057667683e109b5244babc6305ab82542ffac7f42323007bfb74e735dbd8e9b67a6c463b3b74854f52392dd7a93c9ea7ad5aa2bd2a74a30d8f3e75253dc28a28ad4cc28a28a0082eecedafa0305d4293467b30ce0e3191e879ea2b8ed73c14f086b9d2b3220059a063961cff000faf1d8f3c77cd77145673a719ad4d215250d8f1aa2bd0bc53e1c8f5281ef6d976ddc6b921467ce0074c0fe2f4fcbd31e7b5e6d4a6e9bb33be9d4535741451456668145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145006e7853465d5753df30ff0047b6c3b8c0218e78520f63839fa63bd7a4d65786f4e1a6e890445489241e6cbb8107711d083d30303f0ad5af528d3e48799e6d69f3c828a28ad8c828a28a0028a28a0028a28a002b83f1b68cb6b74ba942311dc36245c0015f1d47d704fd41e79aef2aaea5631ea5a74f6721c2cab807fba7a83f81c1acaac39e3634a73e495cf24a295d1e3768e4528ea486561820fa1a4af28f4c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a002ade956c2f356b4b768cc8924ca1d46795cfcdd3db3552b67c23ff00233da7fc0fff00406aa82bc92266ed16cf4ca28a2bd83ca0a28a2800a28a2800a28a2800a28a2800a28a2803cc7c576c2dbc477416328921120ce7e6c804919ff6b35915d378f3fe4370ff00d7b2ff00e84d5ccd793555a6cf529bbc10514515996145145001451450014514500145145001451450014514500145145001451450014514500145145001451450015ade169a383c4966f236d52c501c67965207ea4564d4b6d70f6b750dcc601785d5d4374241cf34e2ed24c52574d1ec145470cd1dc411cf136e8e450ea718c82322a4af64f2428a28a0028a28a0028a28a0028a28a0028a28a00f3cf1ccd1cbaf2a2365a28151c63a1c93fc88ae76af6b77a351d66eae94828ef842011951c29e7d80aa35e4547cd36cf520ad14828a28a82c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00effc13aafdaf4e6b195f32db7ddc9e590f4efd8f1e806dae9abc974bd466d2afe3bb858fca7e75071bd7ba9fafff005ebd4ac2f61d46ca2bbb724c728c8dc30473820fe20d7a387a9cd1e57ba382bd3e595d6ccb145145749ce145145001451450014514500158be29d57fb2f487f2df6dc4ff00bb8b07047ab750781dc7722b5a69a3b78249e56db1c6a5d8e3380064d798ebdacc9acea2d365d605e218d8fdd1ebc773d7f4cf15857a9c91b7566d469f34afd0cca28a2bcc3d10a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800ad7f0ff8826d12e307325ac87f7917a7fb4beffcff00223228a71938bba14a2a4accf5bd3f50b6d52cd2ead5f7237041eaa7b823b1ab55e45657f75a75c0b8b498c520046460e41ec41e0d763a5f8ea09711ea71790dff003d6304a77ea3a8ec3bfe15df4f1119692d19c3528496b1d4eb28aaf697f697e9bed2e63980009d8d92b9e991d47e3562ba53bec73b560a28a8ae2e6ded5049733c70a1380d238504fa734c096a2b9b986ceddee2e2411c518cb31ed5ce6a5e38b28136e9e86ea42386605517af5cf27b71efd6b8ed4f56bcd5e712ddcbbb6e7620185404f403faf5e057354c4463b6ace885094b7d0d3f11f8a24d6316f6c1e1b418255b8690fbe3b0f4fc7d31814515c129393bb3b6315156414514549414514500145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014559b1d36f35294c7676ef330ea47017af52781d0f5aea2cbc02f90d7f780004e52019c8c71f31e9cfb1ab8539cf6444aa463bb38ea2bd221f06e8914411ed9e661d5de5604fe440fd29fff00088e85ff003e3ff915ff00c6b6faacfc8cbeb303cd28af4bff00844742ff009f1ffc8aff00e347fc223a17fcf8ff00e457ff001a3eab3ee83eb30ec79a55b4d5b528d1638f50ba445002aaccc001e839af40ff00844742ff009f1ffc8aff00e347fc223a17fcf8ff00e457ff001a6b0d516cc4f1107ba380fed9d57fe82777ff007fdbfc6a9d7a5ffc223a17fcf8ff00e457ff001a3fe111d0bfe7c7ff0022bff8d0f0d51eec16220b6479a515e97ff088e85ff3e3ff00915ffc68ff00844742ff009f1ffc8aff00e34beab3ee87f598763cd28af4bff844742ff9f1ff00c8affe348fe0fd0d91945a14241019657cafb8c9c51f559f741f5981e6b457697be014c16b0bc208030938ce4e79f9874e3d8d733a968d7fa4be2ee02a99c2c8bca375e87f027079f6aca74a70dd1a46a465b328d1451599a05145140051451400514514005145140051451400514514005145140051451400514514005145140056f787fc2f36b03ed133982d41c06c64c9cf217f5e7d7d79c51d134a9358d4e3b65e107cf2b670550119c7bf381f5af50b6b686cedd2dede311c518c2a8ed5d3428f3eb2d8e7ad579745b8db4b3b6b180416b0a4318eca31938c64fa9e3a9a9e8a2bd14ac706e145145001451450014514500145145001451450014514500151cd0c571118a789258dbaa3a8607f035251401c0f887c22f60925ed81325b824b458cb44beb9ee3afb81ebc9ae62bd8dd124468e450e8c0865619047a1af35f13e89fd8fa8fee9716b3e5a1f9b24631907e84fe4473d6bcfaf4547de8ec7750abcdeecb731a8a28ae53a428a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f40f03d90b7d19ae881bee9c9c827eeaf001fc777e75d2d41676ff0064b182db7eff0026258f76319c0c67153d7af08f2c523ca9cb9a4d851451564851451400514514005145140051451400514514005145140051451400563f8aac85ef87ee0606f8479ca49231b7af4ff6723f1ad8a2a651e64d0e2f95dcf1aa2a6bcb7fb25f4f6dbf7f932b47bb18ce0e338a86bc77a1eb6e1451450014514500145145001451450014514500145145001451450014514500145145007b2d14515ed1e40514514005145140051451400514514005145140051451400514514005145140051451401e4dacff00c86eff00febe64ff00d08d53ab9acffc86efff00ebe64ffd08d53af1a5f133d68ec828a28a430a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803d968a28af68f2028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f26d67fe4377fff005f327fe846a9d5cd67fe4377ff00f5f327fe846a9d78d2f899eb47641451452185145140051451400514514005145140051451400514514005145140051451401ecb451457b47901451450014514500145145001451450014514500145145001451450014514500145145007936b3ff21bbfff00af993ff42354eae6b3ff0021bbff00faf993ff0042354ebc697c4cf5a3b20a28a290c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f65a2aae9b77f6ed32dae8942d2c4acdb0f01b1c8fc0e455aaf653bab9e4b56760a28a298828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a29aee91a34923044504b331c003d4d007946b3ff0021bbff00faf993ff0042354ea5b9b87baba9ae64003ccecec17a024e78a8abc66eecf592b20a28a290c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00ef3c0ba82cda74960effbc818b229c0f90fa773839cfd457535e4ba5ea336957f1ddc2c7e53f3a838debdd4fd7ffaf5ea5617b0ea36515ddb926394646e18239c107f106bd1c3d4e68f2f547057872cb9ba32c514515d27385145140051451400514514005145140051451400514514005145140056178bf505b1d0e48d5f6cb73fbb40304e3f8b83db1919f715b334d1dbc124f2b6d8e352ec719c00326bcc75ed664d675169b2eb02f10c6c7ee8f5e3b9ebfa678ac2bd4e48dbab37a30e695fa23328a28af30f4028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a002b5345f105de88ec22c490b905e27e9f51e871c67f43815974538c9c5dd09a525667ac699ab59eaf0196d25ddb71bd08c32123a11fd7a706aed78ec334b6f2896095e2917a3a31523f115d0d978e353b7205d247749924e46c6e9d011c7e95dd0c527f11c73c3b5f09e834572d0f8fac1a2067b4b9493baa6d603f1247f2a7ff00c279a57fcfbddffdf0bffc556deda9f732f653ec74d45733ff0009e695ff003ef77ff7c2ff00f1547fc279a57fcfbddffdf0bffc551eda9f717b29f63a6a2b99ff0084f34aff009f7bbffbe17ff8aa3fe13cd2bfe7deeffef85ffe2a8f6d4fb87b29f63a6a2b99ff0084f34aff009f7bbffbe17ff8aa3fe13cd2bfe7deeffef85ffe2a8f6d4fb87b29f63a6a2b99ff0084f34aff009f7bbffbe17ff8aa3fe13cd2bfe7deeffef85ffe2a8f6d4fb87b29f63a6a2b99ff0084f34aff009f7bbffbe17ff8aa6bf8f74d08c63b6ba67c1da1954027dce4e3f2a3db53ee1eca7d8ea2abdedfdae9d6e6e2ee611460819393927b003935c4def8eefe7056d208ed4103e63f3b039ed9e3f4ae7aeef2e6fa733dd4cf3487bb1ce067381e839e82b19e2a2be1d4d618793f88d6d7bc5173ac6eb78c793681b2107de71db77f3c0fd700d61d14570ca4e4eeced8c545590514514861451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500145145007ffd9	image/jpeg	activo	t	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	3007654321	2
3	persona	Sofía Herrera	15 años	Femenino	Barrio Cantaclaro	2026-10-12 17:30:00-05	Adolescente de cabello negro largo. Ya fue encontrada y está con su familia.	\\xffd8ffe000104a46494600010100000100010000ffdb0043000a07070807060a0808080b0a0a0b0e18100e0d0d0e1d15161118231f2524221f2221262b372f26293429212230413134393b3e3e3e252e4449433c48373d3e3bffdb0043010a0b0b0e0d0e1c10101c3b2822283b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3bffc00011080140014003012200021101031101ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc4001f0100030101010101010101010000000000000102030405060708090a0bffc400b51100020102040403040705040400010277000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c03010002110311003f00f19a28ae96d3cb83c1704eb369b04d25edd2b1bab312c92858e02155bcb6c60b3752396a00e6a8aec6e63886b3aae91f61b54d3ecade5920985ba07011774521931b9b79da39241f3381d31289c4da55ace6c34f79d74692ed516c215f325175247b8ed519db182d8e9f2720f3401c4d15d769b041a86abe14babbb3b7596f352114d12c0a91cd12c9185628005e4b3a9c0c1d9eb9a9fc38b0ea96cd7d7f6d6114d09b858656b3458d80b499c96455c36c658dbee93f377e28038aa2ba5d1bcbbaf15379d369b70a96574c254b30b002b6f232b18fcb19da403f70f4ef4ba3d9b6a1e2fd36694595ed9aea16b0cef6f6e2385b7b67694d8b9c856cfcbdbe9401ccd15d2dff00976fe15d27cb9b4d85a7b2769227b30d3ca7ed132ee1279671c281f7c7ddaea353d234c8bc45e20bc4d3ed96da5b5bcb7b78044a1219638e7cb28c6011f67078e9e60a00f32a2bd0ad23d246bba3e9f731e9d30b85d2c456b1d98122bb081a4691f600c194c991b9b25c71c71cb69016df46d4b518e0867ba81e1441344b2ac71b6fdcfb581079545c9071bfd714018d456deb3690492d8cced6f6135cd889e74d8ca81f730185453b772856c600f9bb0c55ef0d4105c58c36a6da15babbba78e292ead44915cfcaa3cadff7a2604e72bfdf19230280396a2bb0bb8613abeafa39b1b64d3eceda6782658144802266290c98dc779da39241f3381d31a3a859e9f3789b5eb595349b8b7b469cc30c36cd00b4c4e8a0bb22a160aa482033743d4e2803cfa8aef8e89a5abde5b7d9adace4d49238acede50ef22c82dd5f08c4360b4af18c961c6e038e2b9f8f4eb4b8f08d8cf2de59d94a6fee50bcd1c85a4511c040ca2370093d7fbc71d4d0060d15dd6bf0db5843a8fd99b4ab3c6b9a844167b11233a2795b510f96db40dc7032a3e6fcafe9d63612ea7a75bcb0e9b7116dd27fd192d15658da4f20bbc8db06f5605c11b9b264191e801e6d4577d6f0dab68d3ddb4ba3bdc2d94ae2f8580f217fd22d94298fcacef019f9d9d241cfa33458ad67b2b279db499bcfd4ee5265fb080d788b1c042447cb1b0f2c0729cbe680384a2ba9d4b4db34f09c5144d6c6fec922b8b8548d84bb25ce4bb15c1037400004e096e9935cb500145145001451450014514500145145001451450014514500145145001451450014f334ad02c064731231758cb1daac400481ea42ae7e83d2bd13fe15de91ff003f37bff7da7ff1347fc2bbd23fe7e6f7fefb4ffe26a39d19fb589c149aa6a12d92d8c97f72f6a98db034cc635c74c2e7151c77b771490491dd4c8f6c310b2c84188649c29edcb13c7727d6bd07fe15de91ff003f37bff7da7ff1347fc2bbd23fe7e6f7fefb4ffe268e741ed6270326a57f35ea5f4b7d7125d46559276958c8a47421b3918ed5236b7ab3ddc776daa5e35cc4a56398dc39740410406ce40209fcebbaff008577a47fcfcdeffdf69ffc4d1ff0aef48ff9f9bdff00bed3ff0089a39d07b589c21d635437cb7c752bb3768a556e3cf6f3002082036738c123f134a75bd59a69266d52f0cb2c7e5bb9b87dce9fdd273c8f6aeebfe15de91ff3f37bff007da7ff001347fc2bbd23fe7e6f7fefb4ff00e268e741ed62708bac6a8963f615d4aed6d0295fb389d8478249236e7182493f8d35f54d4642c5efee5b7348e73331cb483121ebd5870c7b8eb5deff00c2bbd23fe7e6f7fefb4ffe268ff8577a47fcfcdeff00df69ff00c4d1ce83dac4f3e179742e63ba173309e1d9e5ca1cef4d8004c1ea300003d302acb6bdacb5c25cb6af7c668c15490dcbee507a8073900d771ff0aef48ff9f9bdff00bed3ff0089a3fe15de91ff003f37bff7da7ff13473a0f6b13cee79e6ba9de7b899e695ce5e4918b331f524f5a96df51beb386582d6f6e208a618912395955fb7201e6bbfff008577a47fcfcdeffdf69ffc4d1ff0aef48ff9f9bdff00bed3ff0089a39d07b589c149aa6a12d92d8c97f72f6a98db034cc635c74c2e71443aaea36f7535dc3a85d4571719f3a649983c993b8ee20e4e48079ee2bbdff8577a47fcfcdeff00df69ff00c4d1ff000aef48ff009f9bdffbed3ff89a39d07b589c14faaea375731dcdc6a17534f0906396499999318c6093918c0fcaa069e678961795da35767542c480cd80c40f53b5727d87a57a27fc2bbd23fe7e6f7fefb4ff00e268ff008577a47fcfcdeffdf69ffc4d1ce83dac4e1e3d7b58896558f56be41348d2ca16e1c6f76fbcc79e49c0c93d6a08f52bf867f3e2bdb84942a2f98b2b06c26dd8339e8bb171e9b463a0aeff00fe15de91ff003f37bff7da7ff1347fc2bbd23fe7e6f7fefb4ffe268e741ed6270569aaea560bb6cb50bab61f3710ccc9f7b6e7a1efb173fee8f4143ea9a849324f25fdcbcb1cbe6a3b4cc595f8f981cf0df2af3d7e51e95deffc2bbd23fe7e6f7fefb4ff00e268ff008577a47fcfcdeffdf69ffc4d1ce83dac4f3d6bbb96795dae252d3aed958b9cc8320e1bd46403cfa0a8abd1ff00e15de91ff3f37bff007da7ff001347fc2bbd23fe7e6f7fefb4ff00e268e741ed6279c515e8ff00f0aef48ff9f9bdff00bed3ff0089a3fe15de91ff003f37bff7da7ff13473a0f6b13ce28af47ff8577a47fcfcdeff00df69ff00c4d1ff000aef48ff009f9bdffbed3ff89a39d07b589e71457a3ffc2bbd23fe7e6f7fefb4ff00e268ff008577a47fcfcdeffdf69ffc4d1ce83dac4f38a2bd1ffe15de91ff003f37bff7da7ff1347fc2bbd23fe7e6f7fefb4ffe268e741ed6279c515e8fff000aef48ff009f9bdffbed3ff89a3fe15de91ff3f37bff007da7ff0013473a0f6b13ce28af47ff008577a47fcfcdeffdf69ffc4d1ff0aef48ff9f9bdff00bed3ff0089a39d07b589e71457a3ff00c2bbd23fe7e6f7fefb4ffe268ff8577a47fcfcdeff00df69ff00c4d1ce83dac4f38a2bd1ff00e15de91ff3f37bff007da7ff001347fc2bbd23fe7e6f7fefb4ff00e268e741ed62757451456072851451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140051453e28659e411c31bc8edd1514927f0140c6515b76be12d56e537b2476e3008f35b04e7d8648fc715a09e06628a5f500ad8f98087201fae79aa516ca5093e87294575bff082ff00d44bff00207ff6559f3f83b558903279339ce36c6f823dfe60051c9207092e86151524f6f3db384b88648588c85914a9c7af351d492145145020a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28aec3c2ba0208e3d4ee9773b7cd0c647ddf463efe9f9fd1a5765462e4ec67e8be159b5044b9bb630db302540fbede8791803fc3df35d8d9e9f69a7c663b4812207a91d4fd49e4f53d6acd15ba8a475460a2145145514145145004373696f7b0986e614950f661d3b647a1e7ad729acf841a20d71a6e5d0025a163961cff0faf1d8f3c77cd763454b8a64ca2a5b9e4b45777e24d0135085ef2dd76dd46b9200cf9a076e3bfa7e5f4e12b0946cce6945c58514514880a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a280367c31a48d4f51df28fdc5be1dc601dc73c29cf6383f97bd7a0d66787ec069fa3c319044920f324c820ee23a63b60607e15a75d1156475c236414514551614514500145145001451450015c4f8c34916d723508861276c48300057c7f5c13f507d6bb6aada859a6a16135a4870255c03e87a83f81c1a992ba2671e6563cba8a57468dd91d4ab29c3291820fa525739c6145145001451450014514500145145001451450014514500145145001451450014514500145145001451450014514500156b4cb7175aa5b40d19915e550ea33cae79e9ed9aab5ade16ff918ed7fe07ffa03535b951d5a3d128a28ae93b028a28a0028a28a0028a28a0028a28a0028a28a00f3af135b8b7d7ee42c6515c8719cfcd900923f1cd655745e36ff0090c45ff5eebffa13573b5cd2dce39ab498514514890a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800ad4f0dca90f882d1a46c02c541c772a40fd48acba92de76b6b98ae1002d1387507a641cd0b4634ecee7ab514c86549e149a36dc92286538c641e453eba8ed0a28a2800a28a2800a28a2800a28a2800a28a280384f194a926b6aa8d93142aae31d0e49fe4456055dd62f05fead7372a41577c21008ca8e01e7d80aa55cd277671c9ddb614514522428a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00ee3c1fa9fdaac0d948d996dfeee4f250f4efdba7b0c57455e5fa75fcda6dec773093f29f9941c6f5eea7eb5e9365790dfd9c77501263906464608ec47e75bc257563a69caeac4f4514559a8514514005145140051451400564789353fecdd29f636279be48f0791eadd73c0efea456a4d2a410bcd236d48d4b31c6700726bce75bd59f57bf6972eb0af1146c7ee8ff0013d7f4ed51395919d495919d45145607285145140051451400514514005145140051451400514514005145140051451400514514005145140051451400514514005145140056ae85aecda3cf83992d9cfef23f4ff687bff3fc88caa284ec34da7747a8d85fdbea56ab736cfb91b820f553e847ad59af2cb3bdb9b09c4f6b298a4c1191ce47a107835d5e9be34865c26a31792dff003d2304af7ea3a8edebf856d19a7b9d11a89ee75145416b7b6b7a9bed6e23946013b5b2573d323a8fc6a7ad0d428a2a29ee20b640f713470a9380d230519f4e68025a8ae2e21b581e79e411c6832cc7b560ea1e32b38536d8a9b9908e1882aabd7d793db8fd6b93d4754bbd526125d49bb6e7628185507b01fe4f02a1cd2d8ce5512d8d1d7fc46faae20b70f15a8c121bef39f7c761e9f8fd30e8a2b06dbdce66db776145145020a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a2ac59e9f77a84863b481e523a91d07d49e0743d6ba3b3f0436435f5d803272908ce4638f98f4e7da9a8b7b14a2dec729457a045e13d1e38c235bbca47f1bc8d93f9103f4a7ffc22da2ffcf97fe457ff001aaf66cbf6523cf28af43ff845b45ff9f2ff00c8affe347fc22da2ff00cf97fe457ff1a3d9b0f6523cf2ad26a7a8468a897d72aaa30aa266000f4eb5dcff00c22da2ff00cf97fe457ff1a3fe116d17fe7cbff22bff008d3f66c7eca470ff00dada97fd042ebfeff37f8d54af43ff00845b45ff009f2ffc8aff00e347fc22da2ffcf97fe457ff001a3d9c83d948f3ca2bd0ff00e116d17fe7cbff0022bff8d1ff0008b68bff003e5ff915ff00c697b362f6523cf28af43ff845b45ff9f2ff00c8affe348fe14d1991945a9424603095b23df938a3d9b0f6523cf68aebaf3c10b82d637641c0c24c33939e7e61d38f6ae7b50d22f74c7c5d425573859072add7bfe1d0f352e2d12e0d6e52a28a29101451450014514500145145001451450014514500145145001451450014514500145145001451450015b7a1786e6d5879f2b986d81c06c73273c81fe3ebebcd52d1f4c7d57514b75e107cd21ce30808ce3df9af47b7b786d6048208c471a0c2a8ed5708df566b4e17d5896d696f650886da148907651d7b64fa9e3ad4d4515b9d214514500145145001451450014514500145145001451450014c9618a78cc7346922375575041fc0d3e8a00e235ef0b358a3ddd913240092d1e3e68c7ae7b8fe5efc9ae72bd61d164464750cac30ca46411e95e7be22d1ff00b26fff0076316d364c5f3648c6323f0cfe58f7ac671b6a8e7a90b6a8c9a28a2b3310a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803b9f06d9883496b9206eb8727209fbabc007f1ddf9d74350da41f65b382df76ef2a354dd8c670319a9aba52b2b1db156560a28a298c28a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a002b2bc4b662f3439c606e8479aa49231b7afe991f8d6ad149aba1357563c968a9aee0fb2de4f6fbb77952326ec633838cd435cc7185145140828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f5aa28a2ba8ee0a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803cc356ff0090c5effd7c49ff00a11aa956f56ff90c5eff00d7c49ffa11aa95caf7389ee145145020a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803d6a8a28aea3b828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f30d5bfe4317bff005f127fe846aa55bd5bfe4317bff5f127fe846aa572bdce27b85145140828a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a00f5aa28a2ba8ee0a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803cc356ff90c5eff00d7c49ffa11aa956f56ff0090c5effd7c49ff00a11aa95caf7389ee145145020a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803d6a8aada7dcfdb74eb7b9ca132c619b6740d8e47e0722acd751dc145145001451450014514500145145001451450014514500145145001451450014514d7758d19dd82aa8cb3138007ad007996adff218bdff00af893ff423552a4b89dae6e65b870034ae5d80e9927351d72b389ee145145020a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803b5f05df896c24b277f9e16dc80e07c87d3b9e739fa8ae96bcbf4ebf9b4dbd8ee6127e53f32838debdd4fd6bd26caf21bfb38eea024c720c8c8c11d88fceb684aeac74d395d589e8a28ad0d428a28a0028a28a0028a28a0028a28a0028a28a0028a28a0028a28a002b17c557e2cf469230f896e3f76a063a7f1707b638fc456bcd2a410bcd236d48d4b31c6700726bce75bd59f57bf6972eb0af1146c7ee8ff0013d7f4ed51395919d495919d4514560728514514005145140051451400514514005145140051451400514514005145140051451400569691aedd68eec22c490b905e26e9f51e871c7f8e2b368a13b0d36b63d3b4ed52d35484c96b26edb8dea461949ec47f91c1ab95e5114d2c12092191e375e8c8c411f88addb3f196a30102e563b95c927236374e808e3f4ad5545d4de355753baa2b9a8bc6f6263066b5b847eea9b580fc491fca9fff0009b69bff003c2ebfef85ff00e2aaf9917cf1ee7454573bff0009b69bff003c2ebfef85ff00e2a8ff0084db4dff009e175ff7c2ff00f1547320e78f73a2a2b9dff84db4dff9e175ff007c2fff001547fc26da6ffcf0baff00be17ff008aa399073c7b9d1515ceff00c26da6ff00cf0baffbe17ff8aa3fe136d37fe785d7fdf0bffc551cc839e3dce8a8ae77fe136d37fe785d7fdf0bff00c551ff0009b69bff003c2ebfef85ff00e2a8e641cf1ee7454573bff09b69bff3c2ebfef85ffe2a91fc6da7846296f72cd8f9410a013f5cf147320e78f73a3a82f2f6dac2033dd4a228f2064f393e800e4d71f79e34bd9815b5863b6040f98fcec0e7b678fd2b0ae6eee2f66335cccf2b9eec7a77c0f41cf4a97517421d55d0d3d6fc4771aaee8107956a1b2147de7f4ddfcf1fcf19ac6a28ac5b6f7306db776145145020a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2800a28a2803ffd9	image/jpeg	encontrado	t	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	3055556677	2
\.


--
-- Data for Name: rutas_guardadas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rutas_guardadas (id, usuario_id, nombre, origen_lat, origen_lon, origen_texto, destino_lat, destino_lon, destino_texto, incluye_demo, distancia_m, tiempo_min, metros_riesgo, geometria, creada_en, modo) FROM stdin;
\.


--
-- Data for Name: solicitudes_ayuda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.solicitudes_ayuda (id, usuario_id, categoria, urgencia, descripcion, personas_afectadas, direccion, latitud, longitud, nombre_contacto, telefono_contacto, adjunto, adjunto_mime, autoriza_compartir, estado, creada_en, actualizada_en, tipo, alcance, nombre_comunidad, motivo_visita, fecha_visita_preferida, franja_horaria) FROM stdin;
1	2	alimentos	alta	El agua entró a la casa y perdimos los alimentos. Somos cuatro personas, dos de ellas niños.	4	Calle 30 # 5-20, Barrio La Granja	8.753	-75.879	Usuario Demo	3007654321	\N	\N	t	en_atencion	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	ayuda	hogar	\N	\N	\N	\N
2	2	atencion_medica	media	Varias familias del barrio presentan fiebre y diarrea después de la inundación. Solicitamos brigada médica.	35	Barrio El Dorado, margen izquierda	8.747	-75.886	Usuario Demo	3007654321	\N	\N	t	pendiente	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	ayuda	comunidad	Barrio El Dorado	\N	\N	\N
3	3	\N	alta	Aparecieron grietas en una pared de la casa después de las lluvias. Solicitamos revisión del riesgo.	5	Carrera 2 # 41-15, Barrio Montería Moderno	\N	\N	Laura Martínez	3011112233	\N	\N	t	programada	2026-10-15 23:29:30.986653-05	2026-10-15 23:29:30.986653-05	visita	hogar	\N	riesgo_estructural	2026-11-20	manana
\.


--
-- Data for Name: suscripciones_push; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.suscripciones_push (id, usuario_id, endpoint, p256dh, auth, creada_en) FROM stdin;
\.


--
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuarios (id, email, password_hash, rol, creado_en, nombre, telefono, tipo_documento, numero_documento, fecha_nacimiento, tipo_sangre, alergias, condiciones_medicas, medicamentos, contacto_emergencia_nombre, contacto_emergencia_telefono, direccion, comunidad, email_verificado) FROM stdin;
1	admin.demo@sigre.co	scrypt:32768:8:1$5PRalFZEddt01aVB$eecdfaf19ef3631f63147ec859b0a342af15d3dc54841339cf8a6cff35b9f72540e131e5a29ad0dd6aaf740b19f2f0843af2ca236d54487d5d2a7dbb789fc4d0	autoridad	2026-09-01 08:00:00-05	Administrador Demo	3001234567	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t
3	laura.martinez@sigre.co	scrypt:32768:8:1$HLxKrBeZbIp5uI5A$f67f7727431cb5d40e2f60f33c86631a254559e11654856761e828c5ab9da44e3a8aac33ada083e2a1e2d6e515983c0f7cfa78c7192d7b3cbfa210cc05f9bc58	ciudadano	2026-09-01 08:00:00-05	Laura Martínez	3011112233	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t
4	carlos.perez@sigre.co	scrypt:32768:8:1$hTW9NjQSumkSdESY$b70a8c28794289fbf1a7220e0fd5fcb5cd85f1e1e842a139372023b924a875dbfd5d03f67bd26f13629dbf727a33b7b49fcaf50e740f2b7fce1224fed274e347	voluntario	2026-09-01 08:00:00-05	Carlos Pérez	3022223344	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t
5	ana.gomez@sigre.co	scrypt:32768:8:1$kz5X9R1XSiYnCB9A$8c4b7f4257587d2049280e4d1059e722f1f7af2f061c4bc9e4e380626c19873a07a9049b3e1cf8f11e4ce49eab9cecb0ab3d729cbd9a54c7840ec28e26939ae7	ciudadano	2026-09-01 08:00:00-05	Ana Gómez	3033334455	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t
2	usuario.demo@sigre.co	scrypt:32768:8:1$5QEKFixUMtD6UWts$e6e55f1f64df3d6273bb4a72f90f6de82a247a2fa57f893a86da1032155ec14a2a10a991c8d4e991980b4a70926c2edbd0a7299a18a521bf90db811ddab392e0	ciudadano	2026-09-01 08:00:00-05	Usuario Demo	3007654321	CC	1000000001	1998-05-14	O+	Ninguna conocida	\N	\N	María Demo	3009998877	Calle 30 # 5-20	Barrio La Granja	t
\.


--
-- Name: centros_ayuda_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.centros_ayuda_id_seq', 3, true);


--
-- Name: comentarios_desaparecidos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.comentarios_desaparecidos_id_seq', 1, true);


--
-- Name: directorio_entidades_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.directorio_entidades_id_seq', 9, true);


--
-- Name: emergencias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.emergencias_id_seq', 1, true);


--
-- Name: inventario_centros_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_centros_id_seq', 11, true);


--
-- Name: jornadas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.jornadas_id_seq', 3, true);


--
-- Name: notificaciones_comentarios_desaparecidos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notificaciones_comentarios_desaparecidos_id_seq', 1, true);


--
-- Name: notificaciones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notificaciones_id_seq', 14, true);


--
-- Name: recuperacion_contrasenas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recuperacion_contrasenas_id_seq', 1, false);


--
-- Name: reportes_desaparecidos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reportes_desaparecidos_id_seq', 3, true);


--
-- Name: rutas_guardadas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.rutas_guardadas_id_seq', 1, false);


--
-- Name: solicitudes_ayuda_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.solicitudes_ayuda_id_seq', 3, true);


--
-- Name: suscripciones_push_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.suscripciones_push_id_seq', 1, false);


--
-- Name: usuarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuarios_id_seq', 5, true);


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

\unrestrict lzxAvNwDQXMMTahR0DngEaRpMCbxqrxSvUzpP4HPciy2mf03ZaEVGvqmHxJLLlY

