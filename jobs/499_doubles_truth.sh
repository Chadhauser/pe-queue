#!/bin/bash
set -o pipefail
# 499_doubles_truth (Finder 2026-11-06, queue item 278, from 499_tennis_doubles): item 275's lines read t 5-9 but 37% of doubles games are unresolved under the inferred-result rule, v 12% in singles, and winning outsiders are known to end on less extreme prints (item 67). This is the audit: same entry, four ways to score it. On singles, official results give the known answer for which way of scoring is honest; on doubles no result exists on the box. Same months that suggested it, so it cannot pass. Read only. No tables written. tennis_results_2026 is read from Railway, this one table, as job 499_tennis_preoff_flb.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,tstat
from lib_official import ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def infer(last,lo_,hi_):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
def ev_lay(p,q):
    """Expected P&L of the lay at print p, the runner winning with probability q."""
    return (1-q)*ly(p,False)+q*ly(p,True)
def q_last(lo_,lf):
    """Outsider's win chance from both last prints, overround removed."""
    a,b=1/lo_,1/lf; return a/(a+b)
# known answers: lay 4.9 fills 5.0, stake 2.5; q 0.2: 0.8*2.45-0.2*10=-0.04. Last prints 2 and 2: 0.5. 4 and 1.25: 0.25/(0.25+0.8)=0.238095
assert abs(ev_lay(4.9,0.2)-(-0.04))<1e-9 and q_last(2,2)==0.5 and abs(q_last(4,1.25)-0.25/1.05)<1e-9
assert infer({'a':1.05,'b':20},1.10,5.0)=='a' and infer({'a':1.2,'b':5},1.10,5.0) is None
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score FROM tennis_results_2026 WHERE tourney_date>='2024-08-01'",rc); rc.close()
ix=defaultdict(list)
for r in TR.itertuples(): ix[frozenset((fold(r.winner_norm),fold(r.loser_norm)))].append((r.tourney_date,fold(r.winner_norm),r.score))
print("official singles results",len(TR),f"{time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Tennis' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND (event_name LIKE '%/%' OR abs(hashtext(market_id))%4=0)"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con)
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P['dbl']=P.ev.str.contains('/',regex=False); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0]); d=bool(g.dbl.iloc[0]); tag='D ' if d else 'S '
    if (ev,o) in seen: C[tag+'second id']+=1; continue
    seen.add((ev,o)); run=g.sel.unique()
    if len(run)!=2: C[tag+'not two runners']+=1; continue
    pre=g[~g.inplay]; last=g[g.inplay].groupby('sel').ltp.last().to_dict(); en={}
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is not None: en[s]=(float(px[i]),ts,px,i)
    if len(en)!=2: C[tag+'both not priced']+=1; continue
    f,b=sorted(en,key=lambda z:en[z][0])
    if en[f][0]==en[b][0]: C[tag+'level']+=1; continue
    _,ts,px,i=en[b]; p=fill(ts,px,i,'L')
    if not 3.0<=p<20.0: C[tag+'outsider outside 3-20']+=1; continue
    w=infer(last,1.10,5.0); both=(b in last and f in last)
    m1=None if w is None else ly(p,w==b)
    m2=ly(p,last[b]<last[f]) if both and last[b]!=last[f] else None
    ze=ev_lay(p,1/step(p,1))
    m3=m1 if m1 is not None else (ev_lay(p,q_last(last[b],last[f])) if both else ze)
    m4=m1 if m1 is not None else ze
    offi=None
    if not d:
        nm={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date(); h=[x for x in ix.get(frozenset(nm),[]) if -2<=(day-x[0]).days<=21]
        if len(h)==1 and not re.search(r"W/O|WO|WALK",str(h[0][2]).upper()): offi=ly(p,nm[h[0][1]]==b)
    rows.append((d,o,p,w is None,both,m1,m2,m3,m4,offi,last.get(b),last.get(f),ts[i]))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='dbl off p un both m1 m2 m3 m4 offi lo lf tse'.split()); md=float(np.median(D[D.dbl].off))
