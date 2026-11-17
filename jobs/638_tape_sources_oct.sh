#!/bin/bash
# 638 (Tue 17 Nov 2026, 07:50). Read only. 637 priced 0 of 181 half-time alerts: local liq_sample only starts 12 Nov. Find every place
# the 25 Oct - 7 Nov in-play over/under prices still live: archive files, and the date range + markets of each in-play table.
R=/root/pe-queue/reports/tape_sources_638.md
{ echo "# 638 — $(date -u '+%F %H:%M') UTC"; echo '```'
for d in /root/pe-archive/*/; do n=$(ls $d | wc -l); echo "$d files $n first $(ls $d | head -1) last $(ls $d | tail -1)"; done
ls -la /root/pe-archive/ | head -20
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='200s'")
for t,ts,extra in [('liq_sample','ts',"mkt"),('ip_tape','ts',None),('liq_goal_depth','goal_ts',None),('xx_tape','ts',"exchange"),('bf_price_log',None,None),('liq_sample_archive',None,None)]:
    try:
        c.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position",(t,)); cols=[r[0] for r in c.fetchall()]
        if not cols: print(t,"no such table"); continue
        tc=ts or next((x for x in cols if x in ('ts','ts_recv','captured_at','logged_at','created_at')),None)
        c.execute(f'SELECT min("{tc}"), max("{tc}") FROM "{t}"'); mn,mx=c.fetchone(); print(t, cols[:14], "range", mn, mx)
        mk=next((x for x in ('mkt','market_type','market_name') if x in cols),None)
        if mk:
            c.execute(f"""SELECT "{mk}", count(*) FROM "{t}" WHERE "{tc}" BETWEEN '2026-10-31 15:00' AND '2026-10-31 17:00' GROUP BY 1 ORDER BY 2 DESC LIMIT 8"""); print("   31 Oct 15-17h by market:", c.fetchall())
    except Exception as e: print(t,"err",str(e)[:90]); c.connection.rollback()
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "638: tape sources for late Oct" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
