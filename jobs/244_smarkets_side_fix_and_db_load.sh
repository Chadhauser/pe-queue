#!/bin/bash
# 244: (a) Smarkets rows now flow (243) but back/lay are inverted: on Smarkets a "bid" is money wanting to BACK (so it is the price I can
# LAY at) and an "offer" is money wanting to LAY (the price I can BACK at). Swap. (b) Railway refused connections twice this morning:
# count connections by application and kill nothing — just report, plus the biggest tables and today's row counts for stream_ticks and
# xx_tape so retention can be set.
set -e
python3 - <<'PY'
p='/root/pe-xx/xx_recorder.py'; s=open(p).read(); n=0
old="""                bp=(10000/bids[0]['price']) if bids else None; bs=(bids[0]['quantity']/10000) if bids else None
                lp=(10000/offers[0]['price']) if offers else None; ls=(offers[0]['quantity']/10000) if offers else None"""
new="""                lp=(10000/bids[0]['price']) if bids else None; ls=(bids[0]['quantity']/10000) if bids else None        # bids = backers -> I can LAY here
                bp=(10000/offers[0]['price']) if offers else None; bs=(offers[0]['quantity']/10000) if offers else None  # offers = layers -> I can BACK here"""
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("smarkets sides swapped")
PY
python3 -m py_compile /root/pe-xx/xx_recorder.py; pkill -f xx_recorder.py || true; sleep 3; nohup /root/pe-xx/keepalive.sh >/dev/null 2>&1 &
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("UPDATE xx_tape SET back_px=lay_px, lay_px=back_px, back_sz=lay_sz, lay_sz=back_sz WHERE exchange='smarkets'"); print("historic smarkets rows swapped:",k.rowcount); k.connection.commit()
k.execute("SELECT coalesce(application_name,'?') app, state, count(*) FROM pg_stat_activity WHERE datname=current_database() GROUP BY 1,2 ORDER BY 3 DESC"); print("connections:",k.fetchall())
k.execute("SHOW max_connections"); print("max_connections:",k.fetchone())
k.execute("SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 8"); print("biggest tables:",k.fetchall())
k.execute("SELECT (SELECT count(*) FROM stream_ticks WHERE ts_recv>now()-interval '24 hours') stream_24h, (SELECT count(*) FROM xx_tape WHERE ts>now()-interval '24 hours') xx_24h, (SELECT count(*) FROM liq_sample WHERE ts>now()-interval '24 hours') liq_24h"); print("rows/24h:",k.fetchone())
PY
sleep 60; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT event_name, sel_name, back_px, lay_px FROM xx_tape WHERE exchange='smarkets' AND back_px IS NOT NULL AND lay_px IS NOT NULL ORDER BY ts DESC LIMIT 4"); [print("  ",r) for r in k.fetchall()]
PY
