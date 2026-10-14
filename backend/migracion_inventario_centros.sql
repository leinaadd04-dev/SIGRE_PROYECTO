-- Los archivos están en UTF-8: sin esto, psql en Windows daña las tildes.
SET client_encoding = 'UTF8';

-- SIGRE · Inventario de los centros de acopio y albergues
--
-- Cada fila es un producto de un centro: categoría, nombre, cantidad, unidad y
-- una cantidad mínima. Si la cantidad llega al mínimo, el producto se muestra
-- como "por agotarse"; en 0, como "agotado".
-- Todos pueden ver el inventario; solo las cuentas de autoridad lo editan.
--
-- Requiere migracion_administracion.sql (centros_ayuda y sigre_usuario_es_autoridad).
-- Ejecútala con el usuario dueño de las tablas (postgres). Se puede repetir.

CREATE TABLE IF NOT EXISTS inventario_centros (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    centro_id BIGINT NOT NULL REFERENCES centros_ayuda(id) ON DELETE CASCADE,
    categoria TEXT NOT NULL CHECK (categoria IN (
        'aseo', 'no_perecederos', 'perecederos', 'agua', 'mascotas',
        'descanso', 'ropa', 'botiquin', 'bebes', 'otros'
    )),
    producto TEXT NOT NULL CHECK (char_length(producto) BETWEEN 2 AND 120),
    cantidad INTEGER NOT NULL DEFAULT 0 CHECK (cantidad BETWEEN 0 AND 1000000),
    unidad TEXT NOT NULL DEFAULT 'unidades' CHECK (unidad IN (
        'unidades', 'kg', 'libras', 'litros', 'paquetes', 'cajas', 'bolsas', 'pares'
    )),
    minimo INTEGER NOT NULL DEFAULT 0 CHECK (minimo BETWEEN 0 AND 1000000),
    actualizado_por BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Talla de la ropa y el calzado (ej. "M", "10", "38"). Solo para la categoría ropa.
ALTER TABLE inventario_centros ADD COLUMN IF NOT EXISTS talla TEXT;
ALTER TABLE inventario_centros DROP CONSTRAINT IF EXISTS inventario_talla_valida;
ALTER TABLE inventario_centros ADD CONSTRAINT inventario_talla_valida CHECK (
    talla IS NULL OR (categoria = 'ropa' AND char_length(talla) BETWEEN 1 AND 20)
);

-- Un mismo producto no se repite en un centro ("Arroz" y "arroz" cuentan igual).
-- En ropa, cada talla es una fila distinta: "Zapatos niño" talla 28 y talla 30.
DROP INDEX IF EXISTS idx_inventario_centro_producto;
CREATE UNIQUE INDEX idx_inventario_centro_producto
    ON inventario_centros (centro_id, lower(producto), lower(coalesce(talla, '')));
CREATE INDEX IF NOT EXISTS idx_inventario_categoria
    ON inventario_centros (categoria);

ALTER TABLE inventario_centros ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario_centros FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventario_ver ON inventario_centros;
CREATE POLICY inventario_ver ON inventario_centros FOR SELECT USING (true);
DROP POLICY IF EXISTS inventario_crear ON inventario_centros;
CREATE POLICY inventario_crear ON inventario_centros FOR INSERT WITH CHECK (sigre_usuario_es_autoridad());
DROP POLICY IF EXISTS inventario_editar ON inventario_centros;
CREATE POLICY inventario_editar ON inventario_centros FOR UPDATE
    USING (sigre_usuario_es_autoridad()) WITH CHECK (sigre_usuario_es_autoridad());
DROP POLICY IF EXISTS inventario_eliminar ON inventario_centros;
CREATE POLICY inventario_eliminar ON inventario_centros FOR DELETE USING (sigre_usuario_es_autoridad());

-- Si tu DB_USER tiene otro nombre, cambia 'sigre_app' en este bloque.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigre_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON inventario_centros TO sigre_app;
    END IF;
END
$$;
