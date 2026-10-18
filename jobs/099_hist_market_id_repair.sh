#!/bin/bash
# 099: BUG FIX in the history loader (064/066/088): market_id was taken as basename.split('.')[0] of files named "1.2345678.bz2",
# so EVERY loaded market got market_id = "1" (found by 097: 9,630 tennis "selections" in one "market"). Loader fixed in 088 (now
# "1.2345678"). Existing rows repaired here with a deterministic key market_type|event_name|market_time (unique per market for
# MATCH_ODDS / WIN; soccer MO vs OU25 split by market_type). Done in sport-sized chunks to stay inside the statement timeout.
python3 - <<'PY'
import sys, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='1500s'")
cur.execute("SELECT sport, count(*) FROM bf_hist_other WHERE market_id='1' GROUP BY 1"); print("rows to repair by sport:",cur.fetchall(),flush=True)
cur.execute("SELECT DISTINCT sport FROM bf_hist_other WHERE market_id='1'")
for (sp,) in cur.fetchall():
    cur.execute("UPDATE bf_hist_other SET market_id = market_type||'|'||event_name||'|'||market_time::text WHERE sport=%s AND market_id='1'",(sp,)); print("repaired",sp,cur.rowcount,flush=True)
cur.execute("SELECT sport, count(DISTINCT market_id), count(*) FROM bf_hist_other GROUP BY 1"); print("markets per sport now:",cur.fetchall())
cur.execute("ANALYZE bf_hist_other")
PY
