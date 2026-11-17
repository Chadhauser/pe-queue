#!/bin/bash
# 627 (Tue 17 Nov 2026, 06:55). Read only. Peter: "are you using the goal signal?" Current numbers for the two lines frozen in on 13 Nov:
# goal signal alerts since the 13 Nov restore (sent, scored, won, paper £) and the post-goal fade forward paper (count towards 100, £,
# each half). Also why the scoreboard calls goal-signal alerts BROKEN since 7 Nov while the 13 Nov email counted 25 alerts.
# Report: reports/goal_fade_627.md
export PGAPPNAME=batch_627
R=/root/pe-queue/reports/goal_fade_627.md
T=/root/pe-sports/team
{
echo "# Goal signal and post-goal fade — $(date -u '+%F %H:%M') UTC"; echo
echo "## How the Friday email counts them (friday_email.py, queries only)"; echo '```'
grep -nE "SELECT|FROM|WHERE|alert|fade|goal" $T/friday_email.py | head -60
echo '```'
echo "## goal_alert_mail.py (what it reads)"; echo '```'; grep -nE "SELECT|FROM|INSERT|UPDATE" $T/goal_alert_mail.py | head -15; tail -5 $T/goal_alert_mail.log 2>/dev/null; echo '```'
echo "## Tables"; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout='120s'")
c.execute("""SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND (table_name ILIKE '%goal%' OR table_name ILIKE '%alert%' OR table_name ILIKE '%fade%' OR table_name ILIKE 'm1_%' OR table_name ILIKE 'h0%') ORDER BY 1""")
for (t,) in c.fetchall():
    try:
        c.execute(f'SELECT count(*) FROM "{t}"'); n=c.fetchone()[0]
        c.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s AND data_type LIKE 'timestamp%%' ORDER BY ordinal_position",(t,)); tc=[r[0] for r in c.fetchall()]
        last=''
        if tc: c.execute(f'SELECT max("{tc[0]}") FROM "{t}"'); last=f'{tc[0]} max {c.fetchone()[0]}'
        print(f"{t}: {n} rows; {last}")
    except Exception as e: print(t,'err',str(e)[:80])
PY
echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "627: goal signal and fade numbers" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "627 done"
