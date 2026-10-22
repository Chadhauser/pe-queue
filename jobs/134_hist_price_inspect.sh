#!/bin/bash
# 134: 129 showed bf_hist_other soccer = Jul-Sep 2026 only (3 months). The two-season soccer history (Aug 2024-Jun 2026, 7 market
# types) lives in bf_hist_price (loader note, 088). Inspect it so LTD classic + Poisson can be re-run on the right table.
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='600s'")
cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name='bf_hist_price' ORDER BY ordinal_position"); print("bf_hist_price columns:",cur.fetchall())
cur.execute("SELECT pg_size_pretty(pg_total_relation_size('bf_hist_price'))"); print("size:",cur.fetchone())
cur.execute("SELECT * FROM bf_hist_price LIMIT 3"); print("sample:",cur.fetchall())
cur.execute("SELECT market_type, count(*) FROM bf_hist_price GROUP BY 1 ORDER BY 2 DESC"); print("by market_type:",cur.fetchall())
try:
    cur.execute("SELECT date_trunc('month',ts)::date, count(DISTINCT market_id) FROM bf_hist_price WHERE market_type='MATCH_ODDS' GROUP BY 1 ORDER BY 1"); print("MO markets by month:",cur.fetchall())
except Exception as e: print("month query:",repr(e)[:150])
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'bf_hist%'"); print("bf_hist tables:",cur.fetchall())
for t in ('bf_hist_markets','bf_hist_events','bf_hist_meta'):
    try: cur.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name='{t}'"); c=cur.fetchall(); print(t,c) if c else None
    except Exception: pass
cur.execute("SELECT event_name FROM bf_hist_price WHERE market_type='MATCH_ODDS' GROUP BY 1 ORDER BY random() LIMIT 10"); print("event names:",[r[0] for r in cur.fetchall()])
cur.execute("SELECT DISTINCT league_code FROM football_matches WHERE date>'2024-08-01'"); print("fm leagues since Aug 2024:",[r[0] for r in cur.fetchall()])
PY
