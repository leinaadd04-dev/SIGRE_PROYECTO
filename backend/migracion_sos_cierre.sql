SET client_encoding = 'UTF8';

-- Reporte de cierre de SOS en vivo: resultado y nota del operador.
-- Solo agrega columnas opcionales; se puede ejecutar varias veces.
ALTER TABLE sesiones_sos
    ADD COLUMN IF NOT EXISTS resultado_cierre TEXT
        CHECK (resultado_cierre IS NULL
               OR resultado_cierre IN ('atendida', 'falsa_alarma', 'derivada', 'sin_respuesta')),
    ADD COLUMN IF NOT EXISTS nota_cierre TEXT
        CHECK (nota_cierre IS NULL OR char_length(nota_cierre) <= 500);

