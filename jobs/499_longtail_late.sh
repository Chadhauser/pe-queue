#!/bin/bash
set -o pipefail
# 499_longtail_late (Finder 2026-11-05, queue item 143, Finder's own, source c): late short prices in the long tail, settled on the official result (bf_hist_result, job 520). Rule pushed in the queue before any price was read. Read only.
# CLOCK first in-play print of the market in T+75 to T+79 and T+95 to T+99 min of market time. Shortest runner of MO, OU25, OU35 by the latest print of each runner in the 5 min up to that clock window's first print, which must itself be a real print in the window; worse of it and the next in-play print within 120 s, one tick adverse, 2%, £10 risk, hold to the official result. A market that has settled before the clock has no print there: it has no entry, as no one could trade it, and is counted. No score used, so a band mixes game states. All one part-loaded month: a pass only earns an unseen-months test. Groups as item 141, senior cuts from the first half.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import group,bk,ly,fill,first_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
def shortest(rows):
    """rows: (sel,price). The runner with the lowest print; a tie has no shortest runner, no trade."""
    rows=sorted(rows,key=lambda r:r[1]); return None if len(rows)<2 or rows[0][1]==rows[1][1] else rows[0][0]
def band(p): return '<1.15' if p<1.15 else '1.15-1.40' if p<1.40 else '1.40-2.00' if p<2.0 else None
assert shortest([('a',1.2),('b',3.0)])=='a' and shortest([('a',2.0),('b',2.0)]) is None and shortest([('a',2.0)]) is None
assert band(1.14)=='<1.15' and band(1.15)=='1.15-1.40' and band(1.40)=='1.40-2.00' and band(2.0) is None
print("checks: OK",flush=True)
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
TYPES={'MATCH_ODDS':'MO','OVER_UNDER_25':'OU25','OVER_UNDER_35':'OU35'}
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,list(TYPES)); print(f"markets with one WINNER {len(RS)}, dropped {bad}",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
print(f"markets on the tape {len(MK)}, events {MK.event_id.nunique()}",flush=True)
mkts=list(MK.market_id); parts=[]; liqp=[]
for i in range(0,len(mkts),2000):
    parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mkts[i:i+2000],)))
mo=list(MK[MK.mty=='MATCH_ODDS'].market_id)
for i in range(0,len(mo),2000):
    liqp.append(pd.read_sql("SELECT o.market_id,count(*) c FROM bf_hist_other o WHERE o.sport='Soccer' AND o.market_id=ANY(%s) AND NOT o.inplay AND o.ts>=o.market_time-interval '60 min' AND o.ts<o.market_time-interval '20 min' GROUP BY 1",con,params=(mo[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
L=pd.concat(liqp,ignore_index=True); mo2e=dict(zip(MK.market_id,MK.event_id)); liq={mo2e[m]:int(c) for m,c in zip(L.market_id,L.c)}
print(f"in-play rows {len(P)}, {time.time()-T0:.0f}s",flush=True)
EV=MK.drop_duplicates('event_id').set_index('event_id'); PX={k:g for k,g in P.groupby('market_id')}
SK=Counter(); rows=[]
for r in MK.itertuples():
    x=PX.get(r.market_id); k=TYPES[r.mty]
    if x is None: SK[k+' no in-play print']+=1; continue
    o=float(r.off)
    for T in (75,95):
        lo,hi=o+T*60,o+(T+5)*60
        win=x[(x.tt>=lo)&(x.tt<=hi)]
        if not len(win): SK[f'{k} T{T} no print in window']+=1; continue
        tf=float(win.tt.iloc[0]); seen=x[(x.tt<=tf)&(x.tt>=tf-300)].groupby('sel',sort=False).ltp.last()   # state at the first print of the window, real prints in the last 5 min only
        s=shortest(list(seen.items()))
        if s is None or s not in RS[r.market_id]: SK[f'{k} T{T} no shortest runner']+=1; continue
        y=x[x.sel==s]; ts,px=y.tt.values,y.ltp.values; i=first_in(ts,tf,hi)
        if i is None: SK[f'{k} T{T} shortest has no print in window']+=1; continue
        b=band(float(px[i]))
        if b is None: SK['outside the bands']+=1; continue
        won=RS[r.market_id][s]; grp=group(r.ev)
        for side in 'BL':
            p=fill(ts,px,i,side); v=bk(p,won) if side=='B' else ly(p,won)
            if v is None: SK['bottom of ladder, no back']+=1; continue
            rows.append((r.event_id,grp,o,k,T,b,side,p,won,v))
print("counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='e grp off k T b side p won v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
ee=MK.drop_duplicates('event_id'); first=[e for e,o,n in zip(ee.event_id,ee.off,ee.ev) if o<md and group(n) is None]; ks=pd.Series([liq.get(e,0) for e in first]); c1,c2=np.quantile(ks,[1/3,2/3]); print(f"cuts {c1:.0f}, {c2:.0f}",flush=True)
R['g']=[x if isinstance(x,str) else ('S_THIN' if liq.get(e,0)<=c1 else 'S_MID' if liq.get(e,0)<=c2 else 'S_DEEP') for x,e in zip(R.grp,R.e)]  # the column holds NaN, not None, for a senior game, and NaN is truthy: the first run lost every senior game
assert R.g.notna().all() and {'S_THIN','S_MID','S_DEEP'}<=set(R.g)
print("games by group:",R.drop_duplicates('e').groupby('g').size().to_dict(),flush=True)
out=[]
for k,x in R.groupby(['g','k','T','b','side']):
    l=line(x.v.values,x.h.values); out.append(dict(g=k[0],mkt=k[1],T=k[2],band=k[3],side=k[4],n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== lines {len(O)}, n>=300 {int((O.n>=300).sum())}; by chance about {len(O)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=30"); print(O[O.n>=30].head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("worst 3"); print(O[O.n>=30].tail(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
