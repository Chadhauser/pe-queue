#!/bin/bash
set -o pipefail
# 499_absence_unseen (Finder 2026-11-06, queue item 253; Finder's own, source a; flags from jobs/499_rotation_scorer.sh): three lines from items 248 and 249 on games that did not choose them, 21 Jun to 30 Sep 2026. Rule pushed in the queue before this read. Read only.
# LINES S_OUT ALL OVER back; S_OUT ALL TEAM back; R2_3 DOG TEAM lay. Nothing else can pass; R0_1 and S_IN are shown as controls.
# ENTRY first in-play print within -5..+5 min of the kick-off, worse of it and the next print within 120 s, one tick adverse, a goal at or before the print's minute dropped, 2%, £10 risk, to FT. Goal line one bet per game. DOG on the team's first print, as item 248.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,warnings,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time(); DAY=86400.0
def secs(x): return (pd.to_datetime(x,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def rested_state(prev,today):
    c=sum(1 for p,v in prev.items() if v[0]>=60 and today.get(p,(0,0))[0]==0)
    return 'R0_1' if c<=1 else ('R2_3' if c<=3 else 'R4P')
def top_scorer(H):
    g={}; a={}
    for x in H:
        for p,v in x.items():
            g[p]=g.get(p,0)+v[1]; a[p]=a.get(p,0)+(v[0]>0)
    if not g: return None
    m=max(g.values())
    if m<3: return None
    w=[p for p,v in g.items() if v==m]
    return w[0] if len(w)==1 and a[w[0]]>=3 else None
def scorer_state(H,today):
    t=top_scorer(H)
    if t is None: return None
    now=today.get(t,(0,0))[0]>0; last=H[-1].get(t,(0,0))[0]>0
    return {(False,True):'S_OUT',(False,False):'S_OUT_LONG',(True,True):'S_IN',(True,False):'S_BACK'}[(now,last)]
def flags(games):
    hist={}; out={}
    for f,t,ts,d in games:
        H=hist.setdefault(t,[]); st=[]
        if H and ts-H[-1][0]<=14*DAY:
            pv=H[-1][1]
            if sum(v[0] for v in pv.values())>=800 and sum(v[0] for v in d.values())>=800: st.append(rested_state(pv,d))
            W=[x[1] for x in H[-8:] if ts-x[0]<=60*DAY]
            if len(W)>=5:
                s=scorer_state(W,d)
                if s: st.append(s)
        if st: out[(f,t)]=st
        H.append((ts,d))
    return out
def fill(ts,px,ko,side):
    """(print index, price): first print within ko-300..ko+300, worse of it and the next print within 120 s. None if no print: never a fill forward."""
    i=np.where((ts>=ko-300)&(ts<=ko+300))[0]
    if not len(i): return None
    i=int(i[0]); p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return i,p
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
# known answers, worked by hand
_t=np.array([100.,700.,760.,2000.]); _p=np.array([3.0,2.5,2.6,9.0])
assert fill(_t,_p,1000.,'B')==(1,2.5) and fill(_t,_p,1000.,'L')==(1,2.6)                 # 100 s is before the window; next print within 120 s
assert fill(_t,_p,3000.,'B') is None                                                     # no print in the window
assert fill(np.array([800.,1000.]),np.array([2.0,3.0]),800.,'L')==(0,2.0)                # next print 200 s on: not used
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
_full={i:(90,0) for i in range(11)}
assert flags([(1,'A',0.0,_full),(2,'A',7*DAY,_full)])[(2,'A')]==['R0_1'] and float(secs(pd.Series(['2026-01-02 00:00:00+00:00'])).iloc[0])==1767312000.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
K=pd.read_sql("SELECT s.fixture_id,s.team,s.player_id,COALESCE(s.minutes,0) minutes,COALESCE(s.goals,0) goals,f.kickoff FROM af_player_stats s JOIN af_fixtures f USING(fixture_id) WHERE f.status IN ('FT','AET','PEN') AND s.player_id IS NOT NULL",con)
K=K.groupby(['fixture_id','team','player_id','kickoff'],as_index=False).agg(minutes=('minutes','max'),goals=('goals','max')); K['ts']=secs(K.kickoff)
games=[]
for (ts,f,t),x in K.sort_values(['ts','fixture_id']).groupby(['ts','fixture_id','team'],sort=False):
    games.append((int(f),t,ts,{int(p):(int(m),int(g)) for p,m,g in zip(x.player_id,x.minutes,x.goals)}))
FL=flags(games); WANT={'S_OUT','R2_3','R0_1','S_IN'}
FROM,TO='2026-06-21','2026-10-01'
FX=pd.read_sql(f"SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE kickoff>='{FROM}' AND kickoff<'{TO}' AND status='FT' AND hg IS NOT NULL",con)
MAPPED=set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map",con).f); FX=FX[~FX.fixture_id.isin(MAPPED)]
FX['k']=pd.to_datetime(FX.kickoff,utc=True); FX=FX.sort_values('k').reset_index(drop=True); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.values.astype('datetime64[ns]')
print(f"FT fixtures in the window {len(FX):,}; with a wanted flag {sum(any(s in WANT for t in (r.home,r.away) for s in FL.get((int(r.fixture_id),t),[])) for r in FX.itertuples()):,}; {time.time()-T0:.0f}s",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,FX.fixture_id)),)); FG=dict(zip(EV.fixture_id,EV.gm))
MK=pd.read_sql(f"SELECT DISTINCT market_id,market_type,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25') AND market_time>='{FROM}' AND market_time<'{TO}'",con)
MK['mt']=pd.to_datetime(MK.market_time,utc=True); print(f"markets {len(MK):,}; {time.time()-T0:.0f}s",flush=True)
Ev={}
for (ev,mt),_ in MK.groupby(['event_name','mt'],sort=False):
    h,_x,a=str(ev).partition(' v '); lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(minutes=20)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
    Ev[(ev,mt)]=loose(norm(h),norm(a),[(q.H,q.A,int(q.fixture_id)) for q in FX.iloc[lo:hi].itertuples()])
