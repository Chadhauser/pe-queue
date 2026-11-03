#!/bin/bash
set -o pipefail
# 475 (Finder 2026-11-03, queue item 19, last two checks).
# PART A: does bf_hist_price hold more than one row per event/minute/selection? 473 printed +0.724 for a rule that 474 rebuilt at +0.565 from an array (last row wins), so which row is used may matter. Sample: the first 1,500 mapped games.
# PART B: real touch for the one line passing at one entry per game in 474 (La Liga, level score, minutes 30-45, LAY OU15 UNDER; the sister lines BACK OU15 OVER and LAY MO DRAW). On liq_sample: ticks from LTP to the touch you would hit, spread,
#   size, and the same trade's entry at real touch against LTP. La Liga by name, all leagues for comparison. liq_sample carries no score, so this is cost only, across all scores at those minutes, not a P&L.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def idx(s): return np.searchsorted(LADA,s.round(2)-1e-9)
t=pd.Series([2.0,2.02,3.0,3.05]); assert (np.diff(idx(t))==[1,49,1]).all()    # 2.00->2.02 one tick; 2.02->3.00 49 ticks; 3.00->3.05 one tick
print("ladder check: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s';")
E=pd.read_sql("SELECT event_id FROM af_price_map LIMIT 1500",con)
D=pd.read_sql("""SELECT mkt, count(*) rows_, count(*) FILTER (WHERE c>1) keys_with_dupes, count(*) FILTER (WHERE c>1 AND mx/mn>1.2) keys_differing_20pct FROM
  (SELECT mkt, sel, event_id, minute, count(*) c, max(ltp::float) mx, min(ltp::float) mn FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','OU35','BTTS') AND ltp>=1.01 GROUP BY 1,2,3,4) x GROUP BY 1 ORDER BY 1""",con,params=(list(E.event_id),))
print("\n== PART A: one key = event/minute/selection"); print(D.to_string(index=False),flush=True)
C=pd.read_sql("SELECT DISTINCT competition FROM liq_sample WHERE ts>now()-interval '6 days' AND competition ILIKE '%%liga%%'",con); print("\ncompetitions matching liga:",sorted(map(str,C.competition)),flush=True)
L=pd.read_sql("""SELECT competition, mkt, sel, ltp::float ltp, back_px::float bp, lay_px::float lp, lay_sz::float ls, back_sz::float bs FROM liq_sample
  WHERE ts>now()-interval '8 days' AND minute BETWEEN 30 AND 45 AND ltp>1 AND back_px>1 AND lay_px>back_px AND ((mkt='OU15') OR (mkt='MO' AND sel='DRAW'))""",con)
L['it']=idx(L.ltp); L['ib']=idx(L.bp); L['il']=idx(L.lp); L['lg']='other'; L.loc[L.competition.str.contains('Spanish La Liga',na=False),'lg']='La Liga'
L['side']=np.where(L.sel.str.contains('OVER'),'BACK','LAY'); L['gap']=np.where(L.side=='BACK',L.it-L.ib,L.il-L.it); L['sz']=np.where(L.side=='BACK',L.bs,L.ls)
L=L[(L.ltp>=1.3)&(L.ltp<=6)]
pd.set_option('display.width',220)
print("\n== PART B: price 1.30-6, minutes 30-45: ticks from LTP to the touch hit (LAY the UNDER and the DRAW, BACK the OVER); the engine assumes 1, the x3 test 4")
print(L.groupby(['lg','mkt','sel','side']).agg(n=('gap','size'),gap_med=('gap','median'),gap_p75=('gap',lambda v:np.percentile(v,75)),gap_p90=('gap',lambda v:np.percentile(v,90)),spread_med=('il',lambda v:np.median(v-L.loc[v.index,'ib'])),sz_med=('sz','median')).round(1).to_string())
print("\n== SURVIVORS: see report")
PY
