#!/bin/bash
set -o pipefail
# 499_cricket_bands_truth (Finder 2026-11-07, queue item 283, Finder's own, source c; entries from jobs/499_cricket_preoff.sh, results from jobs/499_cricket_truth.sh): do item 268's other two bands, 2R <1.5 back and 2R 6-20 lay, hold on official results? Rule pushed in the queue before this read. Same months that chose them, so this keeps or kills the lean and cannot pass. Read only, no tables written. cricket_matches is read from Railway, this one table.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last,lo_=1.10,hi_=5.0):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
def q_last(a,b): x,y=1/a,1/b; return x/(x+y)
def ev(f,p,q): return q*f(p,True)+(1-q)*f(p,False)
# known answers, worked by hand: back 1.4 fills 1.39 wins 3.9 less 2% = 3.822; lay 9.0 fills 9.2 at 8.2 down, stake 10/8.2, wins 1.1951; at q 0.5 back: (3.822-10)/2=-3.089
assert abs(bk(1.4,True)-3.822)<1e-9 and bk(1.4,False)==-10.0 and abs(ly(9.0,False)-10/8.2*.98)<1e-9 and ly(9.0,True)==-10.0
assert abs(ev(bk,1.4,.5)-(-3.089))<1e-9 and abs(q_last(4,1.25)-0.25/1.05)<1e-9 and infer({'a':1.05,'b':20})=='a' and infer({'a':1.2,'b':20}) is None
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); CM=pd.read_sql("SELECT match_date,team1,team2,winner FROM cricket_matches WHERE match_date>='2024-08-25'",rc); rc.close()
ix=defaultdict(list)
for r in CM.itertuples(): ix[frozenset((norm(r.team1),norm(r.team2)))].append((r.match_date,r.winner))
print("official",len(CM),CM.match_date.min(),CM.match_date.max(),flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    e=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (e,o) in seen: C['second id']+=1; continue
    seen.add((e,o)); runners=g.sel.unique()
    if len(runners)!=2: C['not two runners']+=1; continue
    pre=g[~g.inplay]; last=g[g.inplay].groupby('sel').ltp.last().to_dict(); w=infer(last)
    h_,_,a_=str(e).partition(' v '); day=pd.Timestamp(g.mt.iloc[0]).date()
    hits=[x for dd,x in ix.get(frozenset((norm(h_),norm(a_))),[]) if abs((dd-day).days)<=1]
    offi=None
    if len(hits)==1 and hits[0] is not None:
        tw=[s for s in runners if norm(s)==norm(hits[0])]
        if len(tw)==1: offi=tw[0]; C['official scored']+=1
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is None: C['no print in window']+=1; continue
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
        for nm,f,p,cond in (('2R <1.5 back',bk,pb,1.01<=pb<1.5),('2R 6-20 lay',ly,pl,6.0<=pl<20.0)):
            if not cond: continue
            if f(p,True) is None: C['bottom of ladder']+=1; continue
            other=[k for k in runners if k!=s][0]
            if s in last and other in last: q=q_last(last[s],last[other])
            else: q=1/p; C['no last print, entry odds']+=1
            res=None if w is None else f(p,w==s); lpo=ev(f,p,q)
            m3=res if res is not None else lpo
            off_=None if offi is None else f(p,offi==s)
            rows.append(dict(line=nm,off=o,p=p,res=res,lpo=lpo,m3=m3,offi=off_,blend=off_ if off_ is not None else m3,un=w is None))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows); md=float(np.median(D.off)); out=[]
for nm,x in D.groupby('line'):
    for lab,c in (('resolved only, as 268','res'),('unresolved at last-print odds','m3'),('OFFICIAL matched only, the known answer','offi'),('official where matched, else last-print odds (the rule)','blend')):
        z=x[x[c].notna()]
        if len(z)<30: continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm,score=lab,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],bar_on_these_months=l['PASS']))
    print(nm,"games",len(x),"unresolved",int(x.un.sum()),"official",int(x.offi.notna().sum()))
print("\n"+pd.DataFrame(out).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass here, these months chose the lines"); print(f"total {time.time()-T0:.0f}s")
PY
