#!/bin/bash
set -o pipefail
# 465 (Finder 2026-11-03, own item 18): LOW-MONEY DRIFTERS INTO THE OFF — PILOT on stream_ticks (racing WIN, pre-off, OPEN; the whole
# table, ~3 days — range printed). From jobs/463: runners with < half their price share of morning money drift a lot from morning to BSP.
# Here: state at T-9..12 min = each runner's LAST tick with secs_to_off >= 540 (stream racing starts ~716 s before the off).
# R = traded-volume share (tv / race tv) / price share ((1/ltp) normalised over the race's runners with a state tick).
# Trades (real touch as 459: back fills at back_px, lay fills at lay_px, PLUS one tick adverse at both ends; risk £10; 2% commission):
#   LAY  at lay_px (+1 tick), back out at back_px (-1 tick) at the runner's last tick with secs_to_off >= 30 — exit book must be <= 120 s old,
#        otherwise the trade is counted as a skip (pre-off: the race has not run, so there is no result to settle at — skips are printed).
#   BACK at back_px (-1 tick), lay out at lay_px (+1 tick) — the mirror, for every R band.
# Halves by market start-time median. One entry per runner per market. Several runners per race in a cell are correlated.
# With ~90 markets this CANNOT reach n>=300 per cell in most bands: a pilot, to be re-run weekly as the table rolls.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p):
    p=np.asarray(p,dtype=float)
    return np.select([p<2,p<3,p<4,p<6,p<10,p<20,p<30,p<50,p<100],[0.01,0.02,0.05,0.1,0.2,0.5,1,2,5],10.0)
def comm(x): return np.where(x>0,x*0.98,x)
def lay_trade(lp0,bp1):
    a=lp0+tick(lp0); s=10/(a-1); c=np.maximum(1.01,bp1-tick(bp1)); return comm(s*(1-a/c))
def back_trade(bp0,lp1):
    a=bp0-tick(bp0); c=lp1+tick(lp1); return np.where(a>1.01,comm(10*(a/c-1)),np.nan)
b=lambda v: np.array([v],dtype=float)
# known answers: lay at 5.0 (+1 tick -> 5.1, stake 10/4.1=2.439024), back out at 6.0 (-1 tick -> 5.8): 2.439024*(1-5.1/5.8)=0.294365*0.98=0.288478
# back at 5.0 (-1 -> 4.9), lay out at 4.0 (+1 -> 4.1): 10*(4.9/4.1-1)=1.951220*0.98=1.912195
assert abs(lay_trade(b(5.0),b(6.0))[0]-0.288478)<1e-6 and abs(back_trade(b(5.0),b(4.0))[0]-1.912195)<1e-6
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='1800s'")
cur.execute("SELECT min(ts_recv), max(ts_recv) FROM stream_ticks WHERE sport='racing'"); r=cur.fetchone(); print("stream_ticks racing range:",r[0],"..",r[1],flush=True)
E=pd.read_sql("""SELECT DISTINCT ON (market_id, sel_id) market_id, sel_id, ts_recv ts, secs_to_off sto, back_px::float bp, lay_px::float lp, ltp::float ltp, tv::float tv
  FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay=false AND status='OPEN' AND secs_to_off>=540
  ORDER BY market_id, sel_id, ts_recv DESC""",con)
X=pd.read_sql("""SELECT DISTINCT ON (market_id, sel_id) market_id, sel_id, ts_recv xts, secs_to_off xsto, back_px::float xbp, lay_px::float xlp
  FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay=false AND status='OPEN' AND secs_to_off>=30
  ORDER BY market_id, sel_id, ts_recv DESC""",con)
print(f"state ticks {len(E)} runners in {E.market_id.nunique()} markets | exit ticks {len(X)}",flush=True)
E=E[(E.bp>1)&(E.lp>1)&(E.lp<1000)]
E['px']=E.ltp.where(E.ltp>1,(E.bp+E.lp)/2)
E=E[E.tv.notna()&(E.tv>=0)]
E['ps']=(1/E.px)/E.groupby('market_id').px.transform(lambda x:(1/x).sum())
E['vs']=E.tv/E.groupby('market_id').tv.transform('sum')
E=E[E.groupby('market_id').tv.transform('sum')>0]
E['R']=E.vs/E.ps
D=E.merge(X,on=['market_id','sel_id'],how='left')
D['ok']=D.xts.notna()&(D.xsto<=150)&(D.xbp>1)&(D.xlp>1)
skips=int((~D.ok).sum()); print(f"runners {len(D)} | exit book missing/stale (skipped, counted): {skips}",flush=True)
D=D[D.ok].copy()
D['Rb']=pd.cut(D.R,[-1,0.5,0.8,1.25,2,1e9],labels=['<0.5','0.5-0.8','0.8-1.25','1.25-2','2+'])
D['band']=pd.cut(D.bp,[1,3,6,12,30,1000],labels=['<3','3-6','6-12','12-30','30+'])
D['LAY']=lay_trade(D.lp.values,D.xbp.values); D['BACK']=back_trade(D.bp.values,D.xlp.values)
D['mv']=np.log(D.bp/D.xbp)   # >0 = shortened into the off
st=D.groupby('market_id').ts.transform('min'); med=st.median(); D['half']=st>med
print(f"half split at {med}")
print("\n== drift T-10 min -> T-30 s by R band (mean log back-price move, + = shortened; share drifting)")
print(D.groupby('Rb',observed=True).agg(n=('mv','size'),markets=('market_id','nunique'),mean_logmove=('mv','mean'),pct_drift=('mv',lambda x:(x<0).mean()),pct_short=('mv',lambda x:(x>0).mean())).round(4).to_string())
rows=[]
for side in ('LAY','BACK'):
    for keys in (['Rb'],['Rb','band']):
        for k,x in D[D[side].notna()].groupby(keys,observed=True):
            v=x[side]; n=len(v); mu=v.mean(); sd=v.std(ddof=0) or 1e-9
            a=x[~x.half][side]; c=x[x.half][side]
            rows.append(dict(side=side,cell=' '.join(map(str,k if isinstance(k,tuple) else (k,))),n=n,markets=x.market_id.nunique(),mean=mu,t=mu/(sd/np.sqrt(n)),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan))
R=pd.DataFrame(rows)
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)
print("\n== by R band")
print(R[R.cell.str.count(' ')==0].round(3).to_string(index=False))
print("\n== top 10 by t, R x price band")
print(R[R.cell.str.count(' ')==1].sort_values('t',ascending=False).head(10).round(3).to_string(index=False))
S=R[R.PASS]
print(f"\n== SURVIVORS: {len(S)}")
print(S.round(3).to_string(index=False) if len(S) else "none")
PY
