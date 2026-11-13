#!/bin/bash
# 560 (Fri 13 Nov 2026, 08:40). BREAK CHECK AND RECOVERY. Evidence from the repo this morning: no Watchman report since 16:17 UTC
# yesterday, and the fin scoreboard's database heartbeat frozen at 22:40 UTC yesterday while 557/558 (table restores + the pandas replay)
# were running. None of 557/558/559 pushed its report. This job: (1) says what is down, read live; (2) brings PostgreSQL back if it is
# down (restart only, nothing rebuilt); (3) writes everything it saw to reports/break_2026-11-13.md and pushes it, because the
# Watchman is silent; (4) emails Peter ONE line about the break the day it happened (his 13 Nov order), via the operators' mailer.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
R=/root/pe-queue/reports/break_2026-11-13.md
{
echo "# Break report — $(date -u '+%Y-%m-%d %H:%M') UTC (job 560)"; echo
echo "## Box"; uptime; free -m | head -2; df -h / | tail -1; echo
echo "## PostgreSQL"; systemctl is-active postgresql; pg_isready; echo "last OOM/kill lines (dmesg):"; dmesg -T 2>/dev/null | grep -i "out of memory\|killed process\|oom" | tail -4; echo
echo "## Jobs 556-559 (runner state and log tails)"
for j in 556_gate_reality 557_ceo_orders_1_to_3 558_replay_inplay_xx 559_proof_gate_counter; do
  s="not started"; [ -f /root/pe-queue-state/done/$j ] && s="done"; [ -f /root/pe-queue-state/waiting/$j ] && s="waiting"
  echo "### $j — $s"; [ -f /root/pe-queue-logs/$j.log ] && { grep -m1 "^exit=" /root/pe-queue-logs/$j.log; tail -12 /root/pe-queue-logs/$j.log | cut -c1-300; }; echo
done
echo "## Still running from those jobs"; pgrep -fa "replay_inplay_xx|fairprice_v0|zstdcat" | cut -c1-150 || echo none; echo
echo "## Watchman"; ls -t /root/pe-watchman/runs 2>/dev/null | head -3; tail -5 "/root/pe-watchman/runs/$(ls -t /root/pe-watchman/runs 2>/dev/null | head -1)" 2>/dev/null | cut -c1-300; crontab -l | grep -i watchman | cut -c1-160; echo
} > $R 2>&1
DOWN=0; pg_isready >/dev/null 2>&1 || DOWN=1
if [ $DOWN = 1 ]; then
  echo "## Recovery" >> $R
  pkill -f replay_inplay_xx.py; pkill -f fairprice_v0.py; sleep 3
  systemctl restart postgresql || pg_ctlcluster 18 main restart; sleep 10
  { systemctl is-active postgresql; pg_isready; } >> $R 2>&1
  echo "PostgreSQL restarted at $(date -u +%H:%M) UTC; replay/engine processes killed first; nothing rebuilt" >> $R
fi
echo "## Live after this job" >> $R
python3 - >> $R 2>&1 <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='60s'")
    for name,sql in [("stream_ticks rows last 15 min","select count(*) from stream_ticks where ts_recv>now()-interval '15 minutes'"),
                     ("liq_sample rows last 15 min","select count(*) from liq_sample where ts>now()-interval '15 minutes'"),
                     ("xx_tape rows last 15 min","select count(*) from xx_tape where ts>now()-interval '15 minutes'"),
                     ("bookie taker bets (all / settled)","select count(*), count(*) filter (where status='settled') from bookie_paper where version='v2' and fill_kind='taker'"),
                     ("job_results 556-559","select job, status, exit_code, finished from job_results where job ~ '^55[6-9]' order by job"),
                     ("goal tables present","select string_agg(t,', ') from (select unnest(array['goal_alerts','goal_live_predictions','goal_timeline','m1_alerts','af_fixtures','af_events']) t) x where to_regclass(t) is not null")]:
        try: c.execute(sql); print(f"- {name}: {c.fetchall()}")
        except Exception as e: c.connection.rollback(); print(f"- {name}: ERR {str(e)[:120]}")
except Exception as e: print("database still unreachable:",str(e)[:200])
PY
cd /root/pe-queue && git add reports/break_2026-11-13.md && git commit -q -m "560: break report 13 Nov" && git pull -q --rebase && git push -q && echo pushed
# the one-line break email to Peter (his 13 Nov order: any break reported the day it happens)
if [ $DOWN = 1 ] || ! ls /root/pe-watchman/runs/*$(date -u +%F)* >/dev/null 2>&1; then
  WHAT="the database was down (restarted $(date -u +%H:%M) UTC by job 560; cause being read from its logs)"; [ $DOWN = 0 ] && WHAT="the hourly Watchman report has not run since 16:17 UTC yesterday (database up; being read)"
  cd /root/operators && set -a && . ./.env && set +a && PYTHONPATH=/root/operators python3 - "$WHAT" <<'PY'
import sys; from engines.mail import send_text
what=sys.argv[1]
body=f"Break today, 13 November: {what}. No real money is at risk; nothing bets with real money. The full reading is in the repository as reports/break_2026-11-13.md."
mid,refused,found=send_text("Trading estate: break today, 13 November", body, "peter@edwardsbros.co.uk")
print("break email sent:", "in Sent" if found else "NOT confirmed in Sent", "| refused:", refused or "none")
PY
fi
echo "560 done"
