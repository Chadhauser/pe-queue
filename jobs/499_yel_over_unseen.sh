#!/bin/bash
set -o pipefail
# 499_yel_over_unseen (Finder 2026-11-07, queue item 358, Finder's own, source d; port of jobs/499_off_unseen.sh with Yellow Cards for Offsides, Over only): YEL HIGH Over 2.5 back on games item 355 did not read. Rule pushed in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
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
HI,LO=5.1,3.5   # item 355's printed season 2023 cuts
def off_state(games):
    """As jobs/499_style_off_saves.sh, OFF only. games: time-ordered (fid,secs,home,away,ho,ao), one league-season. fid->mean of the two teams' offsides per game by both sides over their last 5 complete games; same-time games are not history."""
    H=defaultdict(lambda:deque(maxlen=5)); out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,ho,ao in games[i:j]:
            if len(H[h])==5 and len(H[a])==5: out[f]=(sum(H[h])/5+sum(H[a])/5)/2
        for f,t,h,a,ho,ao in games[i:j]:
            if ho==ho and ao==ao: H[h].append(ho+ao); H[a].append(ho+ao)
        i=j
    return out
def fill(ts,px,ko,side):
    """(print index, price): first print within ko-300..ko+300, worse of it and the next print within 120 s. None if no print, never a fill forward."""
    i=np.where((ts>=ko-300)&(ts<=ko+300))[0]
    if not len(i): return None
    i=int(i[0]); p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return i,p
_u=off_state([(i,i*10,'A','B',2.,3.) for i in range(1,6)]+[(6,60,'A','B',0.,0.)]); assert _u=={6:5.0}
assert off_state([(i,10,'A','B',2.,3.) for i in range(1,7)])=={}
assert off_state([(i,i*10,'A','B',float('nan'),3.) for i in range(1,6)]+[(6,60,'A','B',0.,0.)])=={}
_t=np.array([100.,700.,760.,2000.]); _p=np.array([3.0,2.5,2.6,9.0])
assert fill(_t,_p,1000.,'B')==(1,2.5) and fill(_t,_p,3000.,'B') is None
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
S=pd.read_sql("""SELECT f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,f.hg,f.ag,s.is_home,
 CASE WHEN s.raw->>'Total Shots' IS NULL THEN NULL ELSE coalesce((s.raw->>'Yellow Cards')::float,0) END fl
 FROM af_fixtures f JOIN af_stats s USING(fixture_id) WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ag IS NOT NULL AND f.season IN (2023,2024,2025,2026)""",con)
