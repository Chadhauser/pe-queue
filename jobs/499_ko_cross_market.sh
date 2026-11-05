#!/bin/bash
set -o pipefail
# 499_ko_cross_market (Finder 2026-11-05, queue item 132, Finder's own, source c): item 51's two-rate Poisson consensus at kick-off on the two-season tape. Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_fixtures, af_events, af_price_map, bf_hist_price. Local DB, read-only. Cups 2, 3 excluded. ENTRY earliest real print in tape minutes 0..2 per selection, lag outside -5..+20 min v the af kick-off dropped, a goal strictly before the latest print used dropped, as jobs/499_clock_calendar.sh.
# MODEL lambda home and away by least squares on normalised MO and OU25, predict OU15, OU35, BTTS, and FH05, FH15 with first-half share 0.45, independent Poisson. Poisson is wrong on average, so the signal is the residual less the rolling mean residual of the previous 1,000 games on that line by kick-off. Walk forward: a game never sees itself or a game at the same kick-off. First 1,000 per line not traded.
# TRADES |r| >= 0.02, 0.03, 0.05, r>0: Over or Yes is rich: lay it, or back Under or No. r<0: the reverse. All one bet per line per game. Hold to FT, FH lines to the af half-time score. LTP, one tick adverse, 2%, £10 risk, an upper bound. Halves by season.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import deque,Counter
from scipy.optimize import minimize
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
FH=0.45; N=11; I=np.arange(N)
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
F_=np.cumprod(np.r_[1.,np.arange(1,N)])
def pmf(l): return np.exp(-l)*l**I/F_
def grid(lh,la):
    return np.outer(pmf(lh),pmf(la))
def probs(lh,la):
    """Home, draw, away, P(total>k) for k=1,2,3, BTTS yes, P(FH total>0), P(FH total>1)."""
    M=grid(lh,la); M=M/M.sum(); S=I[:,None]+I[None,:]
    H=np.tril(M,-1).sum(); D=np.trace(M); A=np.triu(M,1).sum()
    o=lambda k:M[S>k].sum()
    bt=M[1:,1:].sum(); lf=(lh+la)*FH
    return dict(H=H,D=D,A=A,OU15=o(1),OU25=o(2),OU35=o(3),BTTS=bt,FH05=1-np.exp(-lf),FH15=1-np.exp(-lf)*(1+lf))
def fit(h,d,a,ov):
    def f(x):
        p=probs(np.exp(x[0]),np.exp(x[1])); return (p['H']-h)**2+(p['D']-d)**2+(p['A']-a)**2+(p['OU25']-ov)**2
    r=minimize(f,[np.log(1.4),np.log(1.1)],method='Nelder-Mead',options=dict(xatol=1e-3,fatol=1e-7,maxiter=200))
    return float(np.exp(r.x[0])),float(np.exp(r.x[1])),float(r.fun)
