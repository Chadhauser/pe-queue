#!/bin/bash
set -o pipefail
# 451 (Finder 2026-11-02, queue item 3): RACING GRID v3, honest version of 302. racing_bsp UK/IE, WIN and PLACE.
# Shapes (risk £10: back stake £10, lay liability £10; 2% commission on profit):
#  BACK_SETTLE, LAY_SETTLE              at BSP, hold to the result
#  BACK_TP10/20/30/50                   back at BSP, green when in-play price falls X% (needs ipmin)
#  LAY_TP25/50/100                      lay at BSP, green when in-play price rises Y% (needs ipmax). NB: 302 called this "LAY_STOP", but a
#                                       drift is PROFIT for a layer, so it is a take-profit. Kept for comparison with 302.
#  LAY_STOP25/50/100                    lay at BSP, real stop: green when in-play price shortens to BSP/(1+Y) (needs ipmin)
# Honesty vs 302:
#  - ONE TICK ADVERSE at entry even on BSP (back fills BSP-1 tick, lay BSP+1 tick) and at every in-play exit.
#  - A take-profit fills only if the extreme traded THROUGH the target by one tick; fill at the target. A stop fills one tick beyond the
#    stop level (in-play racing gaps can be far worse: STOP P&L IS OPTIMISTIC). A touch is still not a guaranteed fill: TP P&L is unverified.
#  - An exit that never triggers is settled at the RESULT (race finished), never dropped.
#  - New cell levels: course x band x morning-steam (the item's ask), course x band x field; n >= 300 with >= 150 per half.
#  - Distinct races per cell reported (several runners per race in one cell -> correlated, t inflated).
# Look-ahead caveats: price band and steam ratios use BSP (known only at the off; a BSP bet is placed blind) — proxy for the price at the
# off. ppwap includes the final pre-off trades: pp cells are NOT cleanly tradable and are flagged (never PASS).
# LAY_STOP turned out UNMODELLABLE from extremes (see log) and can never PASS.
# Halves by event-date median. Output table rgrid3_cells (created tonight). Log ends with SURVIVORS.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,psycopg2.extras,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p):
    p=np.asarray(p,dtype=float)
    return np.select([p<2,p<3,p<4,p<6,p<10,p<20,p<30,p<50,p<100],[0.01,0.02,0.05,0.1,0.2,0.5,1,2,5],10.0)
def comm(x): return np.where(x>0,x*0.98,x)
def back_settle(bsp,won):
    p=bsp-tick(bsp); return np.where(p>1.01,comm(np.where(won,10*(p-1),-10.0)),np.nan)
def lay_settle(bsp,won):
    p=bsp+tick(bsp); s=10/(p-1); return comm(np.where(won,-10.0,s))
def back_tp(bsp,won,ipmin,X):
    p=bsp-tick(bsp); tgt=p*(1-X); hit=(~np.isnan(ipmin))&(ipmin<=tgt-tick(tgt))&(tgt>1.01)
    return np.where(p>1.01,comm(np.where(hit,10*(p/tgt-1),np.where(won,10*(p-1),-10.0))),np.nan)
def lay_tp(bsp,won,ipmax,Y):
    p=bsp+tick(bsp); s=10/(p-1); tgt=p*(1+Y); hit=(~np.isnan(ipmax))&(ipmax>=tgt+tick(tgt))
    return comm(np.where(hit,s*(1-p/tgt),np.where(won,-10.0,s)))
def lay_stop(bsp,won,ipmin,Y):
    p=bsp+tick(bsp); s=10/(p-1); stp=p/(1+Y); hit=(~np.isnan(ipmin))&(ipmin<=stp)
    q=np.maximum(1.01,stp-tick(stp)); return comm(np.where(hit,s*(1-p/q),np.where(won,-10.0,s)))