F=S[S.is_home==True].merge(S[S.is_home==False][['fixture_id','fl']],on='fixture_id',suffixes=('_h','_a')).drop_duplicates('fixture_id')
F['tt']=secs(F.kickoff); R={}
for (l,s_),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(off_state([tuple(x) for x in g[['fixture_id','tt','home','away','fl_h','fl_a']].itertuples(index=False)]))
F['fv']=F.fixture_id.map(R); B3=F[(F.season==2023)&F.fv.notna()].fv
print("season 2023 games",len(B3),"YEL 20th, 80th",round(B3.quantile(.2),3),round(B3.quantile(.8),3),flush=True); assert abs(B3.quantile(.8)-HI)<1e-6 and abs(B3.quantile(.2)-LO)<1e-6
MAPPED=set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map",con).f)
F['k']=pd.to_datetime(F.kickoff,utc=True)
mask=np.zeros(len(F),bool)
for a,b in WINS: mask|=((F.k>=pd.Timestamp(a,tz='UTC'))&(F.k<pd.Timestamp(b,tz='UTC'))).values
FX=F[mask&~F.fixture_id.isin(MAPPED)&F.fixture_id.isin(R)].sort_values('k').reset_index(drop=True)
FX['st']=np.where(FX.fv>=HI-1e-9,'HIGH',np.where(FX.fv<=LO+1e-9,'LOW','MID'))
print(f"unseen FT fixtures with five earlier games {len(FX):,}; states {FX.st.value_counts().to_dict()}; {time.time()-T0:.0f}s",flush=True)
FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.dt.tz_convert(None).values.astype('datetime64[ns]')
FI=FX.set_index('fixture_id')
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,FX.fixture_id)),)); FG=dict(zip(EV.fixture_id,EV.gm))
rows=[]; SK=Counter()
for mt_type,sel,tag,wfn,scored_state in (('OVER_UNDER_25','Over 2.5 Goals','OVER',lambda f:f.hg+f.ag>2.5,'HIGH'),):
    parts=[]
    for a,b in WINS:
        parts.append(pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND market_time>=%s AND market_time<%s",con,params=(mt_type,a,b)))
    MK=pd.concat(parts,ignore_index=True); MK['mt']=pd.to_datetime(MK.market_time,utc=True)
    MK=MK[[group(str(e)) is None for e in MK.event_name]]; print(f"{tag} senior markets {len(MK):,}; {time.time()-T0:.0f}s",flush=True)
    Ev={}
    for (ev,mt),_ in MK.groupby(['event_name','mt'],sort=False):
        h,_x,a=str(ev).partition(' v '); lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(minutes=20)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
        Ev[(ev,mt)]=loose(norm(h),norm(a),[(q.H,q.A,int(q.fixture_id)) for q in FX.iloc[lo:hi].itertuples()])
    MK['fx']=[Ev.get((e,m)) for e,m in zip(MK.event_name,MK.mt)]; MK=MK[MK.fx.notna()]; MK['fx']=MK.fx.astype(int)
    MK=MK.drop_duplicates('fx',keep=False); print(f"{tag} markets matched to one fixture {len(MK):,}, share {len(MK)/max(len(FX),1):.3f}; {time.time()-T0:.0f}s",flush=True)
    PX={}; mids=list(MK.market_id)
    for c in range(0,len(mids),500):
        P=pd.read_sql("SELECT market_id,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND market_id=ANY(%s) AND sel=%s AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mt_type,mids[c:c+500],sel))
        if not len(P): continue
        P['tt']=secs(P.ts); P=P.sort_values(['market_id','tt'],kind='stable')
        for m,x in P.groupby('market_id',sort=False): PX[m]=(x.tt.values,x.ltp.values)
    print(f"{tag} tapes {len(PX):,}; {time.time()-T0:.0f}s",flush=True)
    for r in MK.itertuples():
        f=FI.loc[r.fx]; ko=f.k.timestamp(); won=bool(wfn(f)); fg=FG.get(r.fx); t=PX.get(r.market_id)
        if t is None: SK[tag+' no in-play tape']+=1; continue
        z=fill(t[0],t[1],ko,'B')
        if z is None: SK[tag+' no print within 5 minutes']+=1; continue
        i,p=z
        if fg is not None and fg<=max((t[0][i]-ko)/60,0): SK[tag+' goal by the print']+=1; continue
        v=bk(p,won)
        if v is None: SK[tag+' bottom of ladder']+=1; continue
        rows.append((f.st,tag,ko,r.fx,v,won,1/p,f.st==scored_state))
con.close()
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='st sel off g v won imp sc'.split()); assert not T.duplicated(['st','sel','g']).any()
md=float(np.median(T.off.unique())); o=[]
def rd(nm,x,scored):
    l=line(x.v.values,np.where(x.off.values<md,1,2)); o.append(dict(line=nm,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],maxwin=round(l['maxwin'],2),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=l['PASS'] and scored))
for (st,sel),x in T.groupby(['st','sel']): rd(f'{st} {sel} back',x,bool(x.sc.iloc[0]))
for sel,x in T.groupby('sel'): rd(f'CONTROL all {sel} back',x,False)
L=pd.DataFrame(o).sort_values('t',ascending=False); print(f"\nlines {len(L)}, {time.time()-T0:.0f}s"); print(L.to_string(index=False))
S_=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S_)}\n",S_.to_string(index=False) if len(S_) else "none")
PY
