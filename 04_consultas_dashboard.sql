-- =====================================================================
-- 04_consultas_dashboard.sql
-- Consultas SQL de cada panel del dashboard "Cafeterías de Teusaquillo".
-- Fuente: tabla cafeterias_teusaquillo en Amazon RDS PostgreSQL.
-- Nota: distance_m es la distancia (en metros) al punto central desde el
-- que se consultó la API de Foursquare en la Actividad 2.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PANEL 1. Indicadores clave (Stat)
-- Propósito: resumir en una sola vista el tamaño de la oferta, qué tanto
-- se diversifica (locales multicategoría), qué tan dispersa está y qué
-- parte del territorio tiene al menos una cafetería.
-- ---------------------------------------------------------------------
WITH limites AS (
    SELECT MIN(latitude)  AS lat_min, MAX(latitude)  AS lat_max,
           MIN(longitude) AS lon_min, MAX(longitude) AS lon_max
    FROM cafeterias_teusaquillo
),
malla AS (
    SELECT i, j
    FROM limites,
         generate_series(0, FLOOR((lat_max - lat_min) / 0.0045)::INT) AS i,
         generate_series(0, FLOOR((lon_max - lon_min) / 0.0045)::INT) AS j
),
ocupadas AS (
    SELECT DISTINCT FLOOR((c.latitude  - l.lat_min) / 0.0045)::INT AS i,
                    FLOOR((c.longitude - l.lon_min) / 0.0045)::INT AS j
    FROM cafeterias_teusaquillo c CROSS JOIN limites l
)
SELECT
    (SELECT COUNT(*) FROM cafeterias_teusaquillo)                        AS "Cafeterías",
    (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE jsonb_array_length(categories) > 1)
                  / COUNT(*), 1) FROM cafeterias_teusaquillo)            AS "% multicategoría",
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_m)
       FROM cafeterias_teusaquillo)                                      AS "Distancia mediana (m)",
    ROUND(100.0 * (SELECT COUNT(*) FROM ocupadas) / (SELECT COUNT(*) FROM malla), 1)
                                                                         AS "% celdas con oferta";


-- ---------------------------------------------------------------------
-- PANEL 2. Inventario de establecimientos (Tabla)
-- Propósito: listado consultable y ordenable de cada cafetería, con su
-- categoría, si es un formato híbrido y su dirección. Es la vista de
-- detalle para validar casos puntuales.
-- ---------------------------------------------------------------------
SELECT
    name                                          AS "Cafetería",
    primary_category                              AS "Categoría principal",
    CASE WHEN jsonb_array_length(categories) > 1
         THEN 'Sí' ELSE 'No' END                  AS "Multicategoría",
    (SELECT string_agg(value, ', ')
       FROM jsonb_array_elements_text(categories)) AS "Todas las categorías",
    distance_m                                    AS "Distancia (m)",
    COALESCE(address, 'Sin dirección')            AS "Dirección"
FROM cafeterias_teusaquillo
ORDER BY distance_m;


-- ---------------------------------------------------------------------
-- PANEL 3. Distribución de distancias (Histograma)
-- Propósito: ver si la oferta está concentrada cerca del punto central
-- o repartida en el territorio. Grafana agrupa los valores en rangos.
-- ---------------------------------------------------------------------
SELECT distance_m AS "Distancia (m)"
FROM cafeterias_teusaquillo
WHERE distance_m IS NOT NULL;


-- ---------------------------------------------------------------------
-- PANEL 4. Mapa de establecimientos (Geomap)
-- Propósito: ubicar cada cafetería en el mapa, coloreada por categoría
-- principal, para identificar corredores y vacíos de oferta.
-- ---------------------------------------------------------------------
SELECT
    name             AS "Cafetería",
    latitude,
    longitude,
    primary_category AS "Categoría",
    distance_m       AS "Distancia (m)"
FROM cafeterias_teusaquillo;


