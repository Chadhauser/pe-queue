#!/bin/bash
# 217: the live ladders say lay-Over 2.5 in the 1.5-2.5 band late is +£2.62/£10 (n 480) — those are mostly TWO-goal games, a state the
# honest engine has never tested (OPENxg requires <= 1 goal). Add family G2LATE@m: exactly 2 goals at m -> lay Over 2.5 (exits
# +10/+20/next goal/FT), and extend trigger minutes to 80 and 85 for all families. Re-run (3-4 min) and print the new family by minute.
cd /root/pe-factory/v4 && python3 - <<'PY'
p='stats_sweep.py'; s=open(p).read(); n=0
if 'G2LATE' not in s:
    anchor="                if hg==0 and ag==0: emit(f'LEVEL00@{m}','MO','DRAW','lay',m)\n"
    assert anchor in s; s=s.replace(anchor,anchor+"                if hg+ag==2 and m>=55: emit(f'G2LATE@{m}','OU25','OVER','lay',m)\n",1); n+=1
if 'TRIG=(20,25,30,35,40,55,60,65,70,75)' in s: s=s.replace('TRIG=(20,25,30,35,40,55,60,65,70,75)','TRIG=(20,25,30,35,40,55,60,65,70,75,80,85)',1); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile stats_sweep.py || exit 1
timeout 3300 python3 stats_sweep.py 2>&1 | grep -E "SWEEP:|stored" | head -3
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT fam, exit, band, n, round(mean,2) mean, round(t,2) t, round(h1,2) h1, round(h2,2) h2 FROM v4_stats_results WHERE run_date=current_date AND fam='G2LATE' ORDER BY exit, band",c)
print("=== G2LATE (2 goals, lay Over 2.5) pooled 55'-85' ===\n",d.to_string(index=False))
m=pd.read_sql("SELECT exit, band, minute, n, round(mean,2) mean, round(t,2) t FROM v4_stats_minute WHERE run_date=current_date AND fam='G2LATE' ORDER BY exit, band, minute",c)
print("\n=== G2LATE by minute ===\n",m.to_string(index=False))
m2=pd.read_sql("SELECT fam, exit, band, minute, n, round(mean,2) mean, round(t,2) t FROM v4_stats_minute WHERE run_date=current_date AND fam='OPENxg1.0' AND sel='OU25 OVER' AND dir='lay' AND minute>=75 ORDER BY exit, band, minute",c)
print("\n=== OPENxg1.0 lay Over at 75/80/85 ===\n",m2.to_string(index=False))
PY
