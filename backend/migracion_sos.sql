-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · SOS en vivo
-- Cada emergencia entra en una cola (en_espera). Un operador (rol autoridad)
-- la toma (en_curso), atiende por videollamada y la cierra (finalizada).
-- El ciudadano también puede cancelarla mientras espera (cancelada).
-- Durante la sesión se guarda la ubicación GPS del ciudadano cada pocos segundos.
--
-- Ejecútala con postgres. Se puede ejecutar varias veces sin duplicar objetos.

CREATE TABLE IF NOT EXISTS sesiones_sos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ciudadano_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    operador_id BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    estado TEXT NOT NULL DEFAULT 'en_espera'
        CHECK (estado IN ('en_espera', 'en_curso', 'finalizada', 'cancelada')),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atendida_en TIMESTAMPTZ,
    finalizada_en TIMESTAMPTZ,
    motivo_cierre TEXT CHECK (motivo_cierre IS NULL OR char_length(motivo_cierre) <= 300),
    CONSTRAINT sesiones_sos_atencion_valida CHECK (
        atendida_en IS NULL OR atendida_en >= creada_en
    ),
    CONSTRAINT sesiones_sos_cierre_valido CHECK (
        finalizada_en IS NULL OR finalizada_en >= creada_en
    ),
    CONSTRAINT sesiones_sos_estado_coherente CHECK (
        (estado = 'en_espera' AND atendida_en IS NULL AND finalizada_en IS NULL)
        OR (estado = 'en_curso' AND atendida_en IS NOT NULL AND finalizada_en IS NULL)
        OR (estado IN ('finalizada', 'cancelada') AND finalizada_en IS NOT NULL)
    )
);

-- La cola: emergencias en espera, de la más antigua a la más reciente.
CREATE INDEX IF NOT EXISTS idx_sesiones_sos_cola
    ON sesiones_sos (creada_en, id) WHERE estado = 'en_espera';

-- Una persona no puede tener dos emergencias abiertas al mismo tiempo.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sesiones_sos_una_abierta
    ON sesiones_sos (ciudadano_id) WHERE estado IN ('en_espera', 'en_curso');

CREATE INDEX IF NOT EXISTS idx_sesiones_sos_operador ON sesiones_sos (operador_id);

CREATE TABLE IF NOT EXISTS ubicaciones_sos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sesion_id BIGINT NOT NULL REFERENCES sesiones_sos(id) ON DELETE CASCADE,
    latitud DOUBLE PRECISION NOT NULL CHECK (latitud BETWEEN -90 AND 90),
    longitud DOUBLE PRECISION NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    precision_m DOUBLE PRECISION CHECK (precision_m IS NULL OR precision_m BETWEEN 0 AND 100000),
    registrada_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ubicaciones_sos_sesion
    ON ubicaciones_sos (sesion_id, registrada_en);

ALTER TABLE sesiones_sos ENABLE ROW LEVEL SECURITY;
ALTER TABLE sesiones_sos FORCE ROW LEVEL SECURITY;
ALTER TABLE ubicaciones_sos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ubicaciones_sos FORCE ROW LEVEL SECURITY;

-- El ciudadano ve sus emergencias; las autoridades ven todas (cola y reportes).
DROP POLICY IF EXISTS sesiones_sos_ver ON sesiones_sos;
CREATE POLICY sesiones_sos_ver ON sesiones_sos
    FOR SELECT
    USING (
        ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
        OR sigre_usuario_es_autoridad()
    );

-- Solo se crea a nombre propio, en espera y sin operador.
DROP POLICY IF EXISTS sesiones_sos_crear ON sesiones_sos;
CREATE POLICY sesiones_sos_crear ON sesiones_sos
    FOR INSERT
    WITH CHECK (
        ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
        AND estado = 'en_espera'
        AND operador_id IS NULL
    );

-- El ciudadano actualiza la suya (cancelar o finalizar). Una autoridad toma
-- una emergencia sin operador o actualiza la que ya es suya.
DROP POLICY IF EXISTS sesiones_sos_actualizar ON sesiones_sos;
CREATE POLICY sesiones_sos_actualizar ON sesiones_sos
    FOR UPDATE
    USING (
        ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
        OR (sigre_usuario_es_autoridad()
            AND (operador_id IS NULL
                 OR operador_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT))
    )
    WITH CHECK (
        ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
        OR (sigre_usuario_es_autoridad()
            AND operador_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT)
    );

-- La ubicación la ven el ciudadano dueño y las autoridades.
DROP POLICY IF EXISTS ubicaciones_sos_ver ON ubicaciones_sos;
CREATE POLICY ubicaciones_sos_ver ON ubicaciones_sos
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM sesiones_sos s
            WHERE s.id = ubicaciones_sos.sesion_id
              AND (s.ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
                   OR sigre_usuario_es_autoridad())
        )
    );

-- Solo el ciudadano envía su ubicación, y solo mientras la emergencia está abierta.
DROP POLICY IF EXISTS ubicaciones_sos_crear ON ubicaciones_sos;
CREATE POLICY ubicaciones_sos_crear ON ubicaciones_sos
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM sesiones_sos s
            WHERE s.id = ubicaciones_sos.sesion_id
              AND s.ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
              AND s.estado IN ('en_espera', 'en_curso')
        )
    );

-- Posición en la cola de una emergencia propia. El ciudadano no puede ver las
-- emergencias de los demás (seguridad por filas), así que se cuenta aquí.
-- Devuelve NULL si la emergencia no es suya o ya no está en espera.
CREATE OR REPLACE FUNCTION sigre_posicion_cola_sos(p_sesion BIGINT)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT (
        SELECT COUNT(*)::INTEGER FROM sesiones_sos otra
        WHERE otra.estado = 'en_espera'
          AND (otra.creada_en, otra.id) <= (propia.creada_en, propia.id)
    )
    FROM sesiones_sos propia
    WHERE propia.id = p_sesion
      AND propia.estado = 'en_espera'
      AND propia.ciudadano_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT;
$$;

-- Nombre y teléfono del ciudadano para el operador que atiende la emergencia
-- (si se cae la videollamada, lo puede llamar). Nadie más los obtiene.
CREATE OR REPLACE FUNCTION sigre_contacto_sos(p_sesion BIGINT)
RETURNS TABLE (nombre TEXT, telefono TEXT, contacto_emergencia_nombre TEXT,
               contacto_emergencia_telefono TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.nombre, u.telefono, u.contacto_emergencia_nombre, u.contacto_emergencia_telefono
    FROM sesiones_sos s
    JOIN usuarios u ON u.id = s.ciudadano_id
    WHERE s.id = p_sesion
      AND s.operador_id = NULLIF(current_setting('app.user_id', true), '')::BIGINT
      AND sigre_usuario_es_autoridad();
$$;

REVOKE ALL ON FUNCTION sigre_posicion_cola_sos(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION sigre_contacto_sos(BIGINT) FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT, UPDATE ON sesiones_sos TO sigre_app;
        GRANT SELECT, INSERT ON ubicaciones_sos TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_posicion_cola_sos(BIGINT) TO sigre_app;
        GRANT EXECUTE ON FUNCTION sigre_contacto_sos(BIGINT) TO sigre_app;
    END IF;
END
$$;
