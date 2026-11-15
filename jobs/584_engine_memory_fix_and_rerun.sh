#!/bin/bash
# 584 (Sun 15 Nov 2026, 15:35). Weekly engine: every sport died at fairprice_v0.py line 22 — GROUP BY over the whole bf_hist_other (52M rows)
# kills the Postgres backend (out of memory). Same failure on 10 Nov (fairprice_v1_<sport>.log, identical 612 bytes); never read.
# Fix: with FP_SPORTS set, count markets per type from bf_hist_result (one row a runner, sport-filtered), work_mem capped; non-football
# sports run first, Soccer last; weekly_engine.sh writes reports/weekly_engine_latest.md and appends to reports/breaks.md on any non-zero
# exit. Then run the engine NOW in the background (nohup) instead of waiting for Sunday.
set -o pipefail
cd /root/pe-sports/team; cp fairprice_v0.py fairprice_v0.py.bak_584
python3 - <<'PY'
p='/root/pe-sports/team/fairprice_v0.py'; s=open(p).read(); assert '584' not in s
old='cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()'
new='''_only=[x for x in os.environ.get('FP_SPORTS','').split(',') if x]
cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='3000s'")
if _only:   # 584: never GROUP BY the whole tape (backend died on it every run since 10 Nov); the results table is one row a runner
    types=[]
    for _s in _only:
        cur.execute("SELECT %s::text, market_type, count(DISTINCT market_id) FROM bf_hist_result WHERE sport=%s GROUP BY 2 HAVING count(DISTINCT market_id)>=200 ORDER BY 3 DESC",(_s,_s)); types+=cur.fetchall()
else:
    cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_result GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()'''
assert old in s; s=s.replace(old,new,1)
if 'import os' not in s.split('\n',12)[0:12].__str__(): s=s.replace('import ','import os, ',1)
open(p,'w').write(s); print("fairprice_v0: sport-filtered type list, work_mem capped")
PY
python3 -m py_compile fairprice_v0.py && echo "engine compiles" || { cp fairprice_v0.py.bak_584 fairprice_v0.py; echo RESTORED; exit 1; }
cat > weekly_engine.sh <<'SH'
#!/bin/bash
# 572/584: the fair-price engine, every sport, one at a time (football last), then the Verifier. Sunday 01:00 UTC. Writes a report and logs breaks.
cd /root/pe-sports/team; L=/root/pe-sports/team/weekly_engine.log; OUT=/root/pe-queue/reports/weekly_engine_latest.md; FAIL=""
echo "== $(date -u '+%F %H:%M') weekly engine ==" >> $L
SPORTS=$(python3 -c "
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute(\"SET statement_timeout='600s'\"); c.execute(\"select distinct sport from bf_hist_result\"); s=[x for (x,) in c.fetchall()]; s=[x for x in s if x!='Soccer']+(['Soccer'] if 'Soccer' in s else []); print(' '.join(x.replace(' ','_') for x in s))")
for S in $SPORTS; do
  N="${S//_/ }"; [ "$(free -m | awk '/Mem:/{print $7}')" -lt 1200 ] && { echo "skip $N: under 1.2 GB free memory" >> $L; FAIL="$FAIL $N(memory)"; continue; }
  FP_SPORTS="$N" timeout 7200 /usr/bin/python3 fairprice_v0.py > "fairprice_weekly_${S}.log" 2>&1; rc=$?
  echo "$N exit $rc RESULT lines $(grep -c ^RESULT fairprice_weekly_${S}.log)" >> $L; [ $rc -ne 0 ] && FAIL="$FAIL $N(exit $rc)"
done
/usr/bin/python3 verifier_cells.py >> $L 2>&1; echo "verifier done $(date -u +%H:%M)" >> $L
{ echo "# Weekly engine $(date -u '+%F %H:%M') UTC"; echo; echo '```'; tail -40 $L | grep -v Deprecation; echo '```'; echo; echo "## last 6 lines of each sport log"; for f in fairprice_weekly_*.log; do echo "### $f"; echo '```'; grep -v Deprecation $f | tail -6 | cut -c1-200; echo '```'; done; } > $OUT
[ -n "$FAIL" ] && echo "$(date -u +%FT%H:%M) BREAK: weekly engine failed for$FAIL (see reports/weekly_engine_latest.md)" >> /root/pe-queue/reports/breaks.md
cd /root/pe-queue && git add reports/weekly_engine_latest.md reports/breaks.md 2>/dev/null; git commit -qm "weekly engine report" 2>/dev/null; git pull -q --no-rebase --no-edit 2>/dev/null; git push -q 2>/dev/null
SH
chmod +x weekly_engine.sh; bash -n weekly_engine.sh && echo "weekly_engine compiles" || exit 1
echo "== run the engine now, in the background =="
pgrep -f fairprice_v0.py >/dev/null && echo "engine already running" || { nohup /root/pe-sports/team/weekly_engine.sh > /root/pe-sports/team/weekly_engine_nohup.log 2>&1 & disown; sleep 90; echo "started: $(pgrep -fa 'fairprice_v0|weekly_engine' | cut -c1-100)"; tail -3 /root/pe-sports/team/weekly_engine.log; for f in /root/pe-sports/team/fairprice_weekly_*.log; do echo "$f: $(grep -v Deprecation $f | tail -2 | cut -c1-160)"; done; }
echo "584 done"
