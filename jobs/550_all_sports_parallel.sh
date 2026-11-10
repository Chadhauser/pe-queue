#!/bin/bash
# 550 (Tue 10 Nov 2026, 13:45). Peter: "why can't you do all at once?" — right. The other sports' maps were queued one after another
# (545). Now: every sport except Soccer runs in parallel, three at a time, each its own process and log, so one sport's failure costs only
# that sport and the rest finish hours sooner. Cells pass straight into fair_price_passed and the taker bot picks them up at its next read.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team
# stop 545's sequential loop if it is still going (its current sport restarts below; nothing else is lost)
for pid in $(pgrep -f "545_fix_markers"); do kill $pid 2>/dev/null; done; pkill -f fairprice_v0.py; sleep 3
SPORTS=$(python3 -c "
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute(\"select distinct sport from bf_hist_other where sport<>'Soccer' except select distinct sport from fair_price_calib where sport<>'Soccer'\"); print('\n'.join(s for (s,) in c.fetchall()))")
echo "sports to map:"; echo "$SPORTS"
echo "$SPORTS" | grep -v '^$' | xargs -d '\n' -P 3 -I{} bash -c 'S="{}"; L="fairprice_v1_$(echo "$S" | tr " " "_").log"; echo "start $S $(date -u +%H:%M)"; FP_SPORTS="$S" timeout 10000 python3 fairprice_v0.py > "$L" 2>&1; echo "done $S exit $? RESULT lines $(grep -c ^RESULT "$L") $(date -u +%H:%M)"; grep -v ^RESULT "$L" | tail -2'
python3 /root/pe-sports/team/verifier_cells.py
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select sport, count(*) from fair_price_calib group by 1 order by 2 desc"); print("calibration cells by sport:",c.fetchall())
c.execute("select sport, count(*) from fair_price_passed group by 1 order by 2 desc"); print("PASSED cells by sport (the bot trades these):",c.fetchall())
PY
pkill -f bookie_v2.py   # relaunch so it re-reads the cells and widens its universe now rather than in 10 min
echo "550 done"
