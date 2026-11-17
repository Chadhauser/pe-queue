#!/bin/bash
# 639 (Tue 17 Nov 2026, 07:10). Peter approved in chat 07:09 ("yes to query guard"). Was drafted as 625. 624 found it: /root/pe-guard/railway_guard.py (cron every minute) terminates any read query
# older than LIMIT_S. Built to protect the web pages from runaway queries; after the move it also kills our own analysis
# on the local DB (the in-play engine at ~254 s, probably 613 too). Fix:
#  1. guard: connections whose application_name starts "batch" get a 3-hour cap instead of LIMIT_S. Everything else unchanged.
#  2. the queue runner exports PGAPPNAME=batch_queue (runner.sh, same commit), so queue jobs and their background children are batch.
#  3. relaunch 613 if the guard killed it; run the in-play engine for all five sports + the verifier in the background
#     (reports/inplay_engine.md, pushed without GITHUB_TOKEN).
export PGAPPNAME=batch_639
R=/root/pe-queue/reports/fix_639.md
G=/root/pe-guard/railway_guard.py
{
echo "# 625 — $(date -u '+%F %H:%M') UTC"; echo
echo "## 1. guard"
echo '```'; sed -n 1,9p $G; echo '```'
cp $G $G.bak_639
python3 - "$G" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
old="AND now()-query_start > interval '%s seconds'"
new="AND now()-query_start > (CASE WHEN application_name LIKE 'batch%%' THEN interval '10800 seconds' ELSE interval '%s seconds' END)"
if new in s: print("already patched")
elif old in s: open(p,'w').write(s.replace(old,new)); print("patched")
else: print("PATTERN NOT FOUND - not patched")
PY
python3 -m py_compile $G && echo compiles || { cp $G.bak_639 $G; echo "compile failed - restored"; }
timeout 50 python3 $G; echo "guard run exit $?"
echo "guard kills today:"; echo '```'; grep "$(date -u +%F)" /root/pe-guard/railway_guard.log | tail -8 | cut -c1-220; echo '```'
echo
echo "## 2. 613"
if pgrep -f execution_methods.py >/dev/null; then echo "613 still running"; pgrep -af execution_methods.py | grep -v pgrep | head -1; else
  echo "613 not running; log tail:"; echo '```'; tail -4 /root/pe-sports/team/execution_methods.log; echo '```'
  if [ ! -f /root/pe-queue/reports/execution_methods.md ]; then
    cd /root/pe-sports/team && PGAPPNAME=batch_613 nohup setsid bash -c 'nice -n 10 timeout 10800 python3 execution_methods.py > execution_methods.log 2>&1; cd /root/pe-queue && git add reports/execution_methods.md && git commit -qm "execution methods on the recorded ladder" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q' >/dev/null 2>&1 < /dev/null &
    sleep 15; echo "relaunched: $(pgrep -f execution_methods.py | wc -l) process(es)"
  fi
fi
echo
echo "## 3. in-play engine + verifier, background"
cd /root/pe-sports/team
cat > /root/pe-sports/team/run_inplay_639.sh <<'SH'
#!/bin/bash
export PGAPPNAME=batch_inplay
cd /root/pe-sports/team; O=/root/pe-queue/reports/inplay_engine.md
{ echo "# In-play fair-price engine + verifier — started $(date -u '+%F %H:%M') UTC (job 639)"; echo; echo '```'
for S in Soccer Tennis Cricket "Horse Racing" "Greyhound Racing"; do
  FP_SPORTS="$S" timeout 7200 nice -n 10 python3 fairprice_inplay.py > "fairprice_inplay_${S// /_}.log" 2>&1
  echo "$S exit $? RESULT lines $(grep -c ^RESULT fairprice_inplay_${S// /_}.log)"; tail -2 "fairprice_inplay_${S// /_}.log" | cut -c1-200
done; echo '```'; echo; echo "## Verifier"; echo '```'
python3 verifier_cells.py 2>&1 | grep -v Deprecation | tail -40; echo '```'; echo "finished $(date -u '+%F %H:%M') UTC"; } > $O 2>&1
cd /root/pe-queue && git add $O && git commit -qm "in-play engine + verifier (639)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
SH
chmod +x run_inplay_639.sh
if pgrep -f fairprice_inplay.py >/dev/null; then echo "engine already running"; else
  nohup setsid ./run_inplay_639.sh >/dev/null 2>&1 < /dev/null & sleep 300
  echo "after 5 min: engine processes $(pgrep -f fairprice_inplay.py | wc -l)"; tail -3 fairprice_inplay_Soccer.log | cut -c1-200
fi
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "639: guard exempts batch, in-play engine relaunched" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "639 done"
