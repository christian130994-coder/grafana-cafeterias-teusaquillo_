#!/usr/bin/env bash
# =====================================================================
# instalar.sh
# Monta el dashboard de Grafana sobre Amazon RDS PostgreSQL en una
# instancia EC2 con Amazon Linux 2023.
#
# Uso (desde la carpeta del repositorio, en la EC2):
#   sudo bash instalar.sh
#
# Qué hace:
#   1. Instala Docker y el cliente de PostgreSQL.
#   2. Verifica la conexión con RDS (grupo de seguridad, credenciales).
#   3. Crea la base de datos, la tabla y carga las 46 cafeterías (UPSERT).
#   4. Crea un usuario de solo lectura para Grafana.
#   5. Levanta Grafana en Docker con la conexión y el dashboard ya
#      configurados (provisioning), con acceso de solo lectura para el
#      evaluador.
# Las claves se piden por teclado y nunca se escriben en el repositorio.
# =====================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAFANA_DIR=/opt/grafana
GRAFANA_IMAGE=grafana/grafana-oss:11.2.0

paso() { echo; echo "==> $*"; }
falla() { echo; echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || falla "Ejecuta el script con sudo: sudo bash instalar.sh"
cd "$REPO_DIR"
for f in 01_ddl.sql 02_carga.sql 03_usuario_lectura.sql cafeterias.json rds.yaml provider.yaml; do
  [ -f "$f" ] || falla "Falta el archivo $f en la carpeta del repositorio."
done
[ -f cafeterias_teusaquillo_limpio.csv ] || falla "Falta el archivo cafeterias_teusaquillo_limpio.csv."

# ---------------------------------------------------------------------
# 0. Datos de conexión (se piden por teclado)
# ---------------------------------------------------------------------
echo "Datos de tu base de datos RDS (los encuentras en la consola de RDS)."
read -rp "Endpoint de RDS (ej. cafeterias-db.xxxx.us-east-1.rds.amazonaws.com): " RDS_ENDPOINT
RDS_ENDPOINT="${RDS_ENDPOINT// /}"
RDS_ENDPOINT="${RDS_ENDPOINT%:5432}"
[ -n "$RDS_ENDPOINT" ] || falla "El endpoint no puede estar vacío."
read -rp "Usuario administrador de RDS [postgres]: " RDS_USER
RDS_USER="${RDS_USER:-postgres}"
read -rsp "Contraseña del administrador de RDS: " RDS_PASSWORD; echo
read -rp "Nombre de la base de datos [cafeterias]: " RDS_DB
RDS_DB="${RDS_DB:-cafeterias}"
while true; do
  read -rsp "Crea una contraseña para entrar a Grafana como admin (mínimo 8 caracteres): " GF_ADMIN; echo
  [ "${#GF_ADMIN}" -ge 8 ] && break
  echo "Muy corta, intenta de nuevo."
done

# ---------------------------------------------------------------------
# 1. Paquetes
# ---------------------------------------------------------------------
paso "Instalando Docker y el cliente de PostgreSQL (1 a 2 minutos)"
dnf install -y -q docker >/dev/null
dnf install -y -q postgresql16 >/dev/null 2>&1 || dnf install -y -q postgresql15 >/dev/null
systemctl enable --now docker >/dev/null

export PGHOST="$RDS_ENDPOINT" PGPORT=5432 PGUSER="$RDS_USER" PGPASSWORD="$RDS_PASSWORD" \
       PGSSLMODE=require PGCONNECT_TIMEOUT=10

# ---------------------------------------------------------------------
# 2. Conexión a RDS
# ---------------------------------------------------------------------
paso "Probando la conexión con RDS"
if ! psql -d postgres -tAc "SELECT 1" >/dev/null 2>/tmp/rds_error.txt; then
  cat /tmp/rds_error.txt
  falla "No hay conexión con RDS. Revisa: (a) que la base esté en estado 'Available',
  (b) que al crearla elegiste 'Connect to an EC2 compute resource' con esta instancia
  (o que su grupo de seguridad permita el puerto 5432 desde la EC2),
  (c) el endpoint y la contraseña."
fi
echo "Conexión OK."

# ---------------------------------------------------------------------
# 3. Base de datos, tabla y carga
# ---------------------------------------------------------------------
paso "Creando la base de datos '$RDS_DB' si no existe"
if [ "$(psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$RDS_DB'")" != "1" ]; then
  psql -d postgres -v ON_ERROR_STOP=1 -qc "CREATE DATABASE \"$RDS_DB\""
fi
export PGDATABASE="$RDS_DB"

paso "Creando la tabla (DDL)"
psql -v ON_ERROR_STOP=1 -q -f 01_ddl.sql

paso "Cargando las cafeterías (UPSERT idempotente)"
psql -v ON_ERROR_STOP=1 -q -f 02_carga.sql

# ---------------------------------------------------------------------
# 4. Usuario de solo lectura para Grafana
# ---------------------------------------------------------------------
paso "Creando el usuario de solo lectura grafana_reader"
GRAFANA_DB_PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
psql -v ON_ERROR_STOP=1 -q -v clave="$GRAFANA_DB_PASSWORD" -v bd="$RDS_DB" -f 03_usuario_lectura.sql

# ---------------------------------------------------------------------
# 5. Grafana
# ---------------------------------------------------------------------
paso "Configurando Grafana"
rm -rf "$GRAFANA_DIR/provisioning" "$GRAFANA_DIR/dashboards"
mkdir -p "$GRAFANA_DIR/provisioning/datasources" "$GRAFANA_DIR/provisioning/dashboards" "$GRAFANA_DIR/dashboards"
cp rds.yaml      "$GRAFANA_DIR/provisioning/datasources/rds.yaml"
cp provider.yaml "$GRAFANA_DIR/provisioning/dashboards/provider.yaml"
cp cafeterias.json "$GRAFANA_DIR/dashboards/cafeterias.json"

umask 077
cat > "$GRAFANA_DIR/grafana.env" <<EOF
RDS_ENDPOINT=$RDS_ENDPOINT
RDS_DB=$RDS_DB
GRAFANA_DB_PASSWORD=$GRAFANA_DB_PASSWORD
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=$GF_ADMIN
GF_AUTH_ANONYMOUS_ENABLED=true
GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/cafeterias.json
GF_USERS_ALLOW_SIGN_UP=false
GF_ANALYTICS_REPORTING_ENABLED=false
EOF
umask 022
chmod 600 "$GRAFANA_DIR/grafana.env"
unset PGPASSWORD RDS_PASSWORD GF_ADMIN

paso "Descargando e iniciando Grafana ($GRAFANA_IMAGE)"
docker rm -f grafana >/dev/null 2>&1 || true
docker volume create grafana-data >/dev/null
docker run -d --name grafana --restart unless-stopped \
  -p 3000:3000 \
  --env-file "$GRAFANA_DIR/grafana.env" \
  -v grafana-data:/var/lib/grafana \
  -v "$GRAFANA_DIR/provisioning:/etc/grafana/provisioning:ro" \
  -v "$GRAFANA_DIR/dashboards:/var/lib/grafana/dashboards:ro" \
  "$GRAFANA_IMAGE" >/dev/null

echo -n "Esperando a que Grafana arranque"
for _ in $(seq 1 60); do
  if curl -fs http://localhost:3000/api/health >/dev/null 2>&1; then echo " listo."; break; fi
  echo -n "."; sleep 2
done
curl -fs http://localhost:3000/api/health >/dev/null || { docker logs --tail 40 grafana; falla "Grafana no arrancó."; }

# IP pública (metadatos de la instancia, IMDSv2)
TOKEN="$(curl -fs -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' || true)"
IP="$(curl -fs -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 || echo '<IP-publica>')"

echo
echo "====================================================================="
echo " Listo. Dashboard disponible en:  http://$IP:3000"
echo " - El evaluador lo ve sin usuario (solo lectura)."
echo " - Para editar: botón 'Sign in', usuario admin y la clave que creaste."
echo " Recuerda: quitar la regla del puerto 22 del grupo de seguridad."
echo "====================================================================="
