#!/bin/bash
# 258: the history's strongest lay-Over cells are xG-conditioned (OPENxg: <=1 goal AND xG total >= 1.0/1.5 -> +1.2 to +2.4/£10,
# t 6-8, n 700-2,700) while the live bot ignores xG. Record h_xg/a_xg (API-Football, ip_stats) and ESPN shots-on-target at entry
# on every paper trade so the book can be sliced xG>=1.0 / <1.0 at the 40-trade gate instead of starting a second book.
set -e
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("ALTER TABLE late_over_paper ADD COLUMN IF NOT EXISTS h_xg NUMERIC, ADD COLUMN IF NOT EXISTS a_xg NUMERIC, ADD COLUMN IF NOT EXISTS h_sot INT, ADD COLUMN IF NOT EXISTS a_sot INT"); print("columns ok")
PY
python3 - <<'PY'
p='/root/pe-xg/late_over_paper.py'; s=open(p).read()
old='cur.execute("INSERT INTO late_over_paper (ou_market_id,mo_market_id,event_name,competition,entry_ts,minute,lay_px,lay_sz,goals,goal_src) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(mid,mo,ev,comp,ts,mn,lp,lsz,g,src))'
new='''cur.execute("SELECT h_xg, a_xg FROM ip_stats WHERE market_id=%s AND (h_xg IS NOT NULL OR a_xg IS NOT NULL) ORDER BY ts DESC LIMIT 1",(mo,)); _x=cur.fetchone() or (None,None)
            cur.execute("SELECT h_sot, a_sot FROM espn_stats WHERE market_id=%s ORDER BY ts DESC LIMIT 1",(mo,)); _e=cur.fetchone() or (None,None)
            cur.execute("INSERT INTO late_over_paper (ou_market_id,mo_market_id,event_name,competition,entry_ts,minute,lay_px,lay_sz,goals,goal_src,h_xg,a_xg,h_sot,a_sot) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(mid,mo,ev,comp,ts,mn,lp,lsz,g,src,_x[0],_x[1],_e[0],_e[1]))'''
if new in s: print("already patched")
else:
    assert old in s, "insert anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("late-over records xG + SOT at entry")
PY
python3 -m py_compile /root/pe-xg/late_over_paper.py
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT column_name FROM information_schema.columns WHERE table_name='espn_stats' AND column_name IN ('h_sot','a_sot')"); print("espn sot cols:",k.fetchall())
PY
pkill -f late_over_paper.py || true; sleep 2; nohup /root/pe-xg/keepalive_lo.sh >/dev/null 2>&1 & sleep 30; pgrep -af late_over_paper.py | head -1; tail -2 /root/pe-xg/late_over.log 2>/dev/null || ls /root/pe-xg
