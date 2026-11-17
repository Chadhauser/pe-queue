#!/bin/bash
# 635 (Tue 17 Nov 2026, 07:20). Read only. 634: the half-time trigger (goal_alerts) fired 181 times 25 Oct - 7 Nov and none since;
# the monitor log shows "mon=0 ht=0" on every line, so no fixture is being monitored. Show how a fixture becomes "monitored",
# what feeds it, and every cron line paused by job 543 on 9 Nov. Report: reports/ht_trigger_635.md
R=/root/pe-queue/reports/ht_trigger_635.md; F=/root/pe-brain/repo/brain/monitor_ht.py
{ echo "# 635 — $(date -u '+%F %H:%M') UTC"; echo '```'
echo "--- all cron lines paused by 543"; crontab -l | grep -n "PAUSED-543"
echo "--- how mon/ht are counted"; grep -nE "mon=|'mon'|monitored|ht_fixtures|watchlist|prematch|pre_match|fav_price|af_fixtures|goal_signal_watchlist" $F | head -40
N=$(grep -nE "def (select|pick|get)_(monitored|fixtures|candidates)|def build_watch|def monitored" $F | head -1 | cut -d: -f1); echo "function at $N"; [ -n "$N" ] && sed -n "$N,$((N+45))p" $F
echo "--- the 25 Oct - 7 Nov alerts: stakes and real prices"
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("""SELECT strategy_id, count(*), avg(stake_gbp), sum(pnl_paper), count(real_price), count(*) FILTER (WHERE outcome ILIKE 'WIN%%')
             FROM goal_alerts WHERE sent_at>'2026-10-25' AND coalesce(alert_type,'')<>'BOOT_TEST' GROUP BY 1 ORDER BY 2 DESC""")
for r in c.fetchall(): print("  ",r)
c.execute("SELECT action, minute, score, stake_gbp, real_price, outcome, pnl_paper FROM goal_alerts WHERE sent_at>'2026-11-05' ORDER BY sent_at DESC LIMIT 6")
for r in c.fetchall(): print("  ",r)
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "635: why the HT trigger is starved" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
