#!/bin/bash
set -o pipefail
# 499_script_run_unseen (Finder 2026-11-07, queue item 351, Finder's own, source d; states from jobs/499_last_game_script.sh, entry and match from jobs/499_foul_draw_unseen.sh): lay the home side when both sides are on a run, and a short side after a comeback, on games items 345 and 347 did not read. Rule pushed in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,loose
from lib_official import ly,secs,group,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
T0=time.time()
WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))
def states(games):
    """As jobs/499_last_game_script.sh. games: time-ordered (fid,secs,home,away,hg,ag,hth,hta), one league-season, ht may be nan. Same-time games are not history for each other."""
    last={}; run={}; out={}; i=0
    while i<len(games):
        j=i
        while j<len(games) and games[j][1]==games[i][1]: j+=1
        for f,t,h,a,hg,ag,hh,ha in games[i:j]:
            rh=run.get(h); ra=run.get(a)
            hrun=rh[1]+1 if rh and rh[0]=='H' else 1 if rh else 0
            arun=ra[1]+1 if ra and ra[0]=='A' else 1 if ra else 0
            out[f]=dict(RALLY_H=last.get(h)=='RALLY',RALLY_A=last.get(a)=='RALLY',BOTH=hrun>=2 and arun>=2)
        for f,t,h,a,hg,ag,hh,ha in games[i:j]:
            for tm,me,op,mh,oh,place in ((h,hg,ag,hh,ha,'H'),(a,ag,hg,ha,hh,'A')):
                r=run.get(tm); run[tm]=(place,r[1]+1) if r and r[0]==place else (place,1)
                if mh==mh and oh==oh:
                    last[tm]='BLEW' if mh>oh and me<=op else 'RALLY' if mh<oh and me>op else 'OTHER'
                else: last[tm]=None
        i=j
    return out
def fill(ts,px,ko,side):
    """(print index, price): first print within ko-300..ko+300, worse of it and the next print within 120 s. None if no print, never a fill forward."""
    i=np.where((ts>=ko-300)&(ts<=ko+300))[0]
    if not len(i): return None
    i=int(i[0]); p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return i,p
_o=states([(1,10,'A','B',2,1,0,1),(2,20,'A','B',0,0,0,0)]); assert _o[2]['RALLY_H'] and not _o[2]['RALLY_A'] and _o[2]['BOTH'] and not _o[1]['BOTH']
_o=states([(1,10,'A','B',1,1,1,0),(2,20,'B','A',0,0,0,0)]); assert not _o[2]['BOTH'] and not _o[2]['RALLY_H']
_t=np.array([100.,700.,760.,2000.]); _p=np.array([3.0,2.5,2.6,9.0]); assert fill(_t,_p,1000.,'L')==(1,2.6) and fill(_t,_p,3000.,'L') is None
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag,ht_hg::float8 hh,ht_ag::float8 ha FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND season IN (2023,2024,2025,2026)",con)
F['tt']=secs(F.kickoff); R={}
for (l,s_),g in F.sort_values('tt').groupby(['league_id','season']):
    R.update(states([tuple(x) for x in g[['fixture_id','tt','home','away','hg','ag','hh','ha']].itertuples(index=False)]))
MAPPED=set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map",con).f)
F['k']=pd.to_datetime(F.kickoff,utc=True)
mask=np.zeros(len(F),bool)
for a,b in WINS: mask|=((F.k>=pd.Timestamp(a,tz='UTC'))&(F.k<pd.Timestamp(b,tz='UTC'))).values
FX=F[mask&~F.fixture_id.isin(MAPPED)].sort_values('k').reset_index(drop=True)
print(f"unseen FT fixtures {len(FX):,}; BOTH {sum(R[f]['BOTH'] for f in FX.fixture_id)}; RALLY sides {sum(R[f]['RALLY_H']+R[f]['RALLY_A'] for f in FX.fixture_id)}; {time.time()-T0:.0f}s",flush=True)
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
MK=MK.drop_duplicates('fx',keep=False); print(f"markets matched to one fixture {len(MK):,}, share {len(MK)/max(len(FX),1):.3f}; {time.time()-T0:.0f}s",flush=True)
FI=FX.set_index('fixture_id')
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,MK.fx)),)); FG=dict(zip(EV.fixture_id,EV.gm))
PX={}; mids=list(MK.market_id)
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND sel<>'The Draw' AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    if not len(P): continue
    P['tt']=secs(P.ts); P=P.sort_values(['market_id','sel','tt'],kind='stable')
    for (m,s),x in P.groupby(['market_id','sel'],sort=False): PX[(m,s)]=(x.tt.values,x.ltp.values)
con.close(); print(f"tapes {len(PX):,}; {time.time()-T0:.0f}s",flush=True)
rows=[]; SK=Counter()
for r in MK.itertuples():
    f=FI.loc[r.fx]; ko=f.k.timestamp(); fg=FG.get(r.fx); st=R[r.fx]; bh,_x,ba=str(r.event_name).partition(' v ')
    for pl,name,won,rally in (('H',bh.strip(),f.hg>f.ag,st['RALLY_H']),('A',ba.strip(),f.ag>f.hg,st['RALLY_A'])):
        t=PX.get((r.market_id,name))
        if t is None: SK['no tape for runner']+=1; continue
        z=fill(t[0],t[1],ko,'L')
        if z is None: SK['no print within 5 minutes']+=1; continue
        i,p=z
        if fg is not None and fg<=max((t[0][i]-ko)/60,0): SK['goal by the print']+=1; continue
        first=float(t[1][i]); v=ly(p,bool(won))
        rows.append((pl,ko,r.fx,v,bool(won),1/p,first,bool(rally),bool(st['BOTH'])))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows,columns='pl off g v won imp first rally both'.split()); assert not T.duplicated(['pl','g']).any()
md=float(np.median(T.off.unique())); o=[]
def rd(nm,x,scored):
    l=line(x.v.values,np.where(x.off.values<md,1,2)); o.append(dict(line=nm,n=l['n'],games=x.g.nunique(),per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],maxwin=round(l['maxwin'],2),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=l['PASS'] and scored))
H=T[T.pl=='H']
rd('BOTH home lay',H[H.both],True); rd('RALLY <2 lay',T[T.rally&(T['first']<2)],True); rd('CONTROL all home lay',H,False); rd('CONTROL side <2 lay',T[T['first']<2],False)
L=pd.DataFrame(o).sort_values('t',ascending=False); print(f"\nlines {len(L)}, {time.time()-T0:.0f}s"); print(L.to_string(index=False))
S_=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S_)}\n",S_.to_string(index=False) if len(S_) else "none")
PY