print(f"events {len(Ev):,}, matched {sum(v is not None for v in Ev.values()):,}",flush=True)
FI=FX.set_index('fixture_id'); MK['fx']=[Ev.get((e,m)) for e,m in zip(MK.event_name,MK.mt)]; MK=MK[MK.fx.notna()]; MK['fx']=MK.fx.astype(int)
flagged={int(r.fixture_id) for r in FX.itertuples() if any(s in WANT for t in (r.home,r.away) for s in FL.get((int(r.fixture_id),t),[]))}
MK=MK[MK.fx.isin(flagged)].drop_duplicates(['fx','market_type'],keep=False); print(f"markets on flagged games, one per game per type {len(MK):,}",flush=True)
PX={}; mids=list(MK.market_id)
for c in range(0,len(mids),300):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+300],))
    if not len(P): continue
    P['tt']=secs(P.ts); P=P.sort_values(['market_id','sel','tt'],kind='stable')
    for (m,s),x in P.groupby(['market_id','sel'],sort=False): PX[(m,s)]=(x.tt.values,x.ltp.values)
con.close(); print(f"runner tapes {len(PX):,}; {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; GM={}
for g,x in MK.groupby('fx'):
    GM[int(g)]=dict(zip(x.market_type,x.market_id))
SEL={}
for (m,s) in PX: SEL.setdefault(m,[]).append(s)
for fx,mm in GM.items():
    r=FI.loc[fx]; ko=r.k.timestamp(); hg,ag=int(r.hg),int(r.ag); over=hg+ag>2.5; fg=FG.get(fx)
    ev=MK[MK.fx==fx].event_name.iloc[0]; bh,_x,ba=str(ev).partition(' v ')
    def ok(ts,i):
        el=(ts[i]-ko)/60
        return not (fg is not None and fg<=max(el,0))
    for team,tname,won in ((r.home,bh.strip(),hg>ag),(r.away,ba.strip(),ag>hg)):
        sts=[s for s in FL.get((fx,team),[]) if s in WANT]
        if not sts: continue
        pb=pl=None; first=None; mo=mm.get('MATCH_ODDS')
        if mo and (mo,tname) in PX:
            ts,px=PX[(mo,tname)]; a=fill(ts,px,ko,'B'); b=fill(ts,px,ko,'L')
            if a is None: SK['team: no print in the window']+=1
            elif not ok(ts,a[0]): SK['team: goal before the print, dropped']+=1
            else: pb=a[1]; pl=b[1]; first=float(px[a[0]])
        elif mo: SK['team: runner name not on the tape']+=1
        else: SK['team: no MO market']+=1
        ou=mm.get('OVER_UNDER_25'); ob=None
        if ou and (ou,'Over 2.5 Goals') in PX:
            ts,px=PX[(ou,'Over 2.5 Goals')]; a=fill(ts,px,ko,'B')
            if a is None: SK['over: no print in the window']+=1
            elif not ok(ts,a[0]): SK['over: goal before the print, dropped']+=1
            else: ob=a[1]
        for st in sts:
            if pb is not None: rows.append((fx,ko,st,'ALL','TEAM','BACK',bk(pb,won)))
            if pb is not None: rows.append((fx,ko,st,'ALL','TEAM','LAY',ly(pl,won)))
            if first is not None and first>=3.0: rows.append((fx,ko,st,'DOG','TEAM','LAY',ly(pl,won))); rows.append((fx,ko,st,'DOG','TEAM','BACK',bk(pb,won)))
            if ob is not None: rows.append((fx,ko,st,'ALL','OVER','BACK',bk(ob,over)))
W_=Counter(z for r in FX.itertuples() for t in (r.home,r.away) for z in FL.get((int(r.fixture_id),t),[])); print('team-games by state in the window, before any tape:',dict(sorted(W_.items())),flush=True)
print('of those on a matched game with a market:',dict(sorted(Counter(z for fx in GM for t in (FI.loc[fx].home,FI.loc[fx].away) for z in FL.get((fx,t),[])).items())),flush=True)
print('counted:',dict(sorted(SK.items())),flush=True)
T=pd.DataFrame(rows,columns='g ko state band leg side v'.split()).dropna(subset=['v'])
gl=T.leg=='OVER'; T=pd.concat([T[~gl],T[gl].drop_duplicates(['state','band','leg','side','g'])],ignore_index=True)
md=T.drop_duplicates('g').ko.median(); o=[]; SC={('S_OUT','ALL','OVER','BACK'),('S_OUT','ALL','TEAM','BACK'),('R2_3','DOG','TEAM','LAY')}
for k,x in T.groupby(['state','band','leg','side']):
    a=x[x.ko<=md].v; b=x[x.ko>md].v; t=tstat(x.v.values); tg=tstat(x.groupby('g').v.sum().values); m=x.v.mean(); ok_=passes(len(x),len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,m)
    o.append(dict(zip(['state','band','leg','side'],k))|dict(n=len(x),games=x.g.nunique(),per10=round(m,3),t=round(t,2),tg=round(tg,2),h1=round(a.mean(),3) if len(a) else None,h2=round(b.mean(),3) if len(b) else None,scored=k in SC,PASS=bool(k in SC and ok_ and tg>=3.5)))
L=pd.DataFrame(o); print("\n== ALL LINES (scored = the three that can pass)"); print(L.sort_values(['scored','t'],ascending=[False,False]).to_string(index=False))
print("\nSURVIVORS"); S=L[L.PASS]; print(S.to_string(index=False) if len(S) else "none"); print(f"done {time.time()-T0:.0f}s")
PY
