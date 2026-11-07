#!/bin/bash
set -o pipefail
# 499_foul_draw_unseen (Finder 2026-11-07, queue item 339, Finder's own, source d; FOUL from jobs/499_style_raw.sh, entry and match from jobs/499_streak_unseen.sh): back the Draw between two high-foul sides, on games item 335 did not read. Rule pushed in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,loose
from lib_official import bk,ly,secs,group,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
T0=time.time()
WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))
def foul_state(games):
    """As jobs/499_style_raw.sh, FOUL only. games: time-ordered (fid,secs,home,away,hf,af), one league-season. fid->mean of the two teams' fouls per game by both sides over their last 5 complete games; same-time games are not history for each other."""
    H=defaultdict(lambda:deque(maxlen=5)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,hf,af in games[i:j]:
            if len(H[h])==5 and len(H[a])==5: out[f]=(sum(H[h])/5+sum(H[a])/5)/2
        for f,t,h,a,hf,af in games[i:j]:
            if hf==hf and af==af: H[h].append(hf+af); H[a].append(hf+af)
        i=j
    return out
def fill(ts,px,ko,side):
    """(print index, price): first print within ko-300..ko+300, worse of it and the next print within 120 s. None if no print, never a fill forward."""
    i=np.where((ts>=ko-300)&(ts<=ko+300))[0]
    if not len(i): return None
    i=int(i[0]); p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return i,p
_u=foul_state([(i,i*10,'A','B',10.,14.) for i in range(1,6)]+[(6,60,'A','B',0.,0.)]); assert _u=={6:24.0}
assert foul_state([(i,10,'A','B',10.,14.) for i in range(1,7)])=={}   # same kick-off time is not history
assert foul_state([(i,i*10,'A','B',float('nan'),14.) for i in range(1,6)]+[(6,60,'A','B',0.,0.)])=={}   # a missing column adds no history
_t=np.array([100.,700.,760.,2000.]); _p=np.array([3.0,2.5,2.6,9.0])
assert fill(_t,_p,1000.,'B')==(1,2.5) and fill(_t,_p,1000.,'L')==(1,2.6) and fill(_t,_p,3000.,'B') is None and fill(np.array([800.,1000.]),np.array([2.0,3.0]),800.,'L')==(0,2.0)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
S=pd.read_sql("SELECT f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,f.hg,f.ag,s.is_home,(s.raw->>'Fouls')::float fl FROM af_fixtures f JOIN af_stats s USING(fixture_id) WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ag IS NOT NULL AND f.season IN (2023,2024,2025,2026)",con)
F=S[S.is_home==True].merge(S[S.is_home==False][['fixture_id','fl']],on='fixture_id',suffixes=('_h','_a')).drop_duplicates('fixture_id')
F['tt']=secs(F.kickoff); R={}
for (l,s_),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(foul_state([tuple(x) for x in g[['fixture_id','tt','home','away','fl_h','fl_a']].itertuples(index=False)]))
F['fv']=F.fixture_id.map(R); CUT=F[(F.season==2023)&F.fv.notna()].fv.quantile(.8); print("season 2023 games",int(((F.season==2023)&F.fv.notna()).sum()),"FOUL 80th",round(CUT,3),flush=True); assert abs(CUT-26.6)<1e-6   # item 335's printed cut
MAPPED=set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map",con).f)
F['k']=pd.to_datetime(F.kickoff,utc=True)
mask=np.zeros(len(F),bool)
for a,b in WINS: mask|=((F.k>=pd.Timestamp(a,tz='UTC'))&(F.k<pd.Timestamp(b,tz='UTC'))).values
FX=F[mask&~F.fixture_id.isin(MAPPED)&F.fixture_id.isin(R)].sort_values('k').reset_index(drop=True); FX['st']=np.where(FX.fv>=CUT,'FOUL_HIGH','OTHER')
print(f"unseen FT fixtures with five earlier games {len(FX):,}; states {FX.st.value_counts(dropna=False).to_dict()}; {time.time()-T0:.0f}s",flush=True)
FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.dt.tz_convert(None).values.astype('datetime64[ns]')
parts=[]
for a,b in WINS:
    parts.append(pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s",con,params=(a,b)))
MK=pd.concat(parts,ignore_index=True); MK['mt']=pd.to_datetime(MK.market_time,utc=True)
MK=MK[[group(str(e)) is None for e in MK.event_name]]; print(f"senior markets {len(MK):,}; {time.time()-T0:.0f}s",flush=True)
Ev={}
for (ev,mt),_ in MK.groupby(['event_name','mt'],sort=False):
    h,_x,a=str(ev).partition(' v '); lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(minutes=20)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
    Ev[(ev,mt)]=loose(norm(h),norm(a),[(q.H,q.A,int(q.fixture_id)) for q in FX.iloc[lo:hi].itertuples()])
MK['fx']=[Ev.get((e,m)) for e,m in zip(MK.event_name,MK.mt)]; MK=MK[MK.fx.notna()]; MK['fx']=MK.fx.astype(int)
MK=MK.drop_duplicates('fx',keep=False); print(f"markets matched to one fixture {len(MK):,}, share of unseen fixtures {len(MK)/max(len(FX),1):.3f}; {time.time()-T0:.0f}s",flush=True)
FI=FX.set_index('fixture_id')
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,MK.fx)),)); FG=dict(zip(EV.fixture_id,EV.gm))
PX={}; mids=list(MK.market_id)
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND sel='The Draw' AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    if not len(P): continue
    P['tt']=secs(P.ts); P=P.sort_values(['market_id','sel','tt'],kind='stable')
    for m,x in P.groupby('market_id',sort=False): PX[m]=(x.tt.values,x.ltp.values)
    print(f"  tapes {min(c+500,len(mids))}/{len(mids)} | {time.time()-T0:.0f}s",flush=True)
con.close()
rows=[]; SK=Counter()
for r in MK.itertuples():
    f=FI.loc[r.fx]; ko=f.k.timestamp(); won=bool(f.hg==f.ag); fg=FG.get(r.fx)
    t=PX.get(r.market_id)
    if t is None: SK['no in-play Draw tape']+=1; continue
    z=fill(t[0],t[1],ko,'B')
    if z is None: SK['no print within 5 minutes']+=1; continue
    i,p=z
    if fg is not None and fg<=max((t[0][i]-ko)/60,0): SK['goal by the print']+=1; continue
    v=bk(p,won)
    if v is None: SK['bottom of ladder']+=1; continue
    rows.append((f.st,'DRAW','back',ko,r.fx,v,won,1/p))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='st sel side off g v won imp'.split()); assert not T.duplicated(['st','sel','side','g']).any()
md=float(np.median(T.off.unique())); o=[]
def rd(nm,x,scored):
    l=line(x.v.values,np.where(x.off.values<md,1,2)); o.append(dict(line=nm,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],maxwin=round(l['maxwin'],2),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=l['PASS'] and scored))
for (st,sel,side),x in T.groupby(['st','sel','side']):
    rd(f'{st} {sel} {side}',x,st=='FOUL_HIGH')
for (sel,side),x in T.groupby(['sel','side']): rd(f'CONTROL all {sel} {side}',x,False)
L=pd.DataFrame(o).sort_values('t',ascending=False); print(f"\nlines {len(L)}, {time.time()-T0:.0f}s"); print(L.to_string(index=False))
S_=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S_)}\n",S_.to_string(index=False) if len(S_) else "none")
PY
