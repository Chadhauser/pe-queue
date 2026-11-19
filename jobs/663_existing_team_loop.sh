#!/bin/bash
# 663 (Thu 19 Nov 2026, 07:30). Read only. sports_team.py (5 Nov) is already a continuous Proposer/Verifier loop with a scoreboard.
# Before building "the one machine", read it so the machine IS that loop extended, not a second one. Plus: which paper tables are live.
R=/root/pe-queue/reports/team_loop_663.md
T=/root/pe-sports/team
{ echo "# 663 — $(date -u '+%F %H:%M') UTC"; echo '```'
wc -l $T/sports_team.py $T/friday_email.py; ls -la $T/hypotheses.json $T/scoreboard.* 2>&1
echo "== sports_team.py"; cat $T/sports_team.py | cut -c1-230
echo "== hypotheses.json (first 80 lines)"; head -80 $T/hypotheses.json | cut -c1-230
echo "== scoreboard.md"; head -60 $T/scoreboard.md | cut -c1-230
echo "== sports_team log tail"; tail -15 $(ls -t $T/sports_team*.log $T/team*.log 2>/dev/null | head -1) 2>/dev/null | cut -c1-200
echo "== friday_email.py head + cron"; head -30 $T/friday_email.py | cut -c1-200; crontab -l | grep -iE 'friday|team' | cut -c1-200
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='120s'")
c.execute("""SELECT c.table_name, string_agg(c.column_name, ',') FROM information_schema.columns c JOIN information_schema.tables t USING (table_name)
             WHERE t.table_schema='public' AND c.data_type LIKE 'timestamp%%' AND (c.table_name LIKE '%%paper%%' OR c.table_name IN ('ht_family_v1','paper_ledger','paper_settlements')) GROUP BY 1""")
for t, cols in c.fetchall():
    col = cols.split(',')[0]
    try: c.execute(f"SELECT count(*), max({col}) FROM {t} WHERE {col} > now() - interval '7 days'"); print(f"{t}.{col}: last 7 days", c.fetchone())
    except Exception as e: c.connection.rollback(); print(t, 'err', str(e)[:80])
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "663: existing team loop" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
