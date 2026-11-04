#!/bin/bash
# 337: INSTALL POSTGRES ON THIS BOX. The 54 GB database on Railway costs £170/month and every test job pulls data across
# the internet (egress). History and tape tables move here; the engine's small live tables stay on Railway.
# Idempotent. Writes the local DSN to /root/.pe_local_pg.env (root only). Never prints the password.
set -o pipefail
echo "== disk before"; df -h / | tail -1
if ! command -v psql >/dev/null || ! systemctl is-active --quiet postgresql 2>/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  . /etc/os-release
  install -d /usr/share/postgresql-common/pgdg
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  apt-get update -qq && apt-get install -y -qq postgresql-17 postgresql-client-17 >/dev/null
  systemctl enable --now postgresql
fi
echo "== versions"; psql --version; pg_dump --version; systemctl is-active postgresql
PGV=$(ls /etc/postgresql | sort -n | tail -1); CONF=/etc/postgresql/$PGV/main/postgresql.conf
# tuning for a test box: this machine has $(free -g | awk '/Mem/{print $2}') GB RAM; local connections only (no public listen)
MEM=$(free -m | awk '/Mem/{print $2}')
SB=$((MEM/4))MB; EC=$((MEM*3/4))MB
for kv in "shared_buffers = $SB" "effective_cache_size = $EC" "work_mem = 128MB" "maintenance_work_mem = 1GB" "max_wal_size = 4GB" "checkpoint_completion_target = 0.9" "random_page_cost = 1.1" "max_parallel_workers_per_gather = 4" "listen_addresses = 'localhost'" "statement_timeout = 0"; do
  k=${kv%% =*}; sed -i "/^#\?\s*$k\s*=/d" $CONF; echo "$kv" >> $CONF; done
systemctl restart postgresql
if [ ! -f /root/.pe_local_pg.env ]; then
  PW=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
  sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='pe') THEN CREATE ROLE pe LOGIN PASSWORD '$PW' SUPERUSER; END IF; END \$\$;"
  sudo -u postgres psql -qc "CREATE DATABASE petrade OWNER pe" 2>/dev/null || true
  (umask 077; echo "PE_LOCAL_PG=postgresql://pe:$PW@127.0.0.1:5432/petrade" > /root/.pe_local_pg.env)
  echo "local DSN written"
fi
set -a; . /root/.pe_local_pg.env; set +a
psql "$PE_LOCAL_PG" -qtc "select 'local pg ok: '||version()" | head -1
psql "$PE_LOCAL_PG" -qc "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" 2>/dev/null || true
echo "== settings"; psql "$PE_LOCAL_PG" -qtc "select name||'='||setting||coalesce(unit,'') from pg_settings where name in ('shared_buffers','work_mem','effective_cache_size','listen_addresses')"
echo "== creds check"; python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.report())"
echo "== disk after"; df -h / | tail -1