-- ---------------------------------------------------------------------
-- PANEL 5. Densidad por celdas de ~500 m y zonas de oportunidad
--          (CONSULTA COMPLEJA: CTE + generate_series + LEFT JOIN +
--           funciones de ventana + clasificación con CASE)
-- Propósito: dividir el área en una cuadrícula de ~500 m x 500 m
-- (0,0045 grados a la latitud de Bogotá), contar cafeterías por celda
-- incluyendo las celdas vacías, y clasificar cada zona como saturada,
-- competida, con baja oferta o sin oferta. Es la base para decidir
-- dónde abrir un nuevo punto.
-- ---------------------------------------------------------------------
WITH limites AS (
    SELECT MIN(latitude)  AS lat_min, MAX(latitude)  AS lat_max,
           MIN(longitude) AS lon_min, MAX(longitude) AS lon_max
    FROM cafeterias_teusaquillo
),
malla AS (                      -- todas las celdas posibles del área
    SELECT i, j
    FROM limites,
         generate_series(0, FLOOR((lat_max - lat_min) / 0.0045)::INT) AS i,
         generate_series(0, FLOOR((lon_max - lon_min) / 0.0045)::INT) AS j
),
conteo AS (                     -- cafeterías y diversidad por celda ocupada
    SELECT FLOOR((c.latitude  - l.lat_min) / 0.0045)::INT AS i,
           FLOOR((c.longitude - l.lon_min) / 0.0045)::INT AS j,
           COUNT(*)                                        AS cafeterias,
           COUNT(*) FILTER (WHERE jsonb_array_length(c.categories) > 1) AS hibridas,
           string_agg(c.name, ', ' ORDER BY c.name)        AS establecimientos
    FROM cafeterias_teusaquillo c CROSS JOIN limites l
    GROUP BY 1, 2
)
SELECT
    'C' || LPAD(m.i::TEXT, 2, '0') || '-' || LPAD(m.j::TEXT, 2, '0') AS "Celda",
    ROUND((l.lat_min + (m.i + 0.5) * 0.0045)::NUMERIC, 5)          AS latitude,
    ROUND((l.lon_min + (m.j + 0.5) * 0.0045)::NUMERIC, 5)          AS longitude,
    COALESCE(c.cafeterias, 0)                                       AS "Cafeterías",
    COALESCE(c.hibridas, 0)                                         AS "Híbridas",
    DENSE_RANK() OVER (ORDER BY COALESCE(c.cafeterias, 0) DESC)     AS "Ranking",
    ROUND(100.0 * COALESCE(c.cafeterias, 0)
          / SUM(COALESCE(c.cafeterias, 0)) OVER (), 1)              AS "% de la oferta",
    CASE
        WHEN COALESCE(c.cafeterias, 0) >= 3 THEN 'Saturada'
        WHEN COALESCE(c.cafeterias, 0) = 2  THEN 'Competida'
        WHEN COALESCE(c.cafeterias, 0) = 1  THEN 'Baja oferta'
        ELSE 'Sin oferta (oportunidad)'
    END                                                             AS "Nivel de competencia",
    COALESCE(c.establecimientos, '')                                AS "Establecimientos"
FROM malla m
CROSS JOIN limites l
LEFT JOIN conteo c ON c.i = m.i AND c.j = m.j
ORDER BY "Cafeterías" DESC, "Celda";


-- ---------------------------------------------------------------------
-- PANEL 6. Frecuencia de categorías (Barras), consulta sobre JSONB
-- Propósito: descomponer el arreglo JSONB de categorías para ver con
-- qué otros negocios se combina la oferta de café (panadería,
-- coworking, etc.), es decir, qué formatos híbridos existen.
-- ---------------------------------------------------------------------
SELECT
    cat.value AS "Categoría",
    COUNT(*)  AS "Establecimientos"
FROM cafeterias_teusaquillo c
CROSS JOIN LATERAL jsonb_array_elements_text(c.categories) AS cat(value)
GROUP BY cat.value
ORDER BY "Establecimientos" DESC, "Categoría";


-- ---------------------------------------------------------------------
-- PANEL 7. Resumen por nivel de competencia (Barras)
-- Propósito: cuántas celdas del área caen en cada nivel; responde de
-- forma directa "¿cuánto territorio está libre de competencia?".
-- ---------------------------------------------------------------------
WITH limites AS (
    SELECT MIN(latitude)  AS lat_min, MAX(latitude)  AS lat_max,
           MIN(longitude) AS lon_min, MAX(longitude) AS lon_max
    FROM cafeterias_teusaquillo
),
malla AS (
    SELECT i, j
    FROM limites,
         generate_series(0, FLOOR((lat_max - lat_min) / 0.0045)::INT) AS i,
         generate_series(0, FLOOR((lon_max - lon_min) / 0.0045)::INT) AS j
),
conteo AS (
    SELECT FLOOR((c.latitude  - l.lat_min) / 0.0045)::INT AS i,
           FLOOR((c.longitude - l.lon_min) / 0.0045)::INT AS j,
           COUNT(*) AS n
    FROM cafeterias_teusaquillo c CROSS JOIN limites l
    GROUP BY 1, 2
),
niveles AS (
    SELECT CASE
               WHEN COALESCE(c.n, 0) >= 3 THEN '4. Saturada (3+)'
               WHEN COALESCE(c.n, 0) = 2  THEN '3. Competida (2)'
               WHEN COALESCE(c.n, 0) = 1  THEN '2. Baja oferta (1)'
               ELSE '1. Sin oferta (0)'
           END AS nivel
    FROM malla m LEFT JOIN conteo c ON c.i = m.i AND c.j = m.j
)
SELECT nivel AS "Nivel de competencia", COUNT(*) AS "Celdas"
FROM niveles
GROUP BY nivel
ORDER BY nivel;
