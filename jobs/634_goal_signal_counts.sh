#!/bin/bash
# 634 (Tue 17 Nov 2026, 07:15). Read only. 633: fired goal signals are stored as goal_live_predictions rows with alert_sent=true
# (the copilot's /signals page reads them there); goal_alerts only holds the half-time trigger. Count fired signals per day since
# 1 Nov with their settlement and paper result, and check whether the duplicate-key write failures are still happening now.
R=/root/pe-queue/reports/goal_counts_634.md
{ echo "# 634 — $(date -u '+%F %H:%M') UTC"; echo '```'
echo "PRED WRITE FAIL in the last 3000 log lines: $(tail -3000 /root/pe-brain/monitor_ht.log | grep -c 'PRED WRITE FAIL')"
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='200s'")
c.execute("SELECT column_name FROM information_schema.columns WHERE table_name='goal_live_predictions' ORDER BY ordinal_position"); cols=[r[0] for r in c.fetchall()]; print("columns:",cols)
pn=[x for x in ('pnl_paper','pnl','paper_pnl') if x in cols]; oc=[x for x in ('outcome','result','goal_within_15') if x in cols]
sel=f"date(captured_at), count(*), count(*) FILTER (WHERE settled)" + (f", sum({pn[0]})" if pn else "") + (f", count(*) FILTER (WHERE {oc[0]}::text IN ('true','WIN','WON','win'))" if oc else "")
c.execute(f"SELECT {sel} FROM goal_live_predictions WHERE alert_sent AND captured_at>'2026-11-01' GROUP BY 1 ORDER BY 1"); print("fired signals per day (date, fired, settled, pnl, won):")
for r in c.fetchall(): print("  ",r)
c.execute("SELECT date(sent_at), count(*), count(*) FILTER (WHERE settled), sum(pnl_paper) FROM goal_alerts WHERE sent_at>'2026-10-25' AND coalesce(alert_type,'')<>'BOOT_TEST' GROUP BY 1 ORDER BY 1"); print("goal_alerts per day:"); [print("  ",r) for r in c.fetchall()]
c.execute("SELECT date(sent_at), count(*), count(*) FILTER (WHERE settled), sum(pnl_paper) FROM goal_advisories WHERE sent_at>'2026-11-01' GROUP BY 1 ORDER BY 1"); print("goal_advisories per day:"); [print("  ",r) for r in c.fetchall()]
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "634: goal signal counts" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
