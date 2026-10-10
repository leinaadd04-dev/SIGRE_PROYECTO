-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- Comentarios de testigos y avisos privados para quien publicó cada reporte.
-- Se puede volver a ejecutar sin duplicar columnas, tablas ni políticas.

ALTER TABLE reportes_desaparecidos
    ADD COLUMN IF NOT EXISTS publicado_por BIGINT
    REFERENCES usuarios(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_reportes_desaparecidos_publicador
    ON reportes_desaparecidos (publicado_por);

CREATE TABLE IF NOT EXISTS comentarios_desaparecidos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reporte_id BIGINT NOT NULL REFERENCES reportes_desaparecidos(id) ON DELETE CASCADE,
    usuario_id BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    nombre_testigo TEXT NOT NULL CHECK (char_length(nombre_testigo) BETWEEN 2 AND 120),
    comentario TEXT NOT NULL CHECK (char_length(comentario) BETWEEN 5 AND 800),
    veracidad_confirmada BOOLEAN NOT NULL CHECK (veracidad_confirmada = TRUE),
    autoriza_compartir_telefono BOOLEAN NOT NULL DEFAULT TRUE
        CHECK (autoriza_compartir_telefono = TRUE),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE comentarios_desaparecidos
    ADD COLUMN IF NOT EXISTS autoriza_compartir_telefono BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_comentarios_desaparecidos_reporte_fecha
    ON comentarios_desaparecidos (reporte_id, creado_en DESC);

-- El teléfono queda en una tabla privada para no exponerlo al público.
CREATE TABLE IF NOT EXISTS contactos_comentarios_desaparecidos (
    comentario_id BIGINT PRIMARY KEY
        REFERENCES comentarios_desaparecidos(id) ON DELETE CASCADE,
    telefono_testigo TEXT NOT NULL
        CHECK (char_length(telefono_testigo) BETWEEN 7 AND 20)
);

CREATE TABLE IF NOT EXISTS notificaciones_comentarios_desaparecidos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    destinatario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    comentario_id BIGINT NOT NULL UNIQUE
        REFERENCES comentarios_desaparecidos(id) ON DELETE CASCADE,
    leida BOOLEAN NOT NULL DEFAULT FALSE,
    creada_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notificaciones_comentarios_destinatario
    ON notificaciones_comentarios_desaparecidos (destinatario_id, leida, creada_en DESC);

ALTER TABLE comentarios_desaparecidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE comentarios_desaparecidos FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS comentarios_desaparecidos_publicos ON comentarios_desaparecidos;
CREATE POLICY comentarios_desaparecidos_publicos ON comentarios_desaparecidos
    FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS comentarios_desaparecidos_crear ON comentarios_desaparecidos;
CREATE POLICY comentarios_desaparecidos_crear ON comentarios_desaparecidos
    FOR INSERT WITH CHECK (
        usuario_id = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
    );

ALTER TABLE contactos_comentarios_desaparecidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE contactos_comentarios_desaparecidos FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS contactos_comentarios_privados ON contactos_comentarios_desaparecidos;
CREATE POLICY contactos_comentarios_privados ON contactos_comentarios_desaparecidos
    FOR SELECT USING (
        EXISTS (
            SELECT 1
            FROM comentarios_desaparecidos c
            WHERE c.id = comentario_id
              AND (
                  c.usuario_id = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
                  OR EXISTS (
                      SELECT 1
                      FROM reportes_desaparecidos r
                      WHERE r.id = c.reporte_id
                        AND r.publicado_por = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
                  )
              )
        )
    );
DROP POLICY IF EXISTS contactos_comentarios_crear ON contactos_comentarios_desaparecidos;
CREATE POLICY contactos_comentarios_crear ON contactos_comentarios_desaparecidos
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM comentarios_desaparecidos c
            WHERE c.id = comentario_id
              AND c.usuario_id = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
        )
    );

ALTER TABLE notificaciones_comentarios_desaparecidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificaciones_comentarios_desaparecidos FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notificaciones_comentarios_ver ON notificaciones_comentarios_desaparecidos;
CREATE POLICY notificaciones_comentarios_ver ON notificaciones_comentarios_desaparecidos
    FOR SELECT USING (
        destinatario_id = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
    );
DROP POLICY IF EXISTS notificaciones_comentarios_crear ON notificaciones_comentarios_desaparecidos;
CREATE POLICY notificaciones_comentarios_crear ON notificaciones_comentarios_desaparecidos
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1
            FROM comentarios_desaparecidos c
            JOIN reportes_desaparecidos r ON r.id = c.reporte_id
            WHERE c.id = comentario_id
              AND r.publicado_por = destinatario_id
        )
    );
DROP POLICY IF EXISTS notificaciones_comentarios_actualizar ON notificaciones_comentarios_desaparecidos;
CREATE POLICY notificaciones_comentarios_actualizar ON notificaciones_comentarios_desaparecidos
    FOR UPDATE USING (
        destinatario_id = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
    ) WITH CHECK (
        destinatario_id = NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
    );

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT ON comentarios_desaparecidos TO sigre_app;
        GRANT SELECT, INSERT ON contactos_comentarios_desaparecidos TO sigre_app;
        GRANT SELECT, INSERT, UPDATE ON notificaciones_comentarios_desaparecidos TO sigre_app;
        GRANT USAGE, SELECT ON SEQUENCE comentarios_desaparecidos_id_seq TO sigre_app;
        GRANT USAGE, SELECT ON SEQUENCE notificaciones_comentarios_desaparecidos_id_seq TO sigre_app;
        GRANT INSERT (publicado_por) ON reportes_desaparecidos TO sigre_app;
        GRANT SELECT (publicado_por) ON reportes_desaparecidos TO sigre_app;
    END IF;
END
$$;
