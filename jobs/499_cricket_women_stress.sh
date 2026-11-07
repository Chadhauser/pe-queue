#!/bin/bash
set -o pipefail
# 499_cricket_women_stress (Finder 2026-11-07, queue item 367, Finder's own, source a; from jobs/499_cricket_women.sh and jobs/499_cricket_truth.sh): item 366's two women's lines at 1, 3, 5 ticks, official winners where matched, thin v thick. Same games, so it cannot pass. Read only, no tables written. cricket_matches is read from Railway, this one table, as job 499_cricket_truth.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,norm,back_settle,lay_settle
from lib_official import fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last):
    lo=[k for k,v in last.items() if v<=1.10]
    if len(lo)!=1 or len(last)<2: return None
    return lo[0] if all(v>=5.0 for k,v in last.items() if k!=lo[0]) else None
def women(ev): return bool(re.search(r'(^|\s)(W|Women)(\s|$)',ev))
def strip(n): return norm(re.sub(r'\s+(W|Women)\s*$','',str(n).strip()))
def q_last(last,s): t=sum(1/v for v in last.values()); return (1/last[s])/t
def val(side,p,k,won):
    """side B backs at p moved k ticks down; side L lays at p moved k ticks up. By hand: back 1.25, 1 tick is 1.24, a win 2.4*.98=2.352; lay 7.0, 1 tick is 7.2, a lose -10, a win 10/6.2*.98=1.5806."""
    if side=='B':
        a=step(p,-k); return None if a<=1.01 else back_settle(a,won)
    return lay_settle(step(p,k),won)
assert abs(val('B',1.25,1,True)-2.352)<1e-9 and val('B',1.25,1,False)==-10 and abs(val('L',7.0,1,False)-10/6.2*.98)<1e-9 and val('L',7.0,1,True)==-10 and val('B',1.02,1,True) is None
assert strip('Lesotho W')==strip('Lesotho') and strip('Victoria Women')==strip('Victoria') and women('Lesotho W v Malawi W') and not women('Canada v USA')
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=30); CM=pd.read_sql("SELECT match_date,team1,team2,winner,competition FROM cricket_matches WHERE match_date>='2024-08-25'",rc); rc.close()
CM=CM[CM.competition.astype(str).str.contains("wom",case=False)|CM.team1.astype(str).str.contains(r'\sW$')]; ix=defaultdict(list)
for r in CM.itertuples(): ix[frozenset((strip(r.team1),strip(r.team2)))].append((r.match_date,r.winner))
print("official women's matches",len(CM),CM.match_date.min(),CM.match_date.max(),flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: continue
    seen.add((ev,o)); runners=g.sel.unique()
    if len(runners)!=2: continue
    pre=g[~g.inplay]; last=g[g.inplay].groupby('sel').ltp.last().to_dict(); w=infer(last) if len(last)==2 else None; wm=women(ev)
    off_w=None
    if wm:
        h_,_,a_=str(ev).partition(' v '); day=pd.Timestamp(g.mt.iloc[0]).date()
        hits=[x for dd,x in ix.get(frozenset((strip(h_),strip(a_))),[]) if abs((dd-day).days)<=1]
        if len(hits)==1 and hits[0] is not None:
            tw=[s for s in runners if strip(s)==strip(hits[0])]
            if len(tw)==1: off_w=tw[0]; C['official matched']+=1
            else: C['official winner name no match']+=1
        else: C['no unique official match']+=1
    prints=len(pre[(pre.tt>=o-3600)&(pre.tt<=o-120)])
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is None: continue
        for side,lab,lo,hi in (('B','<1.5 back',1.01,1.5),('L','6-20 lay',6.0,20.0)):
            p=fill(ts,px,i,side)
            if not lo<=p<hi: continue
            row=[m,o,wm,lab,p,prints,off_w is not None]
            for k in (1,3,5):
                vw,vl=val(side,p,k,True),val(side,p,k,False)
                if vw is None or vl is None: row.append(np.nan); continue
                if off_w is not None: row.append(vw if s==off_w else vl)
                elif w is not None: row.append(vw if s==w else vl)
                elif len(last)==2: q=q_last(last,s); row.append(q*vw+(1-q)*vl)
                else: row.append(np.nan)
            if off_w is not None: row.append(s==off_w)
            elif w is not None: row.append(s==w)
            else: row.append(np.nan)
            rows.append(row)
print("counted:",dict(C),flush=True)
R=pd.DataFrame(rows,columns='m off wm lab p prints official v1 v3 v5 won'.split()); W=R[R.wm]; md=float(np.median(W.off)); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),"prints p50 women",W.prints.median(),"men",R[~R.wm].prints.median(),flush=True)
thin=W.prints.median(); out=[]
def add(nm,x):
    for c,k in (('v1',1),('v3',3),('v5',5)):
        z=x[x[c].notna()]
        if len(z)<20: continue
        l=line(z[c].values,np.where(z.off<md,1,2)); out.append(dict(line=nm,ticks=k,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=z.won.astype(float).mean(),imp=(1/z.p).mean(),maxwin=l['maxwin']))
for lab,x in W.groupby('lab'):
    add('W '+lab,x); add('W '+lab+' OFFICIAL only',x[x.official]); add('W '+lab+' THIN',x[x.prints<thin]); add('W '+lab+' THICK',x[x.prints>=thin])
for lab,x in R[~R.wm].groupby('lab'): add('M '+lab+' control',x)
print(pd.DataFrame(out).round(3).to_string(index=False))
print("\nW <1.5 back by price:",W[W.lab=='<1.5 back'].groupby(pd.cut(W[W.lab=='<1.5 back'].p,[1.01,1.1,1.2,1.3,1.4,1.5],right=False),observed=True).v1.agg(['size','mean']).round(3).to_dict('index'))
print("\n== SURVIVORS: none can pass here, the same games chose the lines"); print(f"total {time.time()-T0:.0f}s")
PY