# known answers (tick = increment at p):
# back 5.0 -> 4.9: win 39*0.98=38.22, lose -10. lay 5.0 -> 5.1, stake 10/4.1, win 2.390244, lose -10.
# BACK_TP20 at 5.0: fill 4.9, target 3.92 (tick .05) -> needs ipmin <= 3.87 -> 10*(4.9/3.92-1)=2.5 -> 2.45; ipmin 3.90 -> settles (-10 if lost).
# LAY_TP50 at 5.0: fill 5.1, target 7.65 (tick .2) -> needs ipmax >= 7.85 -> s*(1-5.1/7.65)=2.439024*0.333333=0.813008 -> *0.98=0.796748.
# LAY_STOP100 at 5.0: fill 5.1, stop 2.55 -> fill 2.53 (tick .02) -> s*(1-5.1/2.53)= -2.477586 (no commission on a loss).
b=lambda v: np.array([v],dtype=float)
assert abs(back_settle(b(5.0),b(True)==1)[0]-38.22)<1e-9 and back_settle(b(5.0),b(False)==1)[0]==-10.0
assert abs(lay_settle(b(5.0),b(False)==1)[0]-10/4.1*0.98)<1e-9 and lay_settle(b(5.0),b(True)==1)[0]==-10.0
assert abs(back_tp(b(5.0),b(False)==1,b(3.87),0.2)[0]-2.45)<1e-9 and back_tp(b(5.0),b(False)==1,b(3.90),0.2)[0]==-10.0
assert abs(lay_tp(b(5.0),b(True)==1,b(7.85),0.5)[0]-0.796748)<1e-6 and lay_tp(b(5.0),b(True)==1,b(7.80),0.5)[0]==-10.0
assert abs(lay_stop(b(5.0),b(True)==1,b(2.55),1.0)[0]-(-10/4.1*(5.1/2.53-1)))<1e-9 and abs(lay_stop(b(5.0),b(True)==1,b(2.55),1.0)[0]+2.477586)<1e-5
print("P&L unit checks: OK")
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
D=pd.read_sql("""SELECT market, event_id, menu_hint course, event_dt, selection_id, win_lose::int won,
  bsp::float bsp, ppwap::float ppwap, morningwap::float mwap, NULLIF(ipmin,0)::float ipmin, NULLIF(ipmax,0)::float ipmax
  FROM racing_bsp WHERE bsp IS NOT NULL AND bsp>1.01 AND bsp<1000 AND lower(country) IN ('uk','ire','gb','ie') AND win_lose IS NOT NULL""",con)
D['market']=D.market.fillna('WIN').str.upper().str.replace(r'.*PLACE.*','PLACE',regex=True); D.loc[~D.market.isin(['WIN','PLACE']),'market']='WIN'
D=D.drop_duplicates(['event_id','market','selection_id'])
D['field']=D.groupby(['event_id','market']).selection_id.transform('size')
D['fband']=pd.cut(D.field,[0,6,9,13,40],labels=['<=6','7-9','10-13','14+'])
D['band']=pd.cut(D.bsp,[1,2,3,5,8,12,20,40,1000],labels=['<2','2-3','3-5','5-8','8-12','12-20','20-40','40+'])
D['steam']=pd.cut(D.mwap/D.bsp,[0,0.8,0.95,1.05,1.25,100],labels=['drift20+','drift5-20','flat','steam5-20','steam20+'])
D['pp']=pd.cut(D.ppwap/D.bsp,[0,0.9,0.98,1.02,1.1,100],labels=['late-drift10+','late-drift','flat','late-steam','late-steam10+'])
D['course']=D.course.fillna('').str.replace(r'\s+\d.*','',regex=True).str.strip()
med=D.event_dt.median(); D['half']=D.event_dt>med
print(f"runners {len(D)} | races {D.event_id.nunique()} | {D.event_dt.min()} -> {D.event_dt.max()} | date median {med} | WIN {int((D.market=='WIN').sum())} PLACE {int((D.market=='PLACE').sum())}",flush=True)
won=D.won.values==1; bsp=D.bsp.values; ipmin=D.ipmin.values; ipmax=D.ipmax.values
shapes={'BACK_SETTLE':back_settle(bsp,won),'LAY_SETTLE':lay_settle(bsp,won)}
for X in (0.10,0.20,0.30,0.50): shapes[f'BACK_TP{int(X*100)}']=back_tp(bsp,won,ipmin,X)
for Y in (0.25,0.50,1.00): shapes[f'LAY_TP{int(Y*100)}']=lay_tp(bsp,won,ipmax,Y)
for Y in (0.25,0.50,1.00): shapes[f'LAY_STOP{int(Y*100)}']=lay_stop(bsp,won,ipmin,Y)
LEVELS=(['market','band'],['market','band','fband'],['market','band','steam'],['market','band','pp'],['market','band','course'],
        ['market','band','steam','pp'],['market','band','fband','steam'],['market','course','band','steam'],['market','course','band','fband'])
