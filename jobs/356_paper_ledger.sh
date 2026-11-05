#!/bin/bash
# 356: ONE LEDGER FOR EVERY PAPER / DRY BOT. 66 trade-shaped tables and no single view. This finds every table with a
# pnl-like column and a timestamp, and writes one row per table into local paper_ledger (table, n, first, last, n_7d,
# pnl_total, pnl_7d, per_10 (if a stake column exists), status) and prints it. Runs daily 06:40 via cron. Report only.
set -o pipefail
mkdir -p /root/pe-data
cat > /root/pe-data/paper_ledger.py <<'PY'
import sys,psycopg2,psycopg2.extras,datetime
sys.path.insert(0,'/root/pe-queue/runner'); import creds
R=psycopg2.connect(creds.pg_railway(), sslmode='require'); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout='120s'")
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
lc.execute("CREATE TABLE IF NOT EXISTS paper_ledger (run_at TIMESTAMPTZ, db TEXT, tbl TEXT, n BIGINT, first_ts TIMESTAMPTZ, last_ts TIMESTAMPTZ, n_7d BIGINT, pnl_total NUMERIC, pnl_7d NUMERIC, staked NUMERIC, per_10 NUMERIC, dry TEXT)")
rows=[]
for db,con,cur in (('railway',R,rc),('local',L,lc)):
    cur.execute("select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE' order by 1"); tabs=[r[0] for r in cur.fetchall()]
    for t in tabs:
        cur.execute("select column_name, data_type from information_schema.columns where table_name=%s",(t,)); cols={a:b for a,b in cur.fetchall()}
        pnl=next((c for c in ('pnl','pnl_per_10','pnl_gbp','profit','pnl_paper','pnl_real') if c in cols and cols[c] in ('numeric','double precision','real','integer','bigint')),None)
        ts=next((c for c in ('entry_ts','entered_at','opened_at','placed_at','sent_at','ts','logged_at','submitted','recorded_at','created_at','settled_at','exit_ts') if c in cols and cols[c].startswith('timestamp')),None)
        if not pnl or not ts: continue
        stake=next((c for c in ('stake','stake_gbp','size','lay_size','staked') if c in cols),None)
        dry='dry' if 'dry' in cols else ''
        try:
            cur.execute(f"select count(*), min({ts}), max({ts}), count(*) filter (where {ts}>now()-interval '7 days'), round(sum(coalesce({pnl},0))::numeric,2), round(sum(coalesce({pnl},0)) filter (where {ts}>now()-interval '7 days')::numeric,2), "+(f"round(sum(coalesce({stake},0))::numeric,2)" if stake else "null")+f" from {t}")
            n,f,l,n7,p,p7,st=cur.fetchone()
            if not n: continue
            per10=round(float(p)/float(st)*10,3) if (st and float(st)>0 and p is not None) else None
            if dry:
                cur.execute(f"select string_agg(distinct dry::text, ',') from {t}"); dry=cur.fetchone()[0]
            rows.append((datetime.datetime.now(datetime.timezone.utc),db,t,n,f,l,n7,p,p7,st,per10,dry))
        except Exception as e:
            con.rollback(); print("skip",t,str(e)[:60])
psycopg2.extras.execute_values(lc,"INSERT INTO paper_ledger VALUES %s",rows)
print(f"{'db':8s}{'table':28s}{'n':>7s}{'first':>11s}{'last':>11s}{'n7d':>5s}{'pnl':>10s}{'pnl7d':>9s}{'per£10':>8s} dry")
for r in sorted(rows,key=lambda x:(x[1],-(x[6] or 0))):
    print(f"{r[1]:8s}{r[2]:28s}{r[3]:>7}{str(r[4])[:10]:>11s}{str(r[5])[:10]:>11s}{r[6]:>5}{str(r[7]):>10s}{str(r[8]):>9s}{str(r[10]):>8s} {r[11]}")
PY
python3 -m py_compile /root/pe-data/paper_ledger.py || exit 1
( crontab -l 2>/dev/null | grep -v paper_ledger; echo "40 6 * * * cd /root/pe-data && python3 paper_ledger.py >> ledger.log 2>&1" ) | crontab -
cd /root/pe-data && python3 paper_ledger.py
