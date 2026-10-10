-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Repara textos con tildes dañadas ("LÃ­nea" en lugar de "Línea").
-- Pasa cuando psql en Windows lee un archivo UTF-8 con otra codificación.
-- Solo cambia los textos que tienen ese daño. Ejecútala con postgres. Se puede repetir.

CREATE OR REPLACE FUNCTION pg_temp.reparar(p TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    IF p IS NULL OR p !~ '[ÃÂ]' THEN
        RETURN p;
    END IF;
    RETURN convert_from(convert_to(p, 'WIN1252'), 'UTF8');
EXCEPTION WHEN OTHERS THEN
    RETURN p;
END;
$$;

UPDATE directorio_entidades
SET nombre = pg_temp.reparar(nombre), detalle = pg_temp.reparar(detalle),
    direccion = pg_temp.reparar(direccion)
WHERE concat(nombre, detalle, direccion) ~ '[ÃÂ]';

UPDATE centros_ayuda
SET nombre = pg_temp.reparar(nombre), direccion = pg_temp.reparar(direccion),
    descripcion = pg_temp.reparar(descripcion), necesidades = pg_temp.reparar(necesidades)
WHERE concat(nombre, direccion, descripcion, necesidades) ~ '[ÃÂ]';

UPDATE jornadas
SET nombre = pg_temp.reparar(nombre), descripcion = pg_temp.reparar(descripcion),
    lugar = pg_temp.reparar(lugar)
WHERE concat(nombre, descripcion, lugar) ~ '[ÃÂ]';

UPDATE emergencias
SET tipo = pg_temp.reparar(tipo), descripcion = pg_temp.reparar(descripcion)
WHERE concat(tipo, descripcion) ~ '[ÃÂ]';

DO $$
BEGIN
    IF to_regclass('notificaciones') IS NOT NULL THEN
        UPDATE notificaciones
        SET titulo = pg_temp.reparar(titulo), mensaje = pg_temp.reparar(mensaje)
        WHERE concat(titulo, mensaje) ~ '[ÃÂ]';
    END IF;
END
$$;
