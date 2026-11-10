#!/bin/bash
# 545 (Tue 10 Nov 2026). Three things the Monday reports showed:
#  (a) 543 wrote STOPPED markers into KEEP folders (pe-liq, pe-sports, pe-queue*, pe-guard, pe-data): the daemons kept running, but a
#      watchdog honours STOPPED and would not restart them after a crash. Removed here. Caught by the Watchman, fixed within the day.
#  (b) liq_sample still lands locally an hour late in batches: the liq recorder (pe-liq) carries its OWN database string, not bot_core.DB,
#      so 536's cutover did not move it — it still writes Railway and the hourly sync copies it over. Pointed at the local database here and
#      restarted; proof = local rows within 3 minutes. Railway cannot be cancelled until this is true.
#  (c) 544's other-sports run died on an SSL connection drop (local Postgres over sslmode=prefer during a long read). Re-run here one
#      sport at a time over a plain local socket (sslmode=disable), so one sport's failure cannot take the others. Football's 19 passed
#      cells stand; its scoreboard lines are copied into reports/fairprice_football_2026-11-09.md for Peter.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== (a) STOPPED markers out of KEEP folders =="
for d in pe-liq pe-sports pe-queue pe-queue-logs pe-queue-state pe-guard pe-data pe-migrate pe-hist pe-ip pe-stream pe-xx pe-watchman; do
  f=/root/$d/STOPPED; if [ -f "$f" ] && grep -q "paused 543" "$f"; then rm -f "$f"; echo "removed $f"; fi
done
echo "== (b) liq recorder -> local database =="
echo "-- diagnosis: what does the running recorder connect to, and what does bot_core.DB resolve to? --"
for pid in $(pgrep -f liq_recorder.py); do echo "pid $pid started $(ps -o lstart= -p $pid)"; ss -tnp 2>/dev/null | grep "pid=$pid," | awk '{print "  ->",$5}' | sort -u | head -3; done
echo "bot_core.py mtime: $(stat -c %y /root/pe-bot/bot_core.py)"; python3 -c "import sys; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB; print('bot_core.DB host:', 'LOCAL' if ('127.0.0.1' in DB or 'localhost' in DB) else 'REMOTE')"
cd /root/pe-liq && cp liq_recorder.py liq_recorder.py.bak_545
python3 - <<'PY2'
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
if '545' in s: print("already pinned local")
else:
    anchor="sys.path.insert(0,'/root/pe-queue/runner'); import creds\n"
    assert s.count(anchor)==1, "creds import anchor"
    s=s.replace(anchor,anchor+"DB=creds.pg_local()   # 545: pinned to the local database whatever bot_core says\n",1); open(p,'w').write(s); print("DB pinned to creds.pg_local()")
PY2
python3 -m py_compile liq_recorder.py && echo "recorder compiles" || { cp liq_recorder.py.bak_545 liq_recorder.py; echo "RESTORED"; }
pkill -f liq_recorder.py; echo "recorder stopped; keepalive relaunches within 60 s"; sleep 180
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()).cursor(); c.execute("select count(*), max(ts) from liq_sample where ts>now()-interval '3 minutes'"); n,m=c.fetchone()
print("LOCAL liq_sample last 3 min: rows",n,"max",m, "| PROOF", "PASS — recorder writes local" if n else "FAIL — still not local (or no in-play football right now: check liq_heartbeat)")
c.execute("select last_seen, live_markets from liq_heartbeat"); print("liq_heartbeat (local):",c.fetchall())
PY
echo "== (c) football lines to the repo, then the other sports one at a time =="
cd /root/pe-sports/team
python3 - <<'PY' > /root/pe-queue/reports/fairprice_football_2026-11-09.md
import json, datetime
rows=[json.loads(l[7:]) for l in open('/root/pe-sports/team/fairprice_v1_football.log') if l.startswith('RESULT ')]
rows.sort(key=lambda r:-r['t'])
print(f"# Fair-price engine v1 — FOOTBALL (run 9 Nov 2026, job 544)\n\n{len(rows)} cells with n>=300 and >=50 each half. Rule: trade toward the in-sample fair price at the closing price, one tick adverse, 2% commission; IS = older half by date, OOS = newer half; control = side at random.\n")
print("| line | n | £/£10 | t | IS £/£10 | OOS £/£10 | control t |"); print("|---|---|---|---|---|---|---|")
for r in rows[:40]: print(f"| {r['name'][:80]} | {r['n']} | {r['mean_per10']:+.3f} | {r['t']} | {r['is_mean']:+.3f} | {r['oos_mean']:+.3f} | {r['control_t']} |")
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local()).cursor(); c.execute("select sport, market_type, band_lo, band_hi, side, n_is, n_oos, edge_is, edge_oos from fair_price_passed order by 1,2,3")
print("\n## Passed cells (the bot quotes only these)\n\n| sport | market | band | side | n IS | n OOS | edge IS | edge OOS |\n|---|---|---|---|---|---|---|---|")
for sp,mt,lo,hi,side,nis,noos,eis,eoos in c.fetchall(): print(f"| {sp} | {mt} | {float(lo):.2f}-{float(hi):.2f} | {side} | {nis} | {noos} | {float(eis):+.3f} | {float(eoos):+.3f} |")
PY
head -5 /root/pe-queue/reports/fairprice_football_2026-11-09.md
sed -i "s/con=psycopg2.connect(creds.pg_local(),sslmode='prefer')/con=psycopg2.connect(creds.pg_local(),sslmode='disable')/" fairprice_v0.py && python3 -m py_compile fairprice_v0.py && echo "engine reads local over a plain socket now"
pkill -f fairprice_v0.py; sleep 2
for sp in $(python3 -c "
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local()).cursor(); c.execute(\"select distinct sport from bf_hist_other where sport<>'Soccer'\"); print(' '.join(s.replace(' ','_') for (s,) in c.fetchall()))"); do
  S="${sp//_/ }"; echo "-- $S --"; FP_SPORTS="$S" timeout 5000 python3 fairprice_v0.py > "fairprice_v1_${sp}.log" 2>&1; echo "exit $? | RESULT lines $(grep -c '^RESULT' fairprice_v1_${sp}.log)"; grep -v '^RESULT' "fairprice_v1_${sp}.log" | tail -4
done
python3 /root/pe-sports/team/verifier_cells.py
cd /root/pe-queue && git add reports/fairprice_football_2026-11-09.md && git commit -q -m "545: football fair-price lines + passed cells to reports" && git pull -q --rebase && git push -q && echo "pushed reports/fairprice_football_2026-11-09.md"
echo "545 done"
