#!/bin/bash
# 340: Railway is PostgreSQL 18.6; 337 installed a 17 server (pg_dump 17 refuses an 18 server). Put 18 on the box:
# install postgresql-18, drop the EMPTY 17 cluster, make the 18 cluster listen on 5432, recreate role/db with the DSN
# already in /root/.pe_local_pg.env (unchanged), same tuning. Refuses to drop the 17 cluster if it holds any user table.
set -o pipefail
export DEBIAN_FRONTEND=noninteractive
set -a; . /root/.pe_local_pg.env; set +a
PW=$(echo "$PE_LOCAL_PG" | sed -E 's#postgresql://pe:([^@]+)@.*#\1#')
n17=$(psql "$PE_LOCAL_PG" -Atqc "select count(*) from pg_class where relkind='r' and relnamespace='public'::regnamespace" 2>/dev/null || echo 0)
echo "user tables in the 17 cluster: $n17"
[ "${n17:-0}" -eq 0 ] || { echo "17 cluster is not empty, refusing to drop it"; exit 1; }
apt-get install -y -qq postgresql-18 postgresql-client-18 >/dev/null
pg_lsclusters
pg_dropcluster --stop 17 main 2>/dev/null || true
if ! pg_lsclusters | grep -q "^18 *main"; then pg_createcluster 18 main; fi
CONF=/etc/postgresql/18/main/postgresql.conf
MEM=$(free -m | awk '/Mem/{print $2}'); SB=$((MEM/4))MB; EC=$((MEM*3/4))MB
for kv in "port = 5432" "shared_buffers = $SB" "effective_cache_size = $EC" "work_mem = 128MB" "maintenance_work_mem = 1GB" "max_wal_size = 4GB" "checkpoint_completion_target = 0.9" "random_page_cost = 1.1" "max_parallel_workers_per_gather = 4" "listen_addresses = 'localhost'" "statement_timeout = 0"; do
  k=${kv%% =*}; sed -i "/^#\?\s*$k\s*=/d" $CONF; echo "$kv" >> $CONF; done
pg_ctlcluster 18 main restart; sleep 2; pg_lsclusters
sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='pe') THEN CREATE ROLE pe LOGIN PASSWORD '$PW' SUPERUSER; ELSE ALTER ROLE pe PASSWORD '$PW'; END IF; END \$\$;"
sudo -u postgres psql -qc "CREATE DATABASE petrade OWNER pe" 2>/dev/null || true
psql "$PE_LOCAL_PG" -qtc "select 'local pg ok: '||version()" | head -1
ls /usr/lib/postgresql/18/bin/pg_dump && /usr/lib/postgresql/18/bin/pg_dump --version
echo "== disk"; df -h / | tail -1
