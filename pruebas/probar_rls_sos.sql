-- SIGRE · Prueba 6: consulta directa a la base como ciudadano.
-- Comprueba que la seguridad por filas solo le deja ver sus propias sesiones SOS.
-- Se ejecuta con el usuario de la aplicación (sigre_app), NO con postgres
-- (postgres se salta la seguridad por filas).
--
-- Uso (ciudadano1.sos@sigre.test tiene el id 8):
--   psql -U sigre_app -d sigre -h localhost -v ciudadano=8 -f pruebas\probar_rls_sos.sql

BEGIN;

\echo '== 1. Sin decir quién es: no debe ver ninguna sesión'
SELECT count(*) AS sesiones_visibles FROM sesiones_sos;

\echo '== 2. Como el ciudadano' :ciudadano ': solo debe ver sus propias sesiones'
SELECT set_config('app.user_id', :'ciudadano', true) AS cuenta;
SELECT set_config('app.user_role', 'ciudadano', true) AS rol;
SELECT id, ciudadano_id, estado FROM sesiones_sos ORDER BY id;

\echo '== 3. Resumen: ninguna sesión ajena'
SELECT count(*) AS sesiones_visibles,
       count(*) FILTER (WHERE ciudadano_id <> :ciudadano) AS sesiones_ajenas
FROM sesiones_sos;

\echo '== 4. Ubicaciones: solo las de sus propias sesiones'
SELECT count(*) AS ubicaciones_visibles,
       count(*) FILTER (WHERE s.ciudadano_id <> :ciudadano) AS ubicaciones_ajenas
FROM ubicaciones_sos u
LEFT JOIN sesiones_sos s ON s.id = u.sesion_id;

ROLLBACK;
