-- =====================================================================
-- 02_carga.sql
-- Carga idempotente del CSV de cafeterías en la tabla de RDS.
-- Replica en SQL la misma transformación de la Lambda de la Actividad 4:
--   distance -> distance_m (entero), LocNombre -> localidad,
--   categories / category_ids (texto separado por comas) -> JSONB,
--   UPSERT por fsq_place_id (se puede ejecutar varias veces sin duplicar).
-- Basado en la Lambda de la Actividad 4 y el CSV de la Actividad 2, del
-- equipo Antonia Gacharná Echeverri, Efren Alexander Granados Latorre y
-- Christian Fabián Jaimes Toscano (github.com/Antoniaga).
-- Se ejecuta desde la raíz del repositorio con psql:
--   psql -f 02_carga.sql
-- =====================================================================

CREATE TEMP TABLE staging_cafeterias (
    fsq_place_id        TEXT,
    name                TEXT,
    latitude            TEXT,
    longitude           TEXT,
    distance            TEXT,
    primary_category    TEXT,
    primary_category_id TEXT,
    categories          TEXT,
    category_ids        TEXT,
    address             TEXT,
    locnombre           TEXT
);

\copy staging_cafeterias FROM 'cafeterias_teusaquillo_limpio.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

INSERT INTO cafeterias_teusaquillo (
    fsq_place_id, name, latitude, longitude, distance_m,
    primary_category, primary_category_id, categories, category_ids,
    address, localidad
)
SELECT
    fsq_place_id,
    name,
    latitude::DOUBLE PRECISION,
    longitude::DOUBLE PRECISION,
    NULLIF(TRIM(distance), '')::NUMERIC::INTEGER,
    primary_category,
    primary_category_id,
    COALESCE((SELECT jsonb_agg(TRIM(x)) FROM unnest(string_to_array(categories, ',')) AS x
              WHERE TRIM(x) <> ''), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(TRIM(x)) FROM unnest(string_to_array(category_ids, ',')) AS x
              WHERE TRIM(x) <> ''), '[]'::jsonb),
    NULLIF(TRIM(address), ''),
    locnombre
FROM staging_cafeterias
ON CONFLICT (fsq_place_id) DO UPDATE SET
    name                = EXCLUDED.name,
    latitude            = EXCLUDED.latitude,
    longitude           = EXCLUDED.longitude,
    distance_m          = EXCLUDED.distance_m,
    primary_category    = EXCLUDED.primary_category,
    primary_category_id = EXCLUDED.primary_category_id,
    categories          = EXCLUDED.categories,
    category_ids        = EXCLUDED.category_ids,
    address             = EXCLUDED.address,
    localidad           = EXCLUDED.localidad,
    fecha_carga         = CURRENT_TIMESTAMP;

-- Verificación: ambos conteos deben ser 46
SELECT COUNT(*) AS total_registros,
       COUNT(DISTINCT fsq_place_id) AS ids_unicos
FROM cafeterias_teusaquillo;
