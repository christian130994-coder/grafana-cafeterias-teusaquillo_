-- =====================================================================
-- 01_ddl.sql
-- Tabla cafeterias_teusaquillo: tipos, restricciones e índices.
-- Origen: Actividad 3 (trabajo en equipo de Antonia Gacharná Echeverri,
-- Efren Alexander Granados Latorre y Christian Fabián Jaimes Toscano),
-- repositorio github.com/alexandergl55-design/actividad3-cafeterias-rds
-- (versión publicada en github.com/Antoniaga/actividad4-lambda-cafeterias-rds).
-- Se reutiliza sin cambios para que el dashboard lea el mismo modelo.
-- =====================================================================

CREATE TABLE IF NOT EXISTS cafeterias_teusaquillo (
    fsq_place_id VARCHAR(40) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    distance_m INTEGER CHECK (distance_m >= 0),
    primary_category VARCHAR(100),
    primary_category_id VARCHAR(40),
    categories JSONB,
    category_ids JSONB,
    address TEXT,
    localidad VARCHAR(100),
    fecha_carga TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_cafeterias_categoria
ON cafeterias_teusaquillo (primary_category);

CREATE INDEX IF NOT EXISTS idx_cafeterias_localidad
ON cafeterias_teusaquillo (localidad);

CREATE INDEX IF NOT EXISTS idx_cafeterias_categories_gin
ON cafeterias_teusaquillo USING GIN (categories);

CREATE INDEX IF NOT EXISTS idx_cafeterias_coords
ON cafeterias_teusaquillo (latitude, longitude);
