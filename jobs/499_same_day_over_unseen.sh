#!/bin/bash
set -o pipefail
# 499_same_day_over_unseen (Finder 2026-11-05, queue item 182, Finder's own, source a): item 180's SD HIGH back Over on games that test did not see. Rule pushed to the queue before any of these prices was read. No new cuts.
# SIGNAL SD as jobs/499_same_day_goals.sh: same league and season, same UTC date, kicked off at least 115 minutes earlier, n>=2, mean goals >=3.5.
# TAPE bf_hist_other OVER_UNDER_25 'Over 2.5 Goals', LTP only, so a pass is an upper bound. Kick-offs from 1 Jul 2026, games in af_price_map out. Names matched with lib_cand.loose, as jobs/499_clock_unseen.sh.
# ENTRY first in-play print within 6 minutes of kick-off, worse of it and the next in-play print within 120 s, one tick adverse, no trade if a goal has come by then. Never forward-filled. Held to the result, 2% commission, £10 risk, one bet per game. Halves by median date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,norm,loose,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250)
T0=time.time(); GAP=115*60; FROM='2026-07-01'
def sd_high(ks,gl,days,K,dday):
    """True or False if at least 2 same-day games kicked off at least GAP earlier, else None."""
    j=int(np.searchsorted(ks,K-GAP,side='right')); g=[gl[i] for i in range(j) if days[i]==dday]
    return None if len(g)<2 else float(np.mean(g))>=3.5
def entry(lag,px,lag2,px2):
    """First in-play print at lag minutes after kick-off. Fill one tick adverse from the worse of it and the next print within 2 minutes. None if outside the window or at the bottom of the ladder."""
    if lag<-5 or lag>6: return None
    p=px if lag2 is None or lag2-lag>2 else min(px,px2)
    a=step(p,-1); return None if a<=1.01 else a
# known answers, worked by hand
assert sd_high([0,3600,3600+GAP],[4,3,9],[1,1,1],3600+GAP,1) is True and sd_high([0,3600],[1,1],[1,1],3600+GAP,1) is False
assert sd_high([0],[9],[1],GAP,1) is None and sd_high([0,0],[9,9],[0,0],GAP,1) is None and sd_high([0,1],[9,9],[1,1],GAP,1) is None   # one game; another date; too recent for the second (1+GAP>GAP)
assert entry(1,2.0,1.5,1.9)==1.89 and entry(1,2.0,None,None)==1.99 and entry(1,2.0,4,1.5)==1.99 and entry(7,2.0,None,None) is None and entry(1,1.02,None,None) is None
assert abs(back_settle(1.89,True)-8.722)<1e-9 and back_settle(1.89,False)==-10.0   # 10*0.89*0.98
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season IN (2025,2026)",con)
F['k']=pd.to_datetime(F.kickoff,utc=True); F['ks']=(F.k-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); F['day']=F.k.dt.date; F['g']=F.hg+F.ag
SIG={}
for _,x in F.sort_values('ks').groupby(['league_id','season'],sort=False):
    ks=x.ks.values; gl=[int(v) for v in x.g.values]; dy=list(x.day.values)
    for r in x.itertuples(): SIG[r.fixture_id]=sd_high(ks,gl,dy,r.ks,r.day)
SEEN=set(pd.read_sql("SELECT substr(understat_id,3)::bigint AS f FROM af_price_map",con).f)
FX=F[(F.k>=pd.Timestamp(FROM,tz='UTC'))&(~F.fixture_id.isin(SEEN))].sort_values('k').reset_index(drop=True); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.dt.tz_convert(None).values
print(f"fixtures from {FROM}, unseen {len(FX)}, {FX.k.min()}..{FX.k.max()}; SD HIGH {sum(SIG[i] is True for i in FX.fixture_id)}",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,FX.fixture_id)),)); FG=dict(zip(EV.fixture_id,EV.gm))
P=pd.read_sql(f"""SELECT market_id,event_name,market_time,ts,ltp FROM (SELECT market_id,event_name,market_time,ts,ltp::float8 ltp,row_number() OVER (PARTITION BY market_id ORDER BY ts) rn FROM bf_hist_other
  WHERE sport='Soccer' AND market_type='OVER_UNDER_25' AND lower(trim(sel))='over 2.5 goals' AND market_time>='{FROM}' AND inplay AND ltp>=1.01 AND ltp<1000) x WHERE rn<=2 ORDER BY market_id,ts""",con); con.close()
P['mt']=pd.to_datetime(P.market_time,utc=True); P['tt']=pd.to_datetime(P.ts,utc=True)
print(f"markets {P.market_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
Mp={}; by=FX.set_index('fixture_id'); rows=[]; SK=Counter()
for mid,g in P.groupby('market_id',sort=False):
    a=g.iloc[0]; key=(a.event_name,a.mt)
    if key not in Mp:
        h,_,aw=str(a.event_name).partition(' v ')
        lo=np.searchsorted(kt,np.datetime64((a.mt-pd.Timedelta(hours=12)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((a.mt+pd.Timedelta(hours=12)).tz_convert(None)),side='right')
        Mp[key]=loose(norm(h),norm(aw),[(r.H,r.A,int(r.fixture_id)) for r in FX.iloc[lo:hi].itertuples()])
    fx=Mp[key]
    if fx is None: SK['no fixture match']+=1; continue
    f=by.loc[fx]; lag=(a.tt-f.k).total_seconds()/60; lag2,px2=(None,None) if len(g)<2 else ((g.iloc[1].tt-f.k).total_seconds()/60,float(g.iloc[1].ltp))
    fx_a=entry(lag,float(a.ltp),lag2,px2)
    if fx_a is None: SK['no entry in the window or no bet']+=1; continue
    gm=FG.get(fx)
    if gm is not None and gm<=max(lag,0): SK['goal by entry']+=1; continue
    won=bool(f.hg+f.ag>2.5); rows.append((fx,f.k,SIG.get(fx),back_settle(fx_a,won),won,1/fx_a))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='fx k sig v won imp'.split()).drop_duplicates('fx')
def rep(name,d):
    if not len(d): print(f"  {name}: n 0"); return False
    md=d.k.median(); o=line(d.v.values,np.where(d.k<md,1,2))
    print(f"  {name}: n {o['n']} games {d.fx.nunique()} per10 {o['per10']:+.3f} t {o['t']:.2f} h1 {o['h1']:+.3f} (n {o['n1']}) h2 {o['h2']:+.3f} (n {o['n2']}) won {d.won.mean():.3f} implied {d.imp.mean():.3f} maxwin {o['maxwin']:.1f} PASS {o['PASS']}")
    return o['PASS']
print("== the one line fixed in the queue"); ok=rep('SD HIGH back Over',T[T.sig==True])
print("== controls"); rep('SD not HIGH back Over',T[T.sig==False]); rep('no SD signal back Over',T[T.sig.isna()]); rep('every game back Over',T)
print("== SURVIVORS"); print("  "+("SD HIGH back Over" if ok else "none"))
print(f"done {time.time()-T0:.0f}s")
PY