DIMS=['market','band','fband','steam','pp','course']
cells=[]
for name,p in shapes.items():
    D['pnl']=p; E=D[D.pnl.notna()]
    for dims in LEVELS:
        g=E.groupby(dims+['half'],observed=True).agg(n=('pnl','size'),s=('pnl','sum'),ss=('pnl',lambda x:(x*x).sum()),races=('event_id','nunique')).reset_index()
        g['shape']=name; g['level']='+'.join(dims)
        for c in DIMS:
            if c not in g: g[c]=None
        cells.append(g[['shape','level']+DIMS+['half','n','s','ss','races']])
C=pd.concat(cells,ignore_index=True)
for c in DIMS: C[c]=C[c].astype(object).where(C[c].notna(),'*')
cur.execute("DROP TABLE IF EXISTS rgrid3_cells; CREATE TABLE rgrid3_cells (shape TEXT, level TEXT, market TEXT, band TEXT, fband TEXT, steam TEXT, pp TEXT, course TEXT, half BOOLEAN, n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION, races INT)")
psycopg2.extras.execute_values(cur,"INSERT INTO rgrid3_cells VALUES %s",[tuple(r) for r in C.itertuples(index=False)],page_size=5000)
C1=C[~C.half].set_index(['shape','level']+DIMS); C2=C[C.half].set_index(['shape','level']+DIMS)
A=C1[['n','s','ss','races']].join(C2[['n','s','ss','races']],how='outer',lsuffix='1',rsuffix='2').fillna(0).reset_index()
A['n']=A.n1+A.n2; A['races']=A.races1+A.races2; A['mean']=(A.s1+A.s2)/A.n
A['sd']=np.sqrt(np.maximum((A.ss1+A.ss2)/A.n-A['mean']**2,1e-9)); A['t']=A['mean']/(A.sd/np.sqrt(A.n))
A['h1']=A.s1/A.n1.replace(0,np.nan); A['h2']=A.s2/A.n2.replace(0,np.nan)
T=A[(A.n>=300)].copy()
T['PASS']=(T.n1>=150)&(T.n2>=150)&(T.t>=3.5)&(T.h1>0)&(T.h2>0)&(T['mean']>=0.15)&(~T.level.str.contains('pp'))&(~T['shape'].str.startswith('LAY_STOP'))
cols=['shape','level','market','course','band','fband','steam','pp','n','races','mean','t','n1','h1','n2','h2','PASS']
print(f"\n==== RACING GRID v3: {len(A)} cells, {len(T)} with n>=300 ====")
print("\n== baseline (market x band, settle shapes)")
print(T[(T.level=='market+band')&T['shape'].isin(['BACK_SETTLE','LAY_SETTLE'])][cols].round(3).to_string(index=False))
OK=T[~T['shape'].str.startswith('LAY_STOP')&~T.level.str.contains('pp')]
print("\n== top 5 LAY_STOP (UNMODELLABLE: winners always trade ~1.01 so 'ipmin<=stop' caps every winner's loss; a stop cannot rest on the book and in-play gaps/delay make the fill fiction — NEVER PASS)")
print(T[T['shape'].str.startswith('LAY_STOP')].sort_values('t',ascending=False).head(5)[cols].round(3).to_string(index=False))
print("\n== top 15 by t, n>=300, tradable shapes (no LAY_STOP, no pp levels)")
print(OK.sort_values('t',ascending=False).head(15)[cols].round(3).to_string(index=False))
print("\n== top 15 by t, course x band x steam (the item's ask; tradable shapes)")
print(OK[OK.level=='market+course+band+steam'].sort_values('t',ascending=False).head(15)[cols].round(3).to_string(index=False))
S=T[T.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} (of {len(T)} cells tested at n>=300 — expect a few false positives at t>=3.5 from that many tests)")
print(S.head(40)[cols].round(3).to_string(index=False) if len(S) else "none")
PY
