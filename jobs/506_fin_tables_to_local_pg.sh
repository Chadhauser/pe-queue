#!/bin/bash
# 506: FINANCIAL — follow the estate off Railway ($230/month). (1) copy the financial tables Railway -> local Postgres 18 (streaming
# pg_dump|psql, all small; skip if already local with >=98% rows); (2) /root/pe-fin/findb.py exposes DB = PE_LOCAL_PG when
# /root/.pe_local_pg.env exists, else bot_core.DB; (3) every financial script that did `from bot_core import DB` now does
# `from findb import DB` (pe-fin, pe-factory/v4, pe-report). Nothing dropped on Railway. Explained to Peter 4 Nov 06:50.
set -o pipefail
[ -f /root/.pe_local_pg.env ] || { echo "no /root/.pe_local_pg.env yet (340 not run) — nothing to do"; exit 0; }
set -a; . /root/.pe_local_pg.env; set +a
RAIL=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_railway())")
PGD=/usr/lib/postgresql/18/bin/pg_dump; [ -x $PGD ] || PGD=pg_dump
TABLES="v4_fin_results v4_fin_xsmom v4_intraday v4_session v4_trend_portfolio v4_trend_rollfree v4_state_scan v4_tqqq v4_intraday_grammar orb_trades orb_qqq_trades orb_stocks_daily fin_config fin_strategies fin_paper_positions fin_paper_daily fin_heartbeat"
FAILS=0
for t in $TABLES; do
  exists=$(psql "$RAIL" -Atqc "select to_regclass('public.$t') is not null" 2>/dev/null); [ "$exists" = "t" ] || { echo "-- $t: not on Railway, skip"; continue; }
  rn=$(psql "$RAIL" -Atqc "select count(*) from $t"); ln=$(psql "$PE_LOCAL_PG" -Atqc "select count(*) from $t" 2>/dev/null || echo -1)
  if [ "$ln" -ge 0 ] && [ $(( ln * 100 / (rn + 1) )) -ge 98 ]; then echo "-- $t: already local ($ln rows), skip"; continue; fi
  echo "-- $t: copying ($rn rows)"
  if $PGD --no-owner --no-privileges --clean --if-exists -t "public.$t" "$RAIL" | psql "$PE_LOCAL_PG" -q -v ON_ERROR_STOP=1 >/dev/null; then echo "   done: local $(psql "$PE_LOCAL_PG" -Atqc "select count(*) from $t") rows"; else echo "   FAILED"; FAILS=$((FAILS+1)); fi
done
cat > /root/pe-fin/findb.py <<'PY'
import os, re
DB=None
try:
    for ln in open('/root/.pe_local_pg.env'):
        m=re.match(r'^\s*(?:export\s+)?PE_LOCAL_PG\s*=\s*(.*?)\s*$',ln)
        if m: DB=m.group(1).strip().strip('"').strip("'")
except Exception: pass
if not DB:
    import sys; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
PY
python3 -c "import sys; sys.path.insert(0,'/root/pe-fin'); import findb; print('findb ->', 'LOCAL' if 'localhost' in findb.DB or '127.0.0.1' in findb.DB else 'RAILWAY')"
n=0; for f in /root/pe-fin/*.py /root/pe-factory/v4/*.py /root/pe-report/fin_*.py; do [ -f "$f" ] || continue; grep -q "from bot_core import DB" "$f" || continue; sed -i "s#sys.path.insert(0,'/root/pe-bot'); from bot_core import DB#sys.path.insert(0,'/root/pe-fin'); from findb import DB#; s#from bot_core import DB#from findb import DB#" "$f"; python3 -m py_compile "$f" && n=$((n+1)); done; echo "scripts switched to findb: $n"
grep -l "from findb import DB" /root/pe-fin/*.py /root/pe-factory/v4/*.py 2>/dev/null | xargs -n1 basename | tr '\n' ' '; echo
# sslmode=require in psycopg2.connect calls breaks on localhost -> prefer
sed -i "s/sslmode='require'/sslmode='prefer'/g" /root/pe-fin/*.py /root/pe-factory/v4/*.py 2>/dev/null; echo "sslmode -> prefer"
echo "== smoke: paper engine can open the DB"; cd /root/pe-fin && python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-fin'); from findb import DB; import psycopg2
con=psycopg2.connect(DB,sslmode='prefer'); cur=con.cursor(); cur.execute("select count(*) from fin_strategies"); print("fin_strategies rows", cur.fetchone()[0]); cur.execute("select count(*) from orb_qqq_trades"); print("orb_qqq_trades rows", cur.fetchone()[0])
PY
echo "tables failed: $FAILS"; [ "$FAILS" -eq 0 ]
