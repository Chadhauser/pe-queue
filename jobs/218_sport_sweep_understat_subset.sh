#!/bin/bash
# 218: RESOLVE THE CONTRADICTION. Price-only sweep (37k games, detected goals, survivorship removed in 214): 0-0 at 60' lay draw 1.5-2.5,
# exit next goal = +£2.40/£10 (n 3,451, t 19.6). True-goal engine (3,440 top-league games): the same rule = -£1.72. Same price data, so
# the gap is either the UNIVERSE (lower leagues behave differently) or the DETECTION (the next-goal exit depends on detecting the goal;
# an undetected goal falls through to a full-win FT settlement instead of a hedge). Run the price-only sweep on exactly the Understat
# games -> if still positive, it is the universe; if negative, it is detection.
cd /root/pe-factory/v4 && python3 - <<'PY'
s=open('sport_sweep.py').read()
old='''    cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]; print("games:",len(evs),flush=True)'''
new='''    cur.execute("SELECT DISTINCT event_id FROM xg_price_map WHERE EXISTS (SELECT 1 FROM understat_shots u WHERE u.understat_id::text=xg_price_map.understat_id)"); evs=[r[0] for r in cur.fetchall()]; print("games (Understat subset):",len(evs),flush=True)'''
assert old in s; s=s.replace(old,new,1); s=s.replace('v4_sport_results','v4_sport_results_sub').replace('v4_sport_trades','v4_sport_trades_sub')
open('sport_sweep_subset.py','w').write(s); print("subset copy written")
PY
python3 -m py_compile sport_sweep_subset.py || exit 1
timeout 3000 python3 sport_sweep_subset.py > sport_sweep_subset.log 2>&1; echo "run exit $?"; grep -E "games|true result|cells" sport_sweep_subset.log | head -5
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT trig, exit, band, n, round(mean,2) mean, round(t,2) t, round(h1,2) h1, round(h2,2) h2 FROM v4_sport_results_sub WHERE run_date=current_date AND trig IN ('CLOCK46g0','CLOCK60g0','CLOCK75g0') AND role='draw' AND dir='lay' AND n>=50 ORDER BY trig, exit, band",c)
print("=== PRICE-ONLY SWEEP ON THE UNDERSTAT GAMES — lay draw in a 0-0 ===\n",d.to_string(index=False))
e=pd.read_sql("SELECT fam, exit, band, minute, n, round(mean,2) mean, round(t,2) t FROM v4_stats_minute WHERE run_date=current_date AND fam='LEVEL00' AND band='1.5-2.5' AND minute IN (60,75) ORDER BY exit, minute",c)
print("\n=== TRUE-GOAL ENGINE, same games, same rule ===\n",e.to_string(index=False))
PY
