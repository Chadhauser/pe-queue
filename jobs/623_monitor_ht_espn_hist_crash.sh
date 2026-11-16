#!/bin/bash
# 623 (Mon 16 Nov 2026, 19:20). From fix_622.md. Report: reports/fix_623.md
#  1. monitor_ht: calibrate_goal_model.calibration_bands builds SQL with "% hours_back" but its band labels hold a bare %
#     ('1. <30%' ...), so Python's % formatting throws. Escape those labels as %% (output identical), restart monitor_ht.
#     Reporting/calibration only - the frozen goal-signal rules are untouched.
#  2. ESPN stats recorder: its keepalive cron line is still "#PAUSED-543" from the migration. It is a data collector,
#     so un-pause that one line (only if /root/pe-stats has no STOPPED marker) and run it once.
#     pe-xg (xg, s9, late_over, lo_live) stays as it is: STOPPED since 9 Nov and REAL_MONEY_OFF.
#  3. The in-play engine's first query on bf_hist_other makes the postgres backend die. Re-run that query alone and read the
#     postgres log (as text) for the crash reason.
R=/root/pe-queue/reports/fix_623.md
F=/root/pe-brain/repo/brain/calibrate_goal_model.py
{
echo "# Fix 623 — $(date -u '+%F %H:%M') UTC"; echo
echo "## 1. monitor_ht % bug"
cp -n $F $F.bak_623
python3 - "$F" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
i=s.find('def calibration_bands'); j=s.find('\ndef ',i+10); j=len(s) if j<0 else j
body=s[i:j]
new=re.sub(r"(THEN '\d\. [^']*?\d)%'", r"\1%%'", body).replace("ELSE '5. 60%+'","ELSE '5. 60%%+'")
open(p,'w').write(s[:i]+new+s[j:]); print("labels changed:", body!=new)
PY
/root/pe-brain/venv/bin/python -m py_compile $F && echo compiles
( source /root/pe-brain/env.sh; cd /root/pe-brain/repo/brain && /root/pe-brain/venv/bin/python -c "
import calibrate_goal_model as m
try: print('calibration_bands ok:', str(m.calibration_bands(30))[:150])
except Exception as e: print('calibration_bands:', type(e).__name__, str(e)[:150])
" 2>&1 | tail -3 )
pkill -f 'brain/monitor_ht.py'; sleep 40
echo "monitor_ht processes: $(pgrep -f 'brain/monitor_ht.py' | wc -l)"
echo '```'; tail -5 /root/pe-brain/monitor_ht.log; echo '```'
echo
echo "## 2. ESPN recorder"
ls -la /root/pe-stats/ 2>&1 | head -15
if [ -f /root/pe-stats/STOPPED ]; then echo "STOPPED marker present: $(cat /root/pe-stats/STOPPED) - left alone"; else
  crontab -l > /root/.cache_cron_623.bak
  crontab -l | sed 's|^#PAUSED-543 \(\* \* \* \* \* /root/pe-stats/keepalive_espn.sh\)|\1|' | crontab -
  crontab -l | grep -n keepalive_espn
  cat /root/pe-stats/keepalive_espn.sh; bash /root/pe-stats/keepalive_espn.sh; sleep 60
  echo "espn processes: $(pgrep -af espn | grep -v pgrep | wc -l)"
  pgrep -af espn | grep -v pgrep | head -3
  for l in $(ls -t /root/pe-stats/*.log 2>/dev/null | head -2); do echo "== $l"; tail -5 $l; done
fi
echo
echo "## 3. bf_hist_other backend crash"
cd /root/pe-sports/team
T0=$(date '+%Y-%m-%d %H:%M')
python3 - <<'PY' 2>&1 | tail -6
import sys,time; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
for q in ["SELECT pg_size_pretty(pg_total_relation_size('bf_hist_other'))",
          "SELECT count(*) FROM (SELECT 1 FROM bf_hist_other LIMIT 1000) x",
          "EXPLAIN SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1",
          "SET work_mem='512MB'; SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"]:
    t=time.time()
    try:
        c.execute(q); r=c.fetchall() if c.description else None; print("OK",round(time.time()-t,1),"s",q[:60],"->",str(r)[:300])
    except Exception as e:
        print("FAIL",round(time.time()-t,1),"s",q[:60],"->",str(e)[:200]); break
PY
sleep 5
echo "postgres log since $T0 (server-local time):"; echo '```'
grep -a -A3 -E 'terminated by signal|PANIC|could not read|invalid page|corrupt|out of memory|server process' /var/log/postgresql/postgresql-18-main.log | grep -a "$(date '+%Y-%m-%d')" | tail -20
echo '```'
echo "same, at the 615 and 619b failure times (16:0x and 17:1x UTC):"; echo '```'
grep -a -E 'terminated by signal|PANIC|out of memory|server process' /var/log/postgresql/postgresql-18-main.log | grep -a "$(date '+%Y-%m-%d')" | tail -10
echo '```'
echo "kernel:"; echo '```'; journalctl -k --since today 2>/dev/null | grep -iE 'oom|killed process|segfault' | tail -5; echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "623: monitor_ht fix, espn recorder, hist crash" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "623 done"
