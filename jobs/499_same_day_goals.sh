#!/bin/bash
set -o pipefail
# 499_same_day_goals (Finder 2026-11-05, queue item 180, Finder's own, source c): are goals earlier today, or last round, priced into Over 2.5 and BTTS? Rule pushed to the queue before any price was read. Idea from jobs/499_meeting_today.sh on racing.
# SIGNAL uses only games kicked off at least 115 minutes before this one. SD: same league, same UTC date, n>=2, mean goals >=3.5 HIGH, <=1.5 LOW, else MID. LB: same league, 115 minutes to 96 hours earlier, n>=5, mean v the league's season to date (n>=30, games before this one), +0.75 HIGH, -0.75 LOW, else MID.
# ENTRY first print tape 0..5, worse of it and the next within 2, one tick adverse, no trade if a goal has come by that minute. No print: no trade, never a forward fill. Held to the result, 2% commission, £10 risk, one bet per game per line. Halves by season.
# The signal counts every game in af_fixtures, mapped or not; the trades are on mapped games. The idea predicts HIGH lay Over, LOW back Over; all lines are read.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_inplay; lib_cand._checks(); lib_inplay.checks()
from lib_inplay import *
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time(); GAP=115*60; LB=96*3600
def bucket_sd(g):
    if len(g)<2: return None
    m=float(np.mean(g)); return 'HIGH' if m>=3.5 else 'LOW' if m<=1.5 else 'MID'
def bucket_lb(g,base):
    if len(g)<5 or len(base)<30: return None
    x=float(np.mean(g))-float(np.mean(base)); return 'HIGH' if x>=0.75 else 'LOW' if x<=-0.75 else 'MID'
def signals(ks,gl,days,K,dday):
    """ks kick-off seconds sorted, gl goals, days UTC date, for one league-season. K, dday: this game. Strictly games at least GAP earlier, so its own goals and a game still running cannot enter."""
    j=int(np.searchsorted(ks,K-GAP,side='right'))
    sd=[gl[i] for i in range(j) if days[i]==dday]
    lb=[gl[i] for i in range(j) if ks[i]>=K-LB]
    return bucket_sd(sd),bucket_lb(lb,gl[:j])
# known answers, worked by hand
assert bucket_sd([5]) is None and bucket_sd([4,3])=='HIGH' and bucket_sd([1,2])=='LOW' and bucket_sd([3,3])=='MID' and bucket_sd([1,1,3])=='MID'
assert bucket_lb([3]*4,[3]*30) is None and bucket_lb([3]*5,[3]*29) is None and bucket_lb([4]*5,[3]*30)=='HIGH' and bucket_lb([2]*5,[3]*30)=='LOW' and bucket_lb([3]*5,[3]*30)=='MID'
_k=[0,3600,7200,7200+GAP]; _g=[6,6,0,9]; _d=[1,1,1,1]
# Game at 7200+GAP: games at 0, 3600, 7200 are in, itself is not. Mean (6+6+0)/3 = 4.0, HIGH. A game at 7199+GAP: 7200 is 1 s too recent, mean 6, HIGH; at 3600+GAP-1: only game 0, n=1, no signal.
assert signals(_k,_g,_d,7200+GAP,1)[0]=='HIGH' and signals(_k,_g,_d,3600+GAP-1,1)[0] is None
assert signals([0,GAP],[0,0],[1,1],2*GAP,1)[0]=='LOW'
assert signals([0,GAP],[9,9],[0,0],2*GAP,1)[0] is None    # earlier games on another date are not same-day
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season IN (2024,2025)",con)
F['ks']=(pd.to_datetime(F.kickoff,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); F['day']=pd.to_datetime(F.kickoff,utc=True).dt.date; F['g']=F.hg+F.ag
SIG={}
for _,x in F.sort_values('ks').groupby(['league_id','season'],sort=False):
    ks=x.ks.values; gl=[int(v) for v in x.g.values]; dy=list(x.day.values)
    for i,r in enumerate(x.itertuples()): SIG[r.fixture_id]=signals(ks,gl,dy,r.ks,r.day)
M=pd.read_sql("SELECT event_id,substr(understat_id,3)::bigint AS fixture_id FROM af_price_map",con).merge(F,on='fixture_id')
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) AS fg FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,M.fixture_id)),))
FG=dict(zip(EV.fixture_id,EV.fg)); EID=list(M.event_id.unique()); px=defaultdict(dict)
print("fixtures",len(F),"mapped",len(M),"SD buckets",Counter(v[0] for v in SIG.values()),"LB buckets",Counter(v[1] for v in SIG.values()),flush=True)
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='OU25' AND sel='OVER') OR (mkt='BTTS' AND sel='YES')) AND minute BETWEEN 0 AND 8 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,mk),g in P.groupby(['event_id','mkt'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][mk]=a
    print(f"  prices {min(i+1000,len(EID))}/{len(EID)} | {time.time()-T0:.0f}s",flush=True)
con.close()
rows=[]; SK=Counter()
for r in M.itertuples():
    b=px.get(r.event_id)
    if not b: SK['no prices']+=1; continue
    h=1 if r.season==2024 else 2; sd,lb=SIG[r.fixture_id]; fg=FG.get(r.fixture_id)
    if r.hg+r.ag>0 and fg is None: SK['goals but no goal rows']+=1; continue
    for mk,won in (('OU25',r.hg+r.ag>2.5),('BTTS',r.hg>0 and r.ag>0)):
        arr=b.get(mk)
        if arr is None: SK[f'{mk} no prices']+=1; continue
        for side in 'BL':
            e=enter(arr,0,5,side)
            if e is None: SK[f'{mk} no print or no bet']+=1; continue
            d,fx=e
            if fg is not None and fg<=d: SK[f'{mk} goal by entry']+=1; continue
            v=settle(side,fx,won); sn='BACK' if side=='B' else 'LAY'
            rows.append(('ALL','ALL',mk,sn,h,r.event_id,v,won,1/fx))
            if sd: rows.append(('SD',sd,mk,sn,h,r.event_id,v,won,1/fx))
            if lb: rows.append(('LB',lb,mk,sn,h,r.event_id,v,won,1/fx))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='fam state mkt side h g v won imp'.split()); o=[]
for k,x in T.groupby(['fam','state','mkt','side']):
    d=line(x.v.values,x.h.values); o.append(dict(zip(['fam','state','mkt','side'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],won=round(x.won.mean(),3),implied=round(x.imp.mean(),3),PASS=d['PASS']))
L=pd.DataFrame(o).sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {(L.n>=300).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s\n"); print(L.drop(columns=['n1','n2']).to_string(index=False))
print("\n== SURVIVORS"); P=L[L.PASS]; print(P.drop(columns=['n1','n2']).to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
