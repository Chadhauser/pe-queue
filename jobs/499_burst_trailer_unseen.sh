#!/bin/bash
set -o pipefail
# 499_burst_trailer_unseen (Finder 2026-11-05, queue item 135, from jobs/499_goal_timing.sh): lay the trailer on MO after two quick goals in 46-69, on Jul-Sep 2026, which did not choose the line. Rule written in the queue before any 2026 price was read. Read only.
# UNSEEN as jobs/499_late_ht_draw_unseen.sh: af_fixtures, af_events x bf_hist_other MATCH_ODDS, lib_cand.loose, market time within 20 min of the af kick-off, games matched to one market.
# SIGNAL goal k>=2 at af minute 46-69, at most 5 min after the previous goal, previous also in the second half. Sides from af_events is_home, own goals flipped if that is what makes the sides add up to the score, else dropped.
# CLOCK wall clock only. Restart taken as KO+63 min, so goal minute g is about KO+63+(g-46). Entry first in-play print on the trailer from that + 5 min, within 4 min, worse of it and the next print within 2 min, one tick adverse. A later goal with af minute <= 46 + (print - KO - 63 min) + 1 drops the trade, counted. The clock is an estimate.
# BAR about 60-80 trades, so n >= 300 is out of reach and no line can pass. A negative read closes it.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_000_000_000,3_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
T0=time.time()
def side_fix(rows,hg):
    """As jobs/499_goal_timing.sh."""
    raw=[(m,h) for m,h,o in rows]
    if None in [h for _,h in raw]: return None
    if sum(1 for _,h in raw if h)==hg: return raw
    fl=[(m,(not h) if o else h) for m,h,o in rows]
    return fl if sum(1 for _,h in fl if h)==hg else None
def bursts(g):
    """g (minute, is_home) in order. Yields (k, trailer 'H' or 'A', kind) for goal k>=1 at 46-69, previous goal in the second half and at most 5 min earlier, with a side trailing."""
    for k in range(1,len(g)):
        m,h=g[k]; pm,ph=g[k-1]
        if not 46<=m<=69 or pm<46 or m-pm>5: continue
        hs=sum(1 for _,x in g[:k+1] if x); a=k+1-hs
        if hs==a: continue
        yield k,('A' if hs>a else 'H'),('CL_SAME' if h==ph else 'CL_SWAP')
def later_seen(g,k,t,ko):
    lim=46+(t-ko-63*60)/60+1
    return any(x<=lim for x,_ in g[k+1:])
_g=[(10,True),(50,True),(53,True),(60,False),(90,False)]
assert list(bursts(_g))==[(2,'A','CL_SAME')] and list(bursts([(47,True),(50,False)]))==[] and list(bursts([(44,True),(47,True)]))==[] and list(bursts([(47,True),(52,True)]))==[(1,'A','CL_SAME')] and list(bursts([(47,True),(53,True)]))==[]
assert list(bursts([(47,True),(49,True),(52,False)]))==[(1,'A','CL_SAME'),(2,'A','CL_SWAP')]
assert side_fix([(5,True,False),(9,False,True)],2)==[(5,True),(9,True)] and side_fix([(5,True,False),(9,False,False)],2) is None
assert later_seen([(50,True),(52,True)],0,63*60+300.0,0) and not later_seen([(50,True),(53,True)],0,63*60+300.0,0)   # 5 min after restart: limit 46+5+1 = 52
assert abs(lay_settle(step(40,1),False)-10/(step(40,1)-1)*.98)<1e-9 and lay_settle(step(40,1),True)==-10.0
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff>='2026-07-01' AND kickoff<'2026-10-01' AND league_id NOT IN (2,3)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:t.timestamp()); F['H']=F.home.map(norm); F['A']=F.away.map(norm); F=F.sort_values('ks').reset_index(drop=True); ksv=F.ks.values
E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,coalesce(extra,0) ex,is_home,detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') ORDER BY 1,2,3",con,params=(list(map(int,F.fixture_id)),))
RAW=defaultdict(list)
for a,b,c,d in zip(E.fixture_id,E.mn,E.is_home,E.detail): RAW[int(a)].append((int(b),None if c is None or c!=c else bool(c),d=='Own Goal'))
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",('MATCH_ODDS','MATCH_ODDT','MATCH_ODDT'))
ids=[r[0] for r in cur.fetchall() if '|' in r[0]]; seen=defaultdict(list)
for mid in ids:
    _,ev,mt=mid.split('|',2)
    if ' v ' not in ev: continue
    ms=pd.Timestamp(mt).timestamp(); lo,hi=np.searchsorted(ksv,ms-1200),np.searchsorted(ksv,ms+1200,side='right')
    if hi<=lo: continue
    h,_,a=ev.partition(' v '); idx=loose(norm(h),norm(a),[(F.H.iat[i],F.A.iat[i],i) for i in range(lo,hi)])
    if idx is not None: seen[idx].append((mid,h.strip(),a.strip(),ms))
one={k:v[0] for k,v in seen.items() if len(v)==1}; print(f"af games {len(F)}; matched to one market {len(one)}; {time.time()-T0:.0f}s",flush=True)
SK=Counter(); items=[]
for i,(mid,h,a,ms) in one.items():
    f=F.iloc[i]; r=RAW.get(int(f.fixture_id),[])
    if len(r)!=f.hg+f.ag: SK['events differ from score']+=1; continue
    g=side_fix(r,f.hg)
    if g is None: SK['sides do not add up']+=1; continue
    for k,tr,kind in bursts(g):
        items.append((mid,h if tr=='H' else a,ms,g,k,kind,int(f.fixture_id),f.ks,(f.hg>f.ag) if tr=='H' else (f.ag>f.hg)))
print(f"burst signals {len(items)}",flush=True); rows=[]; mids=sorted({x[0] for x in items})
for c in range(0,len(mids),300):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+300],))
    P['tt']=(pd.to_datetime(P.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); PX={}
    for (m,s),x in P.groupby(['market_id','sel'],sort=False): x=x.sort_values('tt'); PX[(m,s)]=(x.tt.values,x.ltp.values)
    cs=set(mids[c:c+300])
    for mid,name,ms,g,k,kind,fx,ks,won in [x for x in items if x[0] in cs]:
        z=PX.get((mid,name))
        if z is None: SK['runner rows missing']+=1; continue
        t0=ms+(63+g[k][0]-46+5)*60; e=entry_px(z[0],z[1],t0,'L',window=240,nxt=120)
        if e is None: SK['no print']+=1; continue
        if later_seen(g,k,z[0][e[0]],ms): SK['later goal seen']+=1; continue
        rows.append((kind,fx,ks,e[1],bool(won),lay_settle(step(e[1],1),bool(won))))
con.close(); print("counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns=['kind','fx','ks','x','won','v'])
if R.empty: print("no trades"); sys.exit(0)
R['h']=np.where(R.ks<R.ks.median(),1,2)
print("\n== lay the trailer after a second-half burst, Jul-Sep 2026; halves by median date")
for name,x in list(R.groupby('kind'))+[('ALL',R)]:
    l=line(x.v.values,x.h.values); print(f"  {name}: n {l['n']} games {x.fx.nunique()} per10 {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}) won {x.won.mean():.3f} implied {(1/x.x).mean():.3f} worst {x.v.min():.1f}")
print("\n== SURVIVORS: none can pass at this n; a negative read closes it"); print(f"done {time.time()-T0:.0f}s")
PY
