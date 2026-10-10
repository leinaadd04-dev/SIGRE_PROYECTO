-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Estadísticas públicas del dashboard
-- La tabla usuarios tiene permisos restringidos, así que la aplicación no
-- puede contar todas las filas directamente. Esta función solo devuelve el
-- total (sin correos ni otros datos) y se ejecuta con los permisos de su dueño.
-- Ejecútala con el usuario dueño de la tabla usuarios (por ejemplo, postgres).
-- Se puede ejecutar varias veces.

CREATE OR REPLACE FUNCTION contar_usuarios_registrados()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT count(*) FROM public.usuarios;
$$;

REVOKE ALL ON FUNCTION contar_usuarios_registrados() FROM PUBLIC;

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en ambas líneas.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT EXECUTE ON FUNCTION contar_usuarios_registrados() TO sigre_app;
    END IF;
END
$$;