print("split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
def show(x,cols,lab):
    out=[]
    for nm,c in cols:
        z=x[x[c].notna()]
        if len(z)<30: continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(score=nm,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
    print("\n"+lab); print(pd.DataFrame(out).round(3).to_string(index=False))
CO=[('M1 268 rule, resolved only','m1'),('M2 lower last print wins','m2'),('M3 unresolved at last-print odds','m3'),('M4 unresolved at zero edge','m4')]
Si=D[~D.dbl&D.offi.notna()]
show(Si,CO+[('OFFICIAL, the known answer','offi')],"SINGLES with an official result, the known answer for each way of scoring")
Sm=Si[Si.m1.notna()]; print("official result v 268 rule on resolved singles, agree share:",round(float(((Sm.offi<0)==(Sm.m1<0)).mean()),4),"n",len(Sm))
x=Si.assign(res=~Si.un); print("official outsider win rate, resolved v unresolved singles:",x.groupby('res').offi.agg(n='size',won=lambda v:float((v<0).mean())).round(3).to_dict('index'),"implied",round(float((1/Si.p).mean()),3))
Do=D[D.dbl]; show(Do,CO,"DOUBLES, no official result on the box")
print("doubles games",len(Do),"unresolved",int(Do.un.sum()),"share",round(float(Do.un.mean()),3),"no last print on a runner",int((~Do.both).sum()),"| singles share unresolved",round(float(D[~D.dbl].un.mean()),3))
U=Do[Do.un&Do.both]; print("unresolved doubles with both last prints",len(U),"outsider's last print lower",round(float((U.lo<U.lf).mean()),3),"implied at entry",round(float((1/U.p).mean()),3),"median last prints, outsider",U.lo.median(),"favourite",U.lf.median())
R_=Do[~Do.un]; tot=float(R_.m1.sum()); print(f"resolved P&L {tot:.0f}; share of the {int(Do.un.sum())} unresolved that must be outsider wins to take it to zero: {tot/10/max(1,int(Do.un.sum())):.3f}; resolved outsider win rate {float((R_.m1<0).mean()):.3f} v implied {float((1/R_.p).mean()):.3f}")
print("doubles M3 by half-year:",Do.groupby(pd.to_datetime(Do.off,unit='s').dt.to_period('2Q').astype(str)).m3.agg(['size','mean']).round(3).to_dict('index'))
print("doubles M3 by price:",Do.groupby(pd.cut(Do.p,[3,4,6,10,20],right=False),observed=True).m3.agg(['size','mean']).round(3).to_dict('index'))
print("\n== touch: first in-play ip_tape row per runner, doubles v singles, ticks from back to lay")
T=pd.read_sql("SELECT DISTINCT ON (event_name,sel_name) event_name,sel_name,ts,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l FROM ip_tape WHERE lower(sport) LIKE 'tennis%' AND market_type='MATCH_ODDS' AND back_px>0 AND lay_px>0 AND ltp>=3 AND ltp<20 ORDER BY event_name,sel_name,ts",con); con.close()
from lib_cand import LD
tk=lambda v:np.searchsorted(LD,np.round(v.astype(float),2)-1e-9)
T['sp']=tk(T.l)-tk(T.b); T['dbl']=T.event_name.str.contains('/',regex=False)
print("rows",len(T),"newest",T.ts.max(),"oldest",T.ts.min()); print(T.groupby('dbl').agg(n=('sp','size'),games=('event_name','nunique'),sp_p25=('sp',lambda v:v.quantile(.25)),sp_p50=('sp','median'),sp_p75=('sp',lambda v:v.quantile(.75))).to_string())
print("\n== SURVIVORS: none can pass here, the months suggested it and the doubles results are inferred"); print(f"total {time.time()-T0:.0f}s")
PY
