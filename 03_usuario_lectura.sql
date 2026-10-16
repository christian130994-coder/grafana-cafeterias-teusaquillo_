-- =====================================================================
-- 03_usuario_lectura.sql
-- Usuario de SOLO LECTURA para Grafana (principio de mínimo privilegio).
-- Grafana nunca usa el usuario administrador de RDS.
-- instalar.sh lo ejecuta pasando la clave como variable:
--   psql -v clave="..." -v bd="cafeterias" -f 03_usuario_lectura.sql
-- =====================================================================
SELECT format('CREATE ROLE grafana_reader LOGIN PASSWORD %L', :'clave')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_reader') \gexec
SELECT format('ALTER ROLE grafana_reader WITH LOGIN PASSWORD %L', :'clave') \gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO grafana_reader', :'bd') \gexec
GRANT USAGE ON SCHEMA public TO grafana_reader;
GRANT SELECT ON cafeterias_teusaquillo TO grafana_reader;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON cafeterias_teusaquillo FROM grafana_reader;
