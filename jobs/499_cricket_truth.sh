#!/bin/bash
set -o pipefail
# 499_cricket_truth (Finder 2026-11-06, queue item 279, from 499_cricket_outsider and 499_doubles_truth): item 278 showed on tennis singles that scoring only resolved games, or unresolved at zero edge, flatters a lay of the outsider. Item 271's cricket lead was scored those two ways, and said no cricket result was on the box, but cricket_matches on Railway holds one to 27 Apr 2026. Same entry as 271, unchanged. Same months that chose it, so it cannot pass. Read only. No tables written. cricket_matches is read from Railway, this one table, as job 499_final_print_bias.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,norm
from lib_official import ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last,lo_,hi_):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
def ev_lay(p,q): return (1-q)*ly(p,False)+q*ly(p,True)
def q_last(lo_,lf): a,b=1/lo_,1/lf; return a/(a+b)
assert abs(ev_lay(4.9,0.2)-(-0.04))<1e-9 and abs(q_last(4,1.25)-0.25/1.05)<1e-9
assert norm('Sydney Sixers')==norm('sydney sixers') and norm('England')!=norm('Pakistan')
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); CM=pd.read_sql("SELECT match_date,team1,team2,winner,competition FROM cricket_matches WHERE match_date>='2024-08-25'",rc); rc.close()
ix=defaultdict(list)
for r in CM.itertuples(): ix[frozenset((norm(r.team1),norm(r.team2)))].append((r.match_date,r.winner))
print("official",len(CM),CM.match_date.min(),CM.match_date.max(),"winner NULL",round(float(CM.winner.isna().mean()),3),flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id']+=1; continue
    seen.add((ev,o)); runners=g.sel.unique()
    if len(runners)!=2: C['not two runners']+=1; continue
    pre=g[~g.inplay]; last=g[g.inplay].groupby('sel').ltp.last().to_dict(); en={}
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is not None: en[s]=(float(px[i]),ts,px,i)
    if len(en)!=2: C['both runners not priced']+=1; continue
    f,b=sorted(en,key=lambda z:en[z][0])
    if en[f][0]==en[b][0]: C['level']+=1; continue
    _,ts,px,i=en[b]; p=fill(ts,px,i,'L')
    if not 3.0<=p<20.0: C['outsider outside 3-20']+=1; continue
    w=infer(last,1.10,5.0); both=(b in last and f in last)
    m1=None if w is None else ly(p,w==b)
    m2=ly(p,last[b]<last[f]) if both and last[b]!=last[f] else None
    ze=ev_lay(p,1/step(p,1))
    m3=m1 if m1 is not None else (ev_lay(p,q_last(last[b],last[f])) if both else ze)
    m4=m1 if m1 is not None else ze
    offi=None; h_,_,a_=str(ev).partition(' v '); day=pd.Timestamp(g.mt.iloc[0]).date()
    hits=[x for dd,x in ix.get(frozenset((norm(h_),norm(a_))),[]) if abs((dd-day).days)<=1]
    if len(hits)==1 and hits[0] is not None:
        tw=[s for s in runners if norm(s)==norm(hits[0])]
        if len(tw)==1: offi=ly(p,tw[0]==b); C['official scored']+=1
        else: C['official winner name no match']+=1
    elif len(hits)==1: C['official no winner']+=1
    else: C['no unique official match']+=1
    rows.append((o,p,w is None,m1,m2,m3,m4,offi,None if offi is None else ly(step(p,4),offi<0)))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='off p un m1 m2 m3 m4 offi o5'.split()); md=float(np.median(D.off)); print("games",len(D),"unresolved",int(D.un.sum()),"split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
def show(x,cols,lab):
    out=[]
    for nm,c in cols:
        z=x[x[c].notna()]
        if len(z)<30: continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(score=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],PASS_numbers=l['PASS']))
    print("\n"+lab); print(pd.DataFrame(out).round(3).to_string(index=False))
CO=[('M1 268 rule, resolved only, as 271','m1'),('M2 lower last print wins','m2'),('M3 unresolved at last-print odds','m3'),('M4 unresolved at zero edge, as 271','m4')]
show(D,CO,"ALL games, item 271's entry")
Si=D[D.offi.notna()]
show(Si,CO+[('OFFICIAL, the known answer','offi'),('OFFICIAL, 5 ticks adverse','o5')],"Games with an official winner, known answer")
x=Si.assign(res=~Si.un); print("official outsider win rate, resolved v unresolved:",x.groupby('res').offi.agg(n='size',won=lambda v:float((v<0).mean())).round(3).to_dict('index'),"implied",round(float((1/Si.p).mean()),3))
print("official by price:",Si.groupby(pd.cut(Si.p,[3,4,6,10,20],right=False),observed=True).offi.agg(['size','mean']).round(3).to_dict('index'))
print("\n== SURVIVORS: none can pass here, these months chose the line"); print(f"total {time.time()-T0:.0f}s")
PY
