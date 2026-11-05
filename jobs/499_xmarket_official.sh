#!/bin/bash
set -o pipefail
# 499_xmarket_official (Finder 2026-11-05, queue item 142, Finder's own, source c, item 73's method on the loaded feed; from jobs/499_ko_cross_market.sh): two-rate Poisson cross-market gap before the off, settled on the official result (bf_hist_result, job 520). Rule pushed in the queue before any price was read. Read only.
# ENTRY as item 141: last non-in-play print T-20 to T-2 min per selection, one tick adverse, 2%, £10 risk. The fit uses the print itself; the fill is the worse of it and the next within 120 s. MODEL as item 132: residual less the walk-forward mean of the previous 300 games per line, first 300 not traded, a game never sees itself or a game at the same off. Cuts nest. Not item 73: no 2019-23 fit on the box.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import deque,Counter
from scipy.optimize import minimize
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time(); FH=0.45; N=11; I=np.arange(N); WARM=300
F_=np.cumprod(np.r_[1.,np.arange(1,N)])
def pmf(l): return np.exp(-l)*l**I/F_
def probs(lh,la):
    M=np.outer(pmf(lh),pmf(la)); M=M/M.sum(); S=I[:,None]+I[None,:]
    o=lambda k:M[S>k].sum(); lf=(lh+la)*FH
    return dict(H=np.tril(M,-1).sum(),D=np.trace(M),A=np.triu(M,1).sum(),OU15=o(1),OU25=o(2),OU35=o(3),BTTS=M[1:,1:].sum(),FH05=1-np.exp(-lf),FH15=1-np.exp(-lf)*(1+lf))
def fit(h,d,a,ov):
    def f(x):
        p=probs(np.exp(x[0]),np.exp(x[1])); return (p['H']-h)**2+(p['D']-d)**2+(p['A']-a)**2+(p['OU25']-ov)**2
    r=minimize(f,[np.log(1.4),np.log(1.1)],method='Nelder-Mead',options=dict(xatol=1e-3,fatol=1e-7,maxiter=200))
    return float(np.exp(r.x[0])),float(np.exp(r.x[1])),float(r.fun)
def nrm(a,b): return (1/a)/(1/a+1/b)
_p=probs(1.0,1.0)
assert abs(_p['H']-_p['A'])<1e-9 and abs(_p['OU15']-(1-np.exp(-2)*3))<1e-5 and abs(_p['BTTS']-(1-np.exp(-1))**2)<1e-5 and abs(_p['FH05']-(1-np.exp(-0.9)))<1e-9
_x=probs(1.7,0.9); _f=fit(_x['H'],_x['D'],_x['A'],_x['OU25']); assert abs(_f[0]-1.7)<0.02 and abs(_f[1]-0.9)<0.02 and _f[2]<1e-5
assert abs(nrm(1.5,3.0)-2/3)<1e-9
print("checks: OK",flush=True)
TYPES={'MATCH_ODDS':'MO','OVER_UNDER_15':'OU15','OVER_UNDER_25':'OU25','OVER_UNDER_35':'OU35','BOTH_TEAMS_TO_SCORE':'BTTS','FIRST_HALF_GOALS_05':'FH05','FIRST_HALF_GOALS_15':'FH15'}
PAIR=('OU15','OU35','BTTS','FH05','FH15')
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,list(TYPES)); print(f"markets with one WINNER {len(RS)}, dropped {bad}",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
mkts=list(MK.market_id); parts=[]
for i in range(0,len(mkts),2000):
    parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '21 min'",con,params=(mkts[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
print(f"rows {len(P)}, events {MK.event_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
PX={k:g for k,g in P.groupby('market_id')}; SK=Counter(); rec=[]
for e,g in MK.groupby('event_id'):
    ev=g.ev.iloc[0]; home,_x,away=ev.partition(' v '); E={}
    for r in g.itertuples():
        x=PX.get(r.market_id)
        if x is None: continue
        o=float(r.off)
        for s,y in x.groupby('sel',sort=False):
            if s not in RS[r.market_id]: continue
            ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
            if i is None: continue
            sl=str(s).strip().lower(); tag=sl.split()[0] if sl.split() else sl
            E[(TYPES[r.mty],s if TYPES[r.mty]=='MO' else tag)]=(ts,px,i,RS[r.market_id][s])
    if not all(k in E for k in (('MO',home),('MO',away),('MO','The Draw'),('OU25','over'),('OU25','under'))): SK['no MO or OU25 at entry']+=1; continue
    pr=lambda k:float(E[k][1][E[k][2]])
    ih,idr,ia=1/pr(('MO',home)),1/pr(('MO','The Draw')),1/pr(('MO',away)); z=ih+idr+ia
    if not 0.95<z<1.15: SK['MO book out of 0.95-1.15']+=1; continue
    lh,la,err=fit(ih/z,idr/z,ia/z,nrm(pr(('OU25','over')),pr(('OU25','under'))))
    if err>0.002: SK['fit error over 0.002']+=1; continue
    rec.append(dict(e=e,off=float(g.off.iloc[0]),M=probs(lh,la),E=E))
print(f"fitted {len(rec)}; {dict(SK)}; {time.time()-T0:.0f}s",flush=True)
rec.sort(key=lambda r:r['off']); BUF={k:deque(maxlen=WARM) for k in PAIR}; rows=[]; rs=Counter(); i=0; md=np.median([r['off'] for r in rec])
TAG={'BTTS':('yes','no')}
while i<len(rec):
    j=i
    while j<len(rec) and rec[j]['off']==rec[i]['off']: j+=1
    add=[]
    for r in rec[i:j]:
        for mk in PAIR:
            po,pu=TAG.get(mk,('over','under')); E=r['E']
            if (mk,po) not in E or (mk,pu) not in E: rs[mk+' no pair']+=1; continue
            a,b=E[(mk,po)],E[(mk,pu)]; raw=nrm(float(a[1][a[2]]),float(b[1][b[2]]))-r['M'][mk]; add.append((mk,raw))
            if len(BUF[mk])<WARM: rs[mk+' warm-up']+=1; continue
            rr=raw-float(np.mean(BUF[mk])); h=1 if r['off']<md else 2
            for cut in (.02,.03,.05):
                if abs(rr)<cut: continue
                d='RICH_OVER' if rr>0 else 'CHEAP_OVER'
                cheap,rich=(b,a) if rr>0 else (a,b)
                pb=fill(cheap[0],cheap[1],cheap[2],'B'); v=bk(pb,cheap[3])
                if v is not None: rows.append((mk,cut,d,'BACK_CHEAP',r['e'],h,pb,cheap[3],v))
                pl=fill(rich[0],rich[1],rich[2],'L'); rows.append((mk,cut,d,'LAY_RICH',r['e'],h,pl,rich[3],ly(pl,rich[3])))
    for mk,raw in add: BUF[mk].append(raw)
    i=j
print("counts:",dict(sorted(rs.items())),flush=True)
R=pd.DataFrame(rows,columns='mk cut dir side e h x won v'.split()); out=[]
for k,x in R.groupby(['mk','cut','dir','side']):
    l=line(x.v.values,x.h.values); out.append(dict(mk=k[0],cut=k[1],dir=k[2],side=k[3],n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== lines {len(O)}, n>=300 {int((O.n>=300).sum())}; by chance about {len(O)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=30"); print(O[O.n>=30].head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("worst 3"); print(O[O.n>=30].tail(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)} (cuts nest)\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
