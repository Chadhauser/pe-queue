#!/bin/bash
set -o pipefail
# 499_clock_unseen (Finder 2026-11-05, queue item 128, Finder's own, source c): item 127's two best lines on Jul-Sep 2026, months that test did not see. Rule written in the queue before any 2026 price was read. No new cuts. The number 499 is reused with a new slug: 450-499 are all taken.
# TAPE bf_hist_other Soccer MATCH_ODDS, OVER_UNDER_25, first in-play print. af_fixtures FT, af_events first goal. Read-only, local DB. LTP only, so a pass is an upper bound.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,norm,loose,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time(); FROM,TO='2026-07-01','2026-10-01'
def hdist(a,b):
    d=abs(a-b)%24; return min(d,24-d)
def role(sel,ev):
    """Which side of the book a runner is: the event name gives home and away."""
    h,_,a=str(ev).partition(' v '); s=str(sel).strip().lower()
    if s=='over 2.5 goals': return 'OVER'
    if s=='under 2.5 goals': return 'UNDER'
    if s==h.strip().lower(): return 'HOME'
    if s==a.strip().lower(): return 'AWAY'
    return None
# known answers
assert role('Over 2.5 Goals','A v B')=='OVER' and role('Under 2.5 Goals','A v B')=='UNDER' and role('Leeds','Leeds v Hull')=='HOME' and role('hull ','Leeds v Hull')=='AWAY' and role('The Draw','Leeds v Hull') is None
assert hdist(23,1)==2 and hdist(15.5,15)==.5
assert abs(back_settle(step(1.42,-1),True)-4.018)<1e-9 and lay_settle(step(1.42,1),True)==-10.0
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
FX=pd.read_sql(f"SELECT fixture_id,league,kickoff,home,away,hg,ag FROM af_fixtures WHERE kickoff>='{FROM}' AND kickoff<'{TO}' AND status='FT' AND hg IS NOT NULL",con)
FX['k']=pd.to_datetime(FX.kickoff,utc=True); FX=FX.sort_values('k').reset_index(drop=True); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.dt.tz_convert(None).values
L=pd.read_sql("SELECT league,kickoff FROM af_fixtures WHERE status='FT' AND kickoff IS NOT NULL AND season=2025",con); L['hr']=pd.to_datetime(L.kickoff,utc=True).dt.hour
MODE={l:int(x.hr.mode().iloc[0]) for l,x in L.groupby('league') if len(x)>=50}
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,FX.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm))
P=pd.read_sql(f"""SELECT DISTINCT ON (market_id,sel) market_id,market_type,event_name,market_time,sel,ts,ltp::float8 ltp FROM bf_hist_other
  WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25') AND market_time>='{FROM}' AND market_time<'{TO}' AND inplay AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,sel,ts""",con); con.close()
P['mt']=pd.to_datetime(P.market_time,utc=True); P['tt']=pd.to_datetime(P.ts,utc=True)
print(f"fixtures {len(FX):,}; first in-play prints {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
Mp={}
for (ev,mt),_ in P.groupby(['event_name','mt'],sort=False):
    h,_,a=str(ev).partition(' v ')
    lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(hours=12)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(hours=12)).tz_convert(None)),side='right')
    Mp[(ev,mt)]=loose(norm(h),norm(a),[(r.H,r.A,int(r.fixture_id)) for r in FX.iloc[lo:hi].itertuples()])
print(f"events {len(Mp):,}, matched {sum(v is not None for v in Mp.values()):,}, fixtures hit {len({v for v in Mp.values() if v is not None}):,}",flush=True)
by=FX.set_index('fixture_id'); rows=[]; drop=dict(nomatch=0,lag=0,goal=0,norole=0)
for r in P.itertuples():
    fx=Mp.get((r.event_name,r.mt))
    if fx is None: drop['nomatch']+=1; continue
    f=by.loc[fx]; lag=(r.tt-f.k).total_seconds()/60
    if lag<-5 or lag>20: drop['lag']+=1; continue
    gm=first_goal.get(fx)
    if gm is not None and gm<lag: drop['goal']+=1; continue
    ro=role(r.sel,r.event_name)
    if ro is None:
        if str(r.sel).strip().lower()!='the draw': drop['norole']+=1
        continue
    hf=f.k.hour+f.k.minute/60; mode=MODE.get(f.league); over=f.hg+f.ag>2.5
    rows.append(dict(fx=fx,k=f.k,ro=ro,px=r.ltp,won=(over if ro=='OVER' else (not over) if ro=='UNDER' else (f.hg>f.ag if ro=='HOME' else f.ag>f.hg)),h20=hf>=20,usual=(mode is not None and hdist(hf,mode)<1)))
T=pd.DataFrame(rows).drop_duplicates(['fx','ro'])
print("dropped",drop,"; trades",len(T),"; games",T.fx.nunique(),flush=True)
def report(name,d,side):
    v=np.array([back_settle(step(p,-1),w) if side=='BACK' else lay_settle(step(p,1),w) for p,w in zip(d.px,d.won)]); med=d.k.median(); h=np.where(d.k<med,1,2); o=line(v,h)
    print(f"  {name} {side}: n {o['n']} games {d.fx.nunique()} per10 {o['per10']:+.3f} t {o['t']:.2f} h1 {o['h1']:+.3f} (n {o['n1']}) h2 {o['h2']:+.3f} (n {o['n2']}) won {d.won.mean():.3f} imp {(1/d.px).mean():.3f} PASS {o['PASS']}")
    return o['PASS']
print("== the three lines fixed in the queue"); ok=[]
ok.append(report('H20+ AWAY',T[T.h20&(T.ro=='AWAY')],'LAY')); ok.append(report('S_USUAL UNDER',T[T.usual&(T.ro=='UNDER')],'LAY')); ok.append(report('S_USUAL OVER',T[T.usual&(T.ro=='OVER')],'BACK'))
print("== control: every game"); report('ALL AWAY',T[T.ro=='AWAY'],'LAY'); report('ALL UNDER',T[T.ro=='UNDER'],'LAY'); report('ALL OVER',T[T.ro=='OVER'],'BACK')
print("== SURVIVORS"); print("  "+("see PASS True above" if any(ok) else "none"))
print(f"done {time.time()-T0:.0f}s")
PY
