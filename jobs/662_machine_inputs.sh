#!/bin/bash
# 662 (Thu 19 Nov 2026, 07:20). Read only. Inputs for the one nightly machine: columns of every paper table, test scripts present,
# and what 661's hand-run of the keepalives started (desk, sports_team, stats_collector, hist) - must be paper / read only.
R=/root/pe-queue/reports/machine_inputs_662.md
T=/root/pe-sports/team
{ echo "# 662 — $(date -u '+%F %H:%M') UTC"; echo '```'
ls -la /root/REAL_MONEY_OFF
echo "== started by 661"; ps -eo pid,etime,cmd | grep -E 'desk.py|sports_team.py|stats_collector|keepalive_hist|duka' | grep -v grep | cut -c1-150
for f in /root/pe-sports/desk/desk.py $T/sports_team.py; do echo "-- $f"; head -6 $f | cut -c1-200; grep -nE 'placeOrders|place_order' $f | head -3; done
echo "== test scripts"; cd $T; for f in *.py; do printf '%s | %s | %s\n' "$f" "$(date -r $f +%F)" "$(grep -m1 -oE '"""[^"]{0,140}' $f | cut -c4-)"; done
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
for t in ['bookie_paper','small_bites_paper','coherence_paper','v3_paper','v3_snap','fair_price_passed','fair_price_blocked','goal_alerts','goal_live_predictions','ht_real_price','ht_reprice']:
    c.execute("SELECT string_agg(column_name||':'||data_type, ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name=%s",(t,)); r=c.fetchone()[0]
    if r:
        c.execute(f"SELECT count(*) FROM {t}"); print(f"{t} ({c.fetchone()[0]} rows): {r}")
c.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND (table_name LIKE '%paper%' OR table_name LIKE '%reprice%' OR table_name LIKE 'ht_%' OR table_name LIKE 'machine%')"); print("paper-ish tables:", [r[0] for r in c.fetchall()])
c.execute("SELECT * FROM small_bites_paper LIMIT 2"); print("small_bites sample:", c.fetchall())
c.execute("SELECT * FROM bookie_paper ORDER BY 1 DESC LIMIT 1"); print("bookie sample:", c.fetchall())
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "662: machine inputs" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
