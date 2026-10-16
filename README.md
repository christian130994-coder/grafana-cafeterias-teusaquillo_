# Actividad 5. Dashboard analítico en Grafana sobre Amazon RDS

**Herramientas de Computación en la Nube** · Maestría en Analítica Aplicada · Universidad de La Sabana

**Integrantes:** Antonia Gacharná Echeverri, Christian Fabián Jaimes Toscano y Efren Alexander Granados Latorre

**Dashboard (snapshot público):** https://snapshots.raintank.io/dashboard/snapshot/f9InufNo4CVjaQ0y26XyedXmRRgRcebv

**Informe:** `Informe_Actividad5_Grafana.pdf`

## Objetivo

Cerrar el pipeline de cafeterías de Teusaquillo construido en las actividades
anteriores con una capa de visualización: un dashboard en Grafana, desplegado
en Amazon EC2, que consulta directamente la base Amazon RDS PostgreSQL y
convierte los 46 establecimientos en información para decidir dónde abrir,
competir o diferenciarse.

## Arquitectura

```
Foursquare API → S3 (zona raw) → AWS Lambda (UPSERT) → Amazon RDS PostgreSQL
                                                              │  usuario de solo lectura, SSL
                                                              ▼
                                    Amazon EC2 (Amazon Linux 2023) + Docker + Grafana
                                                              │  puerto 3000, visor anónimo
                                                              ▼
                                                     Dashboard (8 paneles)
```

## Contenido

| Archivo | Descripción |
|---|---|
| `01_ddl.sql` | Tabla `cafeterias_teusaquillo` con tipos, restricciones e índices (de la Actividad 3) |
| `02_carga.sql` | Carga idempotente del CSV (misma transformación y UPSERT de la Lambda de la Actividad 4) |
| `03_usuario_lectura.sql` | Usuario `grafana_reader` de solo lectura (mínimo privilegio) |
| `04_consultas_dashboard.sql` | Las 7 consultas del dashboard, documentadas |
| `cafeterias.json` | Dashboard de Grafana |
| `rds.yaml` | Conexión de Grafana a RDS (sin credenciales; se leen de variables de entorno) |
| `provider.yaml` | Carga automática del dashboard en Grafana |
| `instalar.sh` | Instalación completa en la EC2 en un solo comando |
| `Informe_Actividad5_Grafana.pdf` | Reporte técnico de la entrega (4 páginas) |
| `cafeterias_teusaquillo_limpio.csv` | 46 cafeterías validadas contra el polígono de Teusaquillo (de la Actividad 2) |

## Paneles

1. Indicadores clave (total, % multicategoría, distancia mediana, % de celdas con oferta)
2. Mapa de cafeterías por categoría (geomap)
3. Densidad por celda de ~500 m (geomap)
4. Histograma de distancias
5. Frecuencia de categorías desde JSONB
6. Celdas por nivel de competencia
7. Ranking de zonas y oportunidades (consulta compleja: CTE, `generate_series`, `LEFT JOIN`, funciones de ventana)
8. Inventario de establecimientos (tabla)

## Despliegue

En la EC2 (Amazon Linux 2023), con la base RDS ya creada:

```bash
sudo dnf install -y git
git clone https://github.com/christian130994-coder/grafana-cafeterias-teusaquillo_.git
cd grafana-cafeterias-teusaquillo_
sudo bash instalar.sh
```

## Seguridad y FinOps

- Grafana se conecta con `grafana_reader`, que solo tiene `SELECT` sobre la tabla.
- Las claves se piden por teclado; el archivo de entorno queda en la EC2 con permisos `600` y está excluido del repositorio.
- RDS no es pública: solo acepta el puerto 5432 desde el grupo de seguridad de la EC2, con SSL obligatorio.
- El puerto 22 se abre solo durante la instalación; el evaluador entra como visor anónimo de solo lectura.
- Al finalizar se terminó la EC2 y se eliminó la base RDS (evidencias en el informe).

## Antecedentes

Esta actividad continúa el pipeline desarrollado por el mismo equipo en las actividades anteriores:

| Actividad | Aporte reutilizado | Repositorio |
|---|---|---|
| 2. Ingesta desde Foursquare a S3 | CSV depurado de 46 cafeterías | [Antoniaga/actividad-cafeterias-teusaquillo](https://github.com/Antoniaga/actividad-cafeterias-teusaquillo) |
| 3. Carga analítica en Amazon RDS | Modelo de datos y script DDL | [alexandergl55-design/actividad3-cafeterias-rds](https://github.com/alexandergl55-design/actividad3-cafeterias-rds) |
| 4. Pipeline serverless con AWS Lambda | Transformación y UPSERT | [Antoniaga/actividad4-lambda-cafeterias-rds](https://github.com/Antoniaga/actividad4-lambda-cafeterias-rds) |