def nrm(a,b): return (1/a)/(1/a+1/b)
# known answers, worked by hand or from closed forms
_p=probs(1.0,1.0)
assert abs(_p['H']-_p['A'])<1e-9 and abs(_p['H']+_p['D']+_p['A']-1)<1e-9
assert abs(_p['OU15']-(1-np.exp(-2)*(1+2)))<1e-5 and abs(_p['OU25']-(1-np.exp(-2)*(1+2+2)))<1e-5
assert abs(_p['BTTS']-(1-np.exp(-1))**2)<1e-5 and abs(_p['FH05']-(1-np.exp(-0.9)))<1e-9 and abs(_p['FH15']-(1-np.exp(-0.9)*1.9))<1e-9
_x=probs(1.7,0.9); _f=fit(_x['H'],_x['D'],_x['A'],_x['OU25']); assert abs(_f[0]-1.7)<0.02 and abs(_f[1]-0.9)<0.02 and _f[2]<1e-5
assert abs(nrm(2.0,2.0)-.5)<1e-9 and abs(nrm(1.5,3.0)-2/3)<1e-9
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.kickoff IS NOT NULL AND f.season IN (2024,2025) AND f.league_id NOT IN (2,3)""",con).drop_duplicates('event_id')
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','OU35','BTTS','FH05','FH15') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
gm=P.fixture_id.map(fg); bad=(P.lag<-5)|(P.lag>20); kn=gm.notna()&(gm<P.minute)
print(f"games {G.shape[0]}, with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal before print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
P=P.sort_values('kickoff')
PAIR={'OU15':('OVER','UNDER'),'OU35':('OVER','UNDER'),'BTTS':('YES','NO'),'FH05':('OVER','UNDER'),'FH15':('OVER','UNDER')}
SK=Counter(); rec=[]; n=0
for (e,fx,s,ko,hg,ag,hh,ha),x in P.groupby(['event_id','fixture_id','season','kickoff','hg','ag','ht_hg','ht_ag'],sort=False,dropna=False):
    pr={(a,b):c for a,b,c in zip(x.mkt,x.sel,x.ltp)}
    need=[('MO','HOME'),('MO','DRAW'),('MO','AWAY'),('OU25','OVER'),('OU25','UNDER')]
    if any(k not in pr for k in need): SK['no MO or OU25 at the first print']+=1; continue
    ih,idr,ia=[1/pr[('MO',k)] for k in('HOME','DRAW','AWAY')]; z=ih+idr+ia
    if not 0.95<z<1.15: SK['MO book out of 0.95-1.15']+=1; continue
    lh,la,err=fit(ih/z,idr/z,ia/z,nrm(pr[('OU25','OVER')],pr[('OU25','UNDER')]))
    if err>0.002: SK['fit error over 0.002']+=1; continue
    M=probs(lh,la); n+=1
    rec.append(dict(e=e,fx=fx,s=s,ko=pd.Timestamp(ko),hg=hg,ag=ag,hh=hh,ha=ha,M=M,pr=pr))
    if n%2000==0: print(f"  fitted {n}, {time.time()-T0:.0f}s",flush=True)
print(f"fitted {len(rec)}; {dict(SK)}; {time.time()-T0:.0f}s",flush=True)
rec.sort(key=lambda r:r['ko'])
BUF={k:deque(maxlen=1000) for k in PAIR}; rows=[]; pend=[]; rs=Counter(); last=None; RES=[]
def outcome(mk,r):
    tot=r['hg']+r['ag']
    if mk=='OU15': return tot>1.5
    if mk=='OU35': return tot>3.5
    if mk=='BTTS': return r['hg']>0 and r['ag']>0
    if pd.isna(r['hh']) or pd.isna(r['ha']): return None
    ft=r['hh']+r['ha']; return ft>0.5 if mk=='FH05' else ft>1.5
i=0
while i<len(rec):
    j=i
    while j<len(rec) and rec[j]['ko']==rec[i]['ko']: j+=1
    add=[]
    for r in rec[i:j]:
        for mk,(po,pu) in PAIR.items():
            if (mk,po) not in r['pr'] or (mk,pu) not in r['pr']: rs[mk+' no pair']+=1; continue
            ni=nrm(r['pr'][(mk,po)],r['pr'][(mk,pu)]); raw=ni-r['M'][mk]; add.append((mk,raw))
            if len(BUF[mk])<1000: rs[mk+' warm-up']+=1; continue
            rr=raw-float(np.mean(BUF[mk])); won=outcome(mk,r)
            if won is None: rs[mk+' no HT score']+=1; continue
            RES.append((mk,rr))
            for cut in (.02,.03,.05):
                if abs(rr)<cut: continue
                d='RICH_OVER' if rr>0 else 'CHEAP_OVER'
                sb=(pu,not won) if rr>0 else (po,won)   # back the cheap side
                sl=(po,won) if rr>0 else (pu,not won)   # lay the rich side
                h=1 if r['s']==2024 else 2
                v=bk(r['pr'][(mk,sb[0])],sb[1])
                if v is not None: rows.append((mk,cut,d,'BACK_CHEAP',r['fx'],h,r['pr'][(mk,sb[0])],sb[1],v))
                rows.append((mk,cut,d,'LAY_RICH',r['fx'],h,r['pr'][(mk,sl[0])],sl[1],ly(r['pr'][(mk,sl[0])],sl[1])))
    for mk,raw in add: BUF[mk].append(raw)
    i=j
print("counts:",dict(rs),flush=True)
X=pd.DataFrame(RES,columns=['mk','r']); print("residual after walk-forward bias:"); print(X.groupby('mk').r.agg(['size','mean','std',lambda v:(abs(v)>=.02).mean(),lambda v:(abs(v)>=.05).mean()]).round(4).to_string())
R=pd.DataFrame(rows,columns=['mk','cut','dir','side','fx','h','x','won','v']); out=[]
for k,x in R.groupby(['mk','cut','dir','side']):
    l=line(x.v.values,x.h.values); out.append(dict(mk=k[0],cut=k[1],dir=k[2],side=k[3],n=l['n'],games=x.fx.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== lines {len(O)}, n>=300 {int((O.n>=300).sum())}, positive there {int(((O.n>=300)&(O.per10>0)).sum())}; by chance about {len(O)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=100"); print(O[O.n>=100].head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("worst 3"); print(O[O.n>=100].tail(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)} (one bet per game per line; cuts nest, so 0.03 and 0.05 are inside 0.02)\n",S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
