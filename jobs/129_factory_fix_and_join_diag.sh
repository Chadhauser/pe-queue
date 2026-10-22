#!/bin/bash
# 129: (a) THE FACTORY BUG, found by 126: it computes every sport for ~2 hours then dies on the INSERT with numpy floats
#     ("schema np does not exist") — three nights of results thrown away at the last line. Cast and re-run now (background).
#     (b) 127 matched 0 of 13,963 LTD games to form — diagnose: date ranges of bf_hist_other soccer vs football_matches, and
#     sample normalised names from both sides. Then re-run ltd_poisson with a robust join (exact date, +-1 day) and name fixes.
cd /root/pe-factory
python3 - <<'PY'
p='/root/pe-factory/factory.py'; s=open(p).read()
old="out.append((today,sport,strat,str(band),len(g),len(a),round(p1,2),round(t1,2),len(b),round(p2,2),round(t2,2),round(g[col].mean()*100,2),surv,"
new="out.append((today,sport,strat,str(band),int(len(g)),int(len(a)),float(round(p1,2)),float(round(t1,2)),int(len(b)),float(round(p2,2)),float(round(t2,2)),float(round(g[col].mean()*100,2)),bool(surv),"
if old in s: s=s.replace(old,new); open(p,'w').write(s); print("factory.py: insert cast fixed")
else: print("factory.py: pattern not found — check manually"); import re; print([l for l in s.splitlines() if 'out.append' in l])
PY
python3 -m py_compile factory.py && (nohup /root/pe-factory/resume.sh >/dev/null 2>&1 &) && echo "factory started in background (resume.sh, flock)"
echo "== (b) join diagnostics"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, re, unicodedata, psycopg2, pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT min(market_time), max(market_time), count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id<>'1'"); print("bf_hist soccer MO:",cur.fetchone())
cur.execute("SELECT date_trunc('month',market_time)::date m, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id<>'1' GROUP BY 1 ORDER BY 1"); print("  by month:",cur.fetchall())
cur.execute("SELECT min(date), max(date), count(*) FROM football_matches"); print("football_matches:",cur.fetchone())
cur.execute("SELECT date_trunc('month',date)::date m, count(*) FROM football_matches WHERE date>'2024-01-01' GROUP BY 1 ORDER BY 1"); print("  recent months:",cur.fetchall())
cur.execute("SELECT event_name FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id<>'1' GROUP BY event_name ORDER BY random() LIMIT 12"); print("bf event names:",[r[0] for r in cur.fetchall()])
cur.execute("SELECT DISTINCT home_team FROM football_matches ORDER BY random() LIMIT 12"); print("fm team names:",[r[0] for r in cur.fetchall()])
cur.execute("SELECT league_code, count(*) FROM football_matches GROUP BY 1 ORDER BY 2 DESC LIMIT 30"); print("fm leagues:",cur.fetchall())
PY
