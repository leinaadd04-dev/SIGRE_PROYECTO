-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Cuentas para probar SOS en vivo (SOLO en la base local, nunca en Neon).
-- Crea 3 ciudadanos y 2 autoridades con el correo verificado y cierra las
-- emergencias que hayan quedado abiertas de pruebas anteriores.
-- Contraseña de todas: PruebaSOS2026*
--
-- Ejecútala con postgres antes de cada corrida de pruebas/probar_cola_sos.py.

INSERT INTO usuarios (email, password_hash, rol, nombre, email_verificado)
SELECT correo,
       'scrypt:32768:8:1$SFPHYyBf3DeDf3vk$232944211c7c7863d671c561e9eb3b05cfd0d040cc977aa22a54fc80c7d68d15bdc5ff5b8fd4cb307f094e712a37e0feac5627db8373302ac7e441774edc7ca5',
       rol, nombre, TRUE
FROM (VALUES
    ('ciudadano1.sos@sigre.test', 'ciudadano', 'Ciudadano Prueba Uno'),
    ('ciudadano2.sos@sigre.test', 'ciudadano', 'Ciudadano Prueba Dos'),
    ('ciudadano3.sos@sigre.test', 'ciudadano', 'Ciudadano Prueba Tres'),
    ('operador1.sos@sigre.test', 'autoridad', 'Operador Prueba Uno'),
    ('operador2.sos@sigre.test', 'autoridad', 'Operador Prueba Dos')
) AS cuentas (correo, rol, nombre)
ON CONFLICT (email) DO UPDATE
    SET password_hash = EXCLUDED.password_hash,
        rol = EXCLUDED.rol,
        nombre = EXCLUDED.nombre,
        email_verificado = TRUE;

UPDATE sesiones_sos
SET estado = 'cancelada',
    finalizada_en = NOW(),
    motivo_cierre = 'Cerrada al reiniciar las pruebas'
WHERE estado IN ('en_espera', 'en_curso')
  AND ciudadano_id IN (SELECT id FROM usuarios WHERE email LIKE '%.sos@sigre.test');

SELECT id, email, rol FROM usuarios WHERE email LIKE '%.sos@sigre.test' ORDER BY id;
