#!/bin/bash
set -o pipefail
# 499_scorer_form (Finder 2026-11-06, queue item 251; Finder's own, source c; code from jobs/499_to_score_long_unseen.sh): a player's recent shots and goals v his TO_SCORE price, May-Sep 2026. Rule pushed in the queue before any price was read. No fitting. Read only.
# MODEL over the last 8 games with minutes in 180 days, 4+ games, 200+ minutes: rate = (0.5*goals/90 + 0.5*0.30*shots on target/90) * mean minutes/90; model = 1-exp(-rate); gap = model x print. CHEAP gap >= 1.25, DEAR gap <= 0.75, else MID.
# ITEM 254: pass TO_SCORE_2_OR_MORE or FIRST_GOAL_SCORER as the first argument to read the sister markets, models as queue item 254. Default TO_SCORE.
# RULE as item 166: first print T-30 to the off, worse of it and the next print within 120 s, one tick adverse, 2%, £10 risk, over 200 not traded, minutes 0 void, games must reconcile, one bet per runner. PRINTS ONLY on thin books, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,re,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,lay_settle,back_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time(); DAY=86400.0
MKT=sys.argv[1] if len(sys.argv)>1 and sys.argv[1] in ('TO_SCORE','TO_SCORE_2_OR_MORE','FIRST_GOAL_SCORER') else 'TO_SCORE'; print('market',MKT,flush=True)
def secs(x): return (pd.to_datetime(x,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)  # not astype('int64'): its unit depends on the column
def toks(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    return [w for w in re.sub(r"[^a-z ]"," ",s).split() if w]
def same(a,b):
    x,y=toks(a),toks(b)
    if not x or not y: return 0
    if set(x)==set(y): return 2
    if len(x)>=2 and len(y)>=2 and x[-1]==y[-1] and x[0][0]==y[0][0]: return 1
    return 0
def find(name,squad):
    sc=[(same(name,p),p) for p in squad]; top=max([s for s,_ in sc],default=0)
    if top==0: return None
    best=[p for s,p in sc if s==top]
    return best[0] if len(best)==1 else None
def model(hist,ko,mk='TO_SCORE'):
    """hist: oldest first (ts,minutes,goals,shots on). Games with minutes only. None if under the minimum."""
    H=[h for h in hist if h[0]<ko and h[1]>0 and ko-h[0]<=180*DAY][-8:]
    mins=sum(h[1] for h in H)
    if len(H)<4 or mins<200: return None
    rate=(0.5*sum(h[2] for h in H)*90/mins+0.5*0.30*sum(h[3] for h in H)*90/mins)*(mins/len(H))/90
    if mk=='TO_SCORE_2_OR_MORE': return 1-np.exp(-rate)*(1+rate)
    if mk=='FIRST_GOAL_SCORER': return rate*(1-np.exp(-2.7))/2.7
    return 1-np.exp(-rate)
def state(gap): return 'CHEAP' if gap>=1.25 else ('DEAR' if gap<=0.75 else 'MID')
def entry(ts,px,off,side):
    i=np.where((ts>=off-1800)&(ts<=off))[0]
    if not len(i): return None
    i=i[0]; p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return p
def up_print(ts,px,off):
    """First print in T-30 to the off above the runner's previous print: the only kind a crossing lay can make. None if there is none."""
    for i in range(1,len(ts)):
        if off-1800<=ts[i]<=off and px[i]>px[i-1]: return float(px[i])
    return None
def first_scorer(ev):
    """ev: (minute,type,detail,player). Scorer of the first goal; -1 if the first goal is an own goal or there is none."""
    g=sorted(e for e in ev if e[1]=='Goal' and e[2] in ('Normal Goal','Penalty','Own Goal'))
    if not g: return -1
    return -1 if g[0][2]=='Own Goal' else g[0][3]
def band(p): return '<4' if p<4 else ('4-10' if p<10 else '10-200')
# known answers, worked by hand
# 4 games, 90 min each, 2 goals, 4 on target: 360 min. g/90 0.5, sot/90 1.0: 0.5*0.5 + 0.5*0.3*1.0 = 0.40, times 90/90 = 0.40; 1-exp(-0.4) = 0.329680
_H=[(float(i),90,1 if i<2 else 0,1) for i in range(4)]; assert abs(model(_H,10.0)-0.329680)<1e-5
assert model(_H[:3],10.0) is None and model([(float(i),40,1,1) for i in range(4)],10.0) is None   # 3 games; 160 minutes
assert model(_H,1.5) is None                                # only games before the kick-off count
assert model(_H,200*DAY) is None                            # older than 180 days
# 45 min a game over 8 games: 360 min, same per-90 figures, times 0.5 = 0.20; 1-exp(-0.2) = 0.181269
_H2=[(float(i),45,1 if i<2 else 0,1 if i<4 else 0) for i in range(8)]; assert abs(model(_H2,10.0)-0.181269)<1e-5
# r = 0.40: 1-exp(-0.4)*1.4 = 0.061552; r*(1-exp(-2.7))/2.7 = 0.40*0.932794/2.7 = 0.138192
assert abs(model(_H,10.0,'TO_SCORE_2_OR_MORE')-0.061552)<1e-5 and abs(model(_H,10.0,'FIRST_GOAL_SCORER')-0.138192)<1e-5
assert first_scorer([(30,'Goal','Normal Goal',7),(10,'Goal','Normal Goal',9)])==9 and first_scorer([(5,'Goal','Own Goal',3),(10,'Goal','Normal Goal',9)])==-1 and first_scorer([])==-1
assert state(1.25)=='CHEAP' and state(0.75)=='DEAR' and state(1.0)=='MID'
assert entry(np.array([800.,860.]),np.array([6.0,6.4]),2000.,'L')==6.4 and entry(np.array([800.,860.]),np.array([6.0,6.4]),2000.,'B')==6.0 and entry(np.array([100.]),np.array([9.0]),2000.,'B') is None
assert abs(back_settle(step(6.0,-1),True)-(10*4.9*0.98))<1e-9 and abs(lay_settle(step(6.0,1),False)-1.884615)<1e-5
assert float(secs(pd.Series(['2026-01-02 00:00:00+00:00'])).iloc[0])==1767312000.0
assert up_print(np.array([100.,800.,900.,950.]),np.array([9.,8.,10.,12.]),2000.)==10.0 and up_print(np.array([800.,900.]),np.array([9.,8.]),2000.) is None and up_print(np.array([100.,800.]),np.array([8.,9.]),2000.)==9.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
FROM,TO='2026-05-01','2026-10-01'; SK=Counter()
A=pd.read_sql("SELECT s.player_id,s.fixture_id,COALESCE(s.minutes,0) minutes,COALESCE(s.goals,0) goals,COALESCE(s.shots_on,0) shots_on,f.kickoff FROM af_player_stats s JOIN af_fixtures f USING(fixture_id) WHERE s.player_id IS NOT NULL AND f.status IN ('FT','AET','PEN')",con)
A['ts']=secs(A.kickoff); A=A.sort_values('ts')
HIST={int(p):list(zip(x.ts,x.minutes,x.goals,x.shots_on)) for p,x in A.groupby('player_id',sort=False)}
print(f"history rows {len(A):,}, players {len(HIST):,}; {time.time()-T0:.0f}s",flush=True)
FX=pd.read_sql(f"SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE kickoff>=timestamptz '{FROM}'-interval '20 minutes' AND kickoff<timestamptz '{TO}'+interval '20 minutes' AND status='FT' AND hg IS NOT NULL",con)
FX['k']=pd.to_datetime(FX.kickoff,utc=True); FX=FX.sort_values('k').reset_index(drop=True); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.values.astype('datetime64[ns]'); ids=[int(x) for x in FX.fixture_id]
PS=pd.read_sql("SELECT fixture_id,team,player,player_id,position,COALESCE(minutes,0) minutes,COALESCE(goals,0) goals FROM af_player_stats WHERE fixture_id=ANY(%s)",con,params=(ids,))
OG=pd.read_sql("SELECT fixture_id,count(*) c FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail='Own Goal' GROUP BY 1",con,params=(ids,)); OGD={int(r.fixture_id):int(r.c) for r in OG.itertuples()}
FE={}
if MKT=='FIRST_GOAL_SCORER':
    E_=pd.read_sql("SELECT fixture_id,COALESCE(minute,0) mn,type,detail,player FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal'",con,params=(ids,))
    for k,x in E_.groupby('fixture_id'): FE[int(k)]=first_scorer(list(zip(x.mn,x.type,x.detail,x.player.fillna(""))))
SQ={k:x for k,x in PS.groupby('fixture_id')}; Res={}; KO={int(r.fixture_id):r.k.timestamp() for r in FX.itertuples()}
for r in FX.itertuples():
    fx=int(r.fixture_id); s=SQ.get(fx)
    if s is None: SK['fixture: no player stats']+=1; continue
    pl={}
    for p in s.itertuples():
        o=pl.get(p.player)
        if o is None: pl[p.player]=dict(min=int(p.minutes),g=int(p.goals),pid=p.player_id,pos=p.position)
        else: o['min']=max(o['min'],int(p.minutes)); o['g']=max(o['g'],int(p.goals))
    if sum(v['g'] for v in pl.values())+OGD.get(fx,0)!=r.hg+r.ag: SK['fixture: player goals do not reconcile, not traded']+=1; continue
    SK['fixture: usable']+=1; Res[fx]=pl
P=pd.read_sql(f"SELECT market_id,event_name,market_time,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='{MKT}' AND market_time>='{FROM}' AND market_time<'{TO}' AND NOT inplay AND ltp>=1.01 AND ltp<1000",con)
con.close()
if P.empty: print("no TO_SCORE prints\n\nSURVIVORS\nnone"); sys.exit(0)
P['mt']=pd.to_datetime(P.market_time,utc=True); ep=pd.Timestamp('1970-01-01',tz='UTC'); P['tt']=(pd.to_datetime(P.ts,utc=True)-ep)/pd.Timedelta(seconds=1); P['off']=(P.mt-ep)/pd.Timedelta(seconds=1); P=P.sort_values(['market_id','sel','tt'],kind='stable')
print(f"prints {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
Mp={}
for (ev,mt),_ in P.groupby(['event_name','mt'],sort=False):
    h,_x,a=str(ev).partition(' v '); lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(minutes=20)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
    Mp[(ev,mt)]=loose(norm(h),norm(a),[(q.H,q.A,int(q.fixture_id)) for q in FX.iloc[lo:hi].itertuples()])
print(f"events {len(Mp)}, matched {sum(v is not None for v in Mp.values())}",flush=True)
rows=[]
for (mid,ev,mt,sel),y in P.groupby(['market_id','event_name','mt','sel'],sort=False):
    fx=Mp.get((ev,mt))
    if fx is None: SK['runner: event not matched']+=1; continue
    if fx not in Res: SK['runner: game not usable']+=1; continue
    tt,px,off=y.tt.values,y.ltp.values,y.off.iloc[0]
    pb=entry(tt,px,off,'B'); pl_=entry(tt,px,off,'L')
    if pb is None: SK['runner: no print in T-30 to the off']+=1; continue
    a=find(sel,list(Res[fx]))
    if a is None: SK['runner: not in squad, not traded']+=1; continue
    u=Res[fx][a]
    if u['min']<=0: SK['runner: minutes 0, void']+=1; continue
    if pl_>200: SK['runner: over 200, not traded']+=1; continue
    m=model(HIST.get(int(u['pid']),[]) if u['pid']==u['pid'] else [],KO[fx],MKT)
    if m is None: SK['runner: under the history minimum']+=1; continue
    first=float(px[np.where((tt>=off-1800)&(tt<=off))[0][0]])
    rows.append((fx,off,sel,first,pb,pl_,m,(u['g']>=2 if MKT=='TO_SCORE_2_OR_MORE' else ((FE.get(fx,-1)!=-1 and same(a,FE[fx])>0) if MKT=='FIRST_GOAL_SCORER' else u['g']>=1)),up_print(tt,px,off),float(px[np.where((tt>=off-1800)&(tt<=off))[0][-1]]),u['pos']))
print('counted:',dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='g mt sel first pb pl m won up last pos'.split())
if R.empty: print("no trades\n\nSURVIVORS\nnone"); sys.exit(0)
R['gap']=R.m*R['first']; R['state']=R.gap.map(state); R['bd']=R['first'].map(band)
R['BACK']=[(lambda q:back_settle(q,w) if q>1.01 else np.nan)(step(p,-1)) for p,w in zip(R.pb,R.won)]; R['LAY']=[lay_settle(step(p,1),w) for p,w in zip(R.pl,R.won)]
print(f"runners {len(R):,}, games {R.g.nunique():,}, won {R.won.mean():.3f}, mean implied {(1/R['first']).mean():.3f}, mean model {R.m.mean():.3f}; by state {R.state.value_counts().to_dict()}",flush=True)
print("calibration by state: won v model v implied"); print(R.groupby('state').apply(lambda x:pd.Series(dict(n=len(x),won=x.won.mean(),model=x.m.mean(),implied=(1/x['first']).mean()))).round(3).to_string())
md=R.groupby('g').mt.first().median(); o=[]
for st in ('CHEAP','MID','DEAR'):
    for b in ('ALL','<4','4-10','10-200'):
        x=R[(R.state==st)&((R.bd==b)|(b=='ALL'))]
        for side in ('BACK','LAY'):
            y=x.dropna(subset=[side])
            if not len(y): continue
            A1=y[y.mt<=md][side]; A2=y[y.mt>md][side]; n=len(y); t=tstat(y[side].values); tg=tstat(y.groupby('g')[side].sum().values); m=y[side].mean()
            ok=passes(n,len(A1),len(A2),t,A1.mean() if len(A1) else -1,A2.mean() if len(A2) else -1,m)
            o.append(dict(state=st,band=b,side=side,n=n,games=y.g.nunique(),per10=round(m,3),t=round(t,2),tg=round(tg,2),h1=round(A1.mean(),3) if len(A1) else None,h2=round(A2.mean(),3) if len(A2) else None,won=round(y.won.mean(),3),implied=round((1/y['first']).mean(),3),PASS=bool(ok and tg>=3.5)))
L=pd.DataFrame(o); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}\n"); print(L.sort_values('t',ascending=False).head(15).to_string(index=False))
print("\n== CONTEXT, sceptical checks, none of these can pass or be used to choose")
def ctx(nm,x,v):
    x=x.assign(_v=v).dropna(subset=['_v'])
    if not len(x): print(f"  {nm:34s} n 0"); return
    a=x[x.mt<=md]._v; b=x[x.mt>md]._v
    print(f"  {nm:34s} n {len(x):5d} games {x.g.nunique():4d} per10 {x._v.mean():+.3f} t {tstat(x._v.values):5.2f} tg {tstat(x.groupby('g')._v.sum().values):5.2f} h1 {a.mean() if len(a) else float('nan'):+.3f} h2 {b.mean() if len(b) else float('nan'):+.3f} won {x.won.mean():.3f} implied {(1/x['first']).mean():.3f}")
D=R[(R.state=='DEAR')&(R.bd=='10-200')]; O=R[(R.state!='DEAR')&(R.bd=='10-200')]
ctx('DEAR 10-200 lay, scored',D,D.LAY); ctx('rest of 10-200 lay',O,O.LAY)
dz=(D.LAY.mean()-O.LAY.mean())/np.sqrt(D.LAY.var(ddof=1)/len(D)+O.LAY.var(ddof=1)/len(O)); print(f"  DEAR minus rest z {dz:.2f}")
for lo,hi in ((10,20),(20,50),(50,201)):
    y=D[(D['first']>=lo)&(D['first']<hi)]; ctx(f'DEAR {lo}-{hi}',y,y.LAY)
M=D.assign(mo=pd.to_datetime(D.mt,unit='s').dt.strftime('%Y-%m'))
for k,y in M.groupby('mo'): ctx('DEAR 10-200 '+k,y,y.LAY)
def lay_at(q,w,tick):
    if q is None or q!=q: return np.nan
    return lay_settle(step(q,1) if tick else q,w)
ctx('at first up-print, one tick',D,[lay_at(q,w,True) for q,w in zip(D.up,D.won)])
ctx('at first up-print, no tick',D,[lay_at(q,w,False) for q,w in zip(D.up,D.won)])
print(f"  runners with an up-print {D.up.notna().mean():.3f}; of those mean first print {D[D.up.notna()]['first'].mean():.2f}, mean up-print {D.up.mean():.2f}; mean first over all {D['first'].mean():.2f}")
ctx('at the last print, one tick',D,[lay_at(q,w,True) for q,w in zip(D['last'],D.won)])
ctx('rest of band at first up-print',O,[lay_at(q,w,True) for q,w in zip(O.up,O.won)])
for k in (2,3,5):
    ctx(f'DEAR 10-200, {k} ticks worse',D,[lay_settle(step(q,k),w) for q,w in zip(D.pl,D.won)])
A10=R[R.bd=='10-200']
for lo,hi in ((0,0.45),(0.45,0.6),(0.6,0.75),(0.75,0.9),(0.9,1.1),(1.1,1.25),(1.25,9)):
    y=A10[(A10.gap>lo)&(A10.gap<=hi)]; ctx(f'10-200 gap {lo}-{hi}',y,y.LAY)
for k,y in A10.groupby('pos'): ctx('10-200 all, position '+str(k),y,y.LAY)
for k,y in D.groupby('pos'): ctx('DEAR 10-200, position '+str(k),y,y.LAY)
print("\nSURVIVORS"); S=L[L.PASS]; print(S.to_string(index=False) if len(S) else "none"); print(f"done {time.time()-T0:.0f}s")
PY
