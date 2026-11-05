#!/bin/bash
# 354: the loader's bookkeeping tables (bf_hist_other_files, bf_hist_months) were not in the migration list, so the local
# loader is re-downloading months Railway already held and DUPLICATING rows in bf_hist_other. Fix: stop the loader, copy
# the two bookkeeping tables from Railway, rebuild bf_hist_other without duplicates (DISTINCT ON market_id, sel, ts),
# add a unique index so it cannot recur, make the loader insert ON CONFLICT DO NOTHING, restart. Runs after 353.
set -o pipefail
export PATH=/usr/lib/postgresql/18/bin:$PATH
set -a; . /root/.pe_local_pg.env; set +a
RAIL=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_railway())")
pkill -f keepalive_hist.sh; pkill -f "pe-hist/loader.py"; sleep 3; echo "loader stopped"
for t in bf_hist_other_files bf_hist_months; do
  psql "$PE_LOCAL_PG" -qc "DROP TABLE IF EXISTS ${t}_rail"
  pg_dump --no-owner --no-acl -t public.$t "$RAIL" | sed "s/\b$t\b/${t}_rail/g" | psql "$PE_LOCAL_PG" -q -v ON_ERROR_STOP=1
  psql "$PE_LOCAL_PG" -Atc "select '$t rail rows: '||count(*) from ${t}_rail"
done
psql "$PE_LOCAL_PG" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS bf_hist_other_files (path TEXT PRIMARY KEY, loaded_at TIMESTAMPTZ);
CREATE TABLE IF NOT EXISTS bf_hist_months (sport TEXT, y INT, m INT, status TEXT, files INT, loaded INT, updated TIMESTAMPTZ, PRIMARY KEY (sport,y,m));
INSERT INTO bf_hist_other_files SELECT * FROM bf_hist_other_files_rail ON CONFLICT DO NOTHING;
INSERT INTO bf_hist_months SELECT * FROM bf_hist_months_rail ON CONFLICT (sport,y,m) DO NOTHING;
DROP TABLE bf_hist_other_files_rail; DROP TABLE bf_hist_months_rail;
SELECT 'files known: '||count(*) FROM bf_hist_other_files;
SELECT 'before: '||count(*) FROM bf_hist_other;
SET maintenance_work_mem='2GB'; SET work_mem='512MB';
CREATE TABLE bf_hist_other_dedup AS SELECT DISTINCT ON (market_id, sel, ts) * FROM bf_hist_other ORDER BY market_id, sel, ts;
SELECT 'after: '||count(*) FROM bf_hist_other_dedup;
DROP TABLE bf_hist_other; ALTER TABLE bf_hist_other_dedup RENAME TO bf_hist_other;
CREATE UNIQUE INDEX bfo_uniq ON bf_hist_other (market_id, sel, ts);
CREATE INDEX bfo_mkt ON bf_hist_other (sport, market_id);
CREATE INDEX bfo_type_time ON bf_hist_other (sport, market_type, market_time);
ANALYZE bf_hist_other;
SQL
python3 - <<'PY'
p='/root/pe-hist/loader_core.py'; s=open(p).read()
s=s.replace('"INSERT INTO bf_hist_other VALUES %s",rows,page_size=5000','"INSERT INTO bf_hist_other VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000')
open(p,'w').write(s); print("loader insert is ON CONFLICT DO NOTHING:", s.count("ON CONFLICT DO NOTHING\",rows"))
PY
python3 -m py_compile /root/pe-hist/loader_core.py || exit 1
nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
sleep 60; pgrep -af "pe-hist/loader" | head -1; tail -4 /root/pe-hist/loader.log | cut -c1-200
echo "== disk"; df -h / | tail -1
