#!/bin/bash
# 245 (244 re-run; the exact-text anchor failed because the live recorder file is indented differently — regex on the two assignments):
# Smarkets back/lay are inverted in the recorder: a "bid" is money wanting to BACK (price I can LAY at), an "offer" is money wanting
# to LAY (price I can BACK at). Swap in code and in the stored rows. Then the DB load report (Railway refused connections twice today).
set -e
python3 - <<'PY'
import re
p='/root/pe-xx/xx_recorder.py'; s=open(p).read()
a=re.search(r"bp=\(10000/bids\[0\]\['price'\]\) if bids else None; bs=\(bids\[0\]\['quantity'\]/10000\) if bids else None",s)
b=re.search(r"lp=\(10000/offers\[0\]\['price'\]\) if offers else None; ls=\(offers\[0\]\['quantity'\]/10000\) if offers else None",s)
assert a and b, "assignments not found: "+str([l.strip()[:120] for l in s.splitlines() if 'bids[0]' in l or 'offers[0]' in l][:4])
s=s.replace(a.group(0),"lp=(10000/bids[0]['price']) if bids else None; ls=(bids[0]['quantity']/10000) if bids else None   # bids = backers -> I can LAY")
s=s.replace(b.group(0),"bp=(10000/offers[0]['price']) if offers else None; bs=(offers[0]['quantity']/10000) if offers else None   # offers = layers -> I can BACK")
open(p,'w').write(s); print("smarkets sides swapped")
PY
python3 -m py_compile /root/pe-xx/xx_recorder.py; pkill -f xx_recorder.py || true; sleep 3; nohup /root/pe-xx/keepalive.sh >/dev/null 2>&1 &
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("UPDATE xx_tape SET back_px=lay_px, lay_px=back_px, back_sz=lay_sz, lay_sz=back_sz WHERE exchange='smarkets' AND ts<now()"); print("historic smarkets rows swapped:",k.rowcount)
k.execute("SELECT coalesce(application_name,'?') app, state, count(*) FROM pg_stat_activity WHERE datname=current_database() GROUP BY 1,2 ORDER BY 3 DESC"); print("connections:",k.fetchall())
k.execute("SHOW max_connections"); print("max_connections:",k.fetchone())
k.execute("SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 8"); print("biggest tables:",k.fetchall())
k.execute("SELECT (SELECT count(*) FROM stream_ticks WHERE ts_recv>now()-interval '24 hours') stream_24h, (SELECT count(*) FROM xx_tape WHERE ts>now()-interval '24 hours') xx_24h, (SELECT count(*) FROM liq_sample WHERE ts>now()-interval '24 hours') liq_24h, pg_size_pretty(pg_database_size(current_database())) db"); print("rows/24h + db size:",k.fetchone())
PY
sleep 60; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT event_name, sel_name, back_px, lay_px FROM xx_tape WHERE exchange='smarkets' AND back_px IS NOT NULL AND lay_px IS NOT NULL ORDER BY ts DESC LIMIT 4"); [print("  ",r) for r in k.fetchall()]
PY
