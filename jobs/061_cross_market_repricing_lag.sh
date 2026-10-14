#!/bin/bash
# 061: PETER'S CROSS-MARKET TEST (14 Oct prompt): after a goal, Match Odds reprices in seconds; do Over/Under 1.5/2.5/3.5, BTTS and
# first-half lines LAG, and is the lag tradeable? bf_hist_price holds 7 markets per event at 1-min LTP (Basic history, fresh LTP only).
# Goal = MO draw/leader LTP jump >=15% between consecutive minutes while in play. For each other market: LTP at goal+1..+5 vs its own
# level at goal+10 (the "settled" price). Lag = share of the eventual move not yet made at +1/+2/+3. Trade: at +1 min, back/lay the
# market in the direction of its eventual move, exit at +10, 2% spread each way, 2% comm; train 2024/25, test 2025/26, by market x
# goals-so-far x minute band. Also a consistency check: implied P(O1.5)>P(O2.5)>P(O3.5) violations per minute (free money if real).
cd /root/pe-scan && cat > xmkt_lag.py <<'PYFILE'
import sys, math, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(name='tape'); cur.itersize=100000
cur.execute("SELECT event_id, m, minute, mkt, sel, ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND minute BETWEEN 1 AND 88 ORDER BY event_id, m")
SELS={'OU15':'OVER','OU25':'OVER','OU35':'OVER','BTTS':'YES','FH05':'OVER','FH15':'OVER'}
rows=[]; viol=collections.Counter(); tot=collections.Counter(); n_ev=0; n_goals=0
def tp(side,e,x):
    p=(e*(1-SPREAD))/(x*(1+SPREAD))-1 if side=='back' else 1-(e*(1+SPREAD))/(x*(1-SPREAD))
    return p*(1-COMM) if p>0 else p
def process(ev,rs):
    global n_ev,n_goals
    n_ev+=1; season=str(rs[0][1])[:7]
    px=collections.defaultdict(dict)
    for _,m,minute,mkt,sel,ltp in rs:
        if ltp and ltp>1.0: px[(mkt,sel)][int(minute)]=float(ltp)
    draw=px.get(('MO','DRAW'),{})
    if not draw: return
    # consistency check per minute
    for t in range(1,89):
        a=px.get(('OU15','OVER'),{}).get(t); b=px.get(('OU25','OVER'),{}).get(t); c=px.get(('OU35','OVER'),{}).get(t)
        if a and b and c:
            tot['ou']+=1
            if not (1/a>1/b>1/c): viol['ou']+=1
    # goals from draw jumps
    goals=[]; last=None
    for t in sorted(draw):
        if last is not None and t-last[0]<=2 and abs(draw[t]/last[1]-1)>=0.15: goals.append(t)
        last=(t,draw[t])
    goals=[g for i,g in enumerate(goals) if i==0 or g-goals[i-1]>3]
    for gi,g in enumerate(goals):
        if g<5 or g>80: continue
        n_goals+=1
        for mkt,sel in SELS.items():
            d=px.get((mkt,sel),{})
            p0=d.get(g-1); p10=d.get(g+10) or d.get(g+9) or d.get(g+11)
            if not p0 or not p10: continue
            move=p10/p0-1
            if abs(move)<0.05: continue
            for off in (1,2,3,5):
                pk=d.get(g+off)
                if not pk: continue
                done=(pk/p0-1)/move          # share of eventual move already made at +off
                side='lay' if move>0 else 'back'   # price going up -> lay now, back later; going down -> back now
                pnl=tp(side,pk,p10)
                rows.append((season,mkt,gi+1,g,off,move,done,pnl))
buf=[]; last=None
for r in cur:
    if last is not None and r[0]!=last: process(last,buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(last,buf)
D=pd.DataFrame(rows,columns=['season','mkt','goal_no','minute','off','move','done','pnl'])
print(f"events {n_ev} goals {n_goals} market-goal-offset rows {len(D)}")
print(f"OU monotonicity violations (P(O1.5)>P(O2.5)>P(O3.5) broken): {viol['ou']} of {tot['ou']} minutes = {100*viol['ou']/max(tot['ou'],1):.2f}% (LTP staleness, not free money, unless tradeable at depth)")
pd.set_option('display.width',240)
print("\n=== 1. Share of the eventual (+10 min) move already made at +1/+2/+3/+5 min, by market (median) ===")
print(D.groupby(['mkt','off']).done.median().unstack('off').round(2).to_string())
D['mb']=pd.cut(D.minute,[0,30,45,60,80],labels=['5-30','31-45','46-60','61-80'])
def tstat(x): x=x.dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
print("\n=== 2. TRADE the lag: enter at +off in the direction of the eventual move, exit +10. P&L per £100 by market x off x season ===")
t=D.groupby(['mkt','off','season']).agg(n=('pnl','size'),per100=('pnl',lambda x:round(100*x.mean(),1)),t=('pnl',tstat)); print(t.unstack('season').to_string())
print("\n=== 3. same, +1 min only, by market x goal number x minute band (both seasons side by side) ===")
E=D[D.off==1]; t=E.groupby(['mkt','goal_no','mb','season'],observed=True).agg(n=('pnl','size'),per100=('pnl',lambda x:round(100*x.mean(),1)),t=('pnl',tstat)); t=t[t.n>=40]; print(t.unstack('season').to_string())
print("\nREADING: 'done' near 1.0 at +1 min = no lag. A cell is tradeable only if per100>+1 with t>=2 in BOTH seasons. Direction of the eventual move is known in hindsight here — the live version must infer it from the MO move (next job if any cell survives).")
PYFILE
python3 xmkt_lag.py
