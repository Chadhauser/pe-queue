#!/bin/bash
set -o pipefail
# 499_c2_one_id (Finder 2026-11-05, queue item 151; re-score, rule unchanged from section B of jobs/499_cand_c2_segunda.sh): that job matches fixtures to OU25 markets with lib_cand.loose, which returns None on a tie, so a game held under two ids was dropped as unmatched. Same rule, read twice: AS_WRITTEN (both ids) and ONE_ID (lowest id per event name and market time). BTTS holds no duplicates (census), so OU25 only. Read only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,loose,line,step,lay_settle
import lib_cand; lib_cand._checks()
# known answer: a tie between two ids is lost, one id is matched
_h,_a=norm('Leeds'),norm('Hull'); assert loose(_h,_a,[(_h,_a,'x'),(_h,_a,'y')]) is None and loose(_h,_a,[(_h,_a,'x')])=='x'
print("checks: OK",flush=True); T0=time.time(); E0=pd.Timestamp('1970-01-01',tz='UTC')
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
LG={141:'Segunda',40:'Championship',136:'Serie B',79:'Bundesliga 2',62:'Ligue 2',140:'La Liga'}
F=pd.read_sql("SELECT fixture_id,league_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season=2026 AND league_id=ANY(%s) AND kickoff>='2026-07-01'",con,params=(list(LG),))
F['ko']=(pd.to_datetime(F.kickoff,utc=True)-E0).dt.total_seconds(); F['H']=F.home.map(norm); F['A']=F.away.map(norm)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) fg FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,F.fixture_id)),)); FG=dict(zip(EV.fixture_id,EV.fg))
B0=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_25' AND ltp>=1.01 AND ltp<1000 AND market_time>='2026-07-01' AND sel='Under 2.5 Goals' ORDER BY market_id,ts",con); con.close()
B0['t']=(pd.to_datetime(B0.ts,utc=True)-E0).dt.total_seconds(); B0['mt']=(pd.to_datetime(B0.market_time,utc=True)-E0).dt.total_seconds()
print(f"fixtures {len(F)}, markets {B0.market_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
ids=B0.drop_duplicates('market_id')[['market_id','event_name','mt']]; keep=set(ids.sort_values('market_id').drop_duplicates(['event_name','mt']).market_id)
out=[]
for mode,B in (('AS_WRITTEN',B0),('ONE_ID',B0[B0.market_id.isin(keep)])):
    meta=B.groupby('market_id',sort=False).agg(ev=('event_name','first'),mt=('mt','first')).reset_index().sort_values('mt'); mts=meta.mt.values; cand=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),m) for e,m in zip(meta.ev,meta.market_id)]
    gr={k:g for k,g in B.groupby('market_id',sort=False)}; rows=[]; S={'unmatched':0,'KO dropped':0}
    for r in F.itertuples():
        a,b=np.searchsorted(mts,r.ko-1800),np.searchsorted(mts,r.ko+1800)
        if a==b: continue
        m=loose(r.H,r.A,cand[a:b])
        if m is None: S['unmatched']+=1; continue
        g=gr[m]; won=(r.hg+r.ag<2.5); pre=g[(~g.inplay)&(g.t>=r.ko-900)&(g.t<r.ko)]
        if len(pre): rows.append(dict(lg=r.league_id,entry='T15',d=r.ko,p=float(pre.ltp.iloc[0]),won=won,fid=r.fixture_id))
        ip=g[g.inplay]
        if len(ip):
            t0=ip.t.iloc[0]; lag=(t0-r.ko)/60
            if -5<=lag<=20 and not (FG.get(r.fixture_id,999)<=max(lag,0)): rows.append(dict(lg=r.league_id,entry='KO',d=r.ko,p=float(ip.ltp.iloc[0]),won=won,fid=r.fixture_id))
            else: S['KO dropped']+=1
    R=pd.DataFrame(rows); print(mode,"skips",S,"trades",len(R),"by month",pd.to_datetime(R.d,unit='s').dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),flush=True)
    R['v']=[lay_settle(step(p,1),w) for p,w in zip(R.p,R.won)]
    for (lg,en),x in R.groupby(['lg','entry']):
        h=np.where(x.d<=x.d.median(),1,2); l=line(x.v.values,h); out.append(dict(mode=mode,league=LG[lg],entry=en,n=l['n'],games=x.fid.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print("\n"+O.sort_values(['league','entry','mode']).round(3).to_string(index=False))
S=O[O.PASS&(O['mode']=='ONE_ID')&(O.league=='Segunda')]; print(f"\n== SURVIVORS: {len(S)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
