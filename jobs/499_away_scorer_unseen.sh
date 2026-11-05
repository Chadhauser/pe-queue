#!/bin/bash
set -o pipefail
# 499_away_scorer_unseen (Finder 2026-11-05, queue item 125, from jobs/499_player_corner_markets.sh): lay an away player to score, on Jun-Jul 2026, months that did not choose the line (it was chosen on Aug-Sep 2026). Read only. Rule fixed in the queue before any Jun-Jul price was read, no new cuts.
# INTERIM: the item asks for Jun and May; May is still loading (Soccer 2026-05 about 2,400 of 33,556 files), so it is left out and the item stays open for it. July is unseen too and is on the box, so it is used.
# RULE: TO_SCORE, first non-in-play print T-30 min to the off, away team's runners, prices to 200, lay at the worse of that print and the next within 120 s, one tick adverse, 2%, £10 liability, hold to result. Minutes 0 void. A runner not found in the squad, or a game whose player goals do not reconcile with the score, is not traded, counted.
# VOID RULE: Betfair's market rules are not on this box. A void removes a lay winner (a player who never played cannot score), so voiding is the cautious side for this lay.
# REGRESSION: the same code on Aug-Sep must come back near item 74's n 921, +0.409. That window is NOT evidence, it picked the line. Scored line: AWAY lay on Jun-Jul. Everything else is a mirror, labelled, not scored.
# REGRESSION RESULT 2026-11-05: n 1,097, +0.286, t 2.22, not 921, as Aug-Sep has since loaded; jobs/499_player_corner_markets.sh on the same data returns the same n, per10, t and tg, so the code agrees.
# PRINTS ONLY on thin books: a pass here would be an upper bound and would earn a real-touch check on player_liq, no more.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,re,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,lay_settle,back_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
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
def runner(sel,squad):
    """(status,won,home): status OK, VOID or NOSQUAD."""
    a=find(sel,list(squad))
    if a is None: return 'NOSQUAD',None,None
    u=squad[a]
    if u['min']<=0: return 'VOID',None,u['home']
    return 'OK',u['g']>=1,u['home']
def entry(ts,px,ltp_inplay_free_off):
    """First print in T-30 min to the off, lay at the worse of it and the next print within 120 s. ts sorted, non-in-play only."""
    off=ltp_inplay_free_off; i=np.where((ts>=off-1800)&(ts<=off))[0]
    if not len(i): return None
    i=i[0]; p=float(px[i]); first=p
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1]))
    return first,p
# known answers, worked by hand
_S={'E. Haaland':dict(min=90,g=2,home=False),'P. Foden':dict(min=90,g=0,home=False),'J. Doku':dict(min=0,g=0,home=False)}
assert runner('Erling Haaland',_S)==('OK',True,False) and runner('Phil Foden',_S)==('OK',False,False) and runner('Jeremy Doku',_S)==('VOID',None,False) and runner('Harry Kane',_S)[0]=='NOSQUAD'
# lay at 6.0, one tick adverse 6.2, liability 10: stake 10/5.2=1.923; wins 1.923*0.98=1.8846; loses -10
assert abs(lay_settle(step(6.0,1),False)-1.884615)<1e-5 and lay_settle(step(6.0,1),True)==-10.0
# entry: first print at T-20m 6.0, next 60 s later 6.4: lay takes 6.4. Next 200 s later: keeps 6.0. Print before T-30 is not used; no print in the window, no entry, never a fill forward.
assert entry(np.array([800.,860.]),np.array([6.0,6.4]),2000.)==(6.0,6.4) and entry(np.array([800.,1000.]),np.array([6.0,6.4]),2000.)==(6.0,6.0)
assert entry(np.array([100.,800.]),np.array([9.0,6.0]),2000.)==(6.0,6.0) and entry(np.array([100.]),np.array([9.0]),2000.) is None
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
def run(FROM,TO,label):
    SK=Counter()
    FX=pd.read_sql(f"SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE kickoff>=timestamptz '{FROM}'-interval '20 minutes' AND kickoff<timestamptz '{TO}'+interval '20 minutes' AND status='FT' AND hg IS NOT NULL",con)
    FX['k']=pd.to_datetime(FX.kickoff,utc=True); FX=FX.sort_values('k').reset_index(drop=True); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.values.astype('datetime64[ns]'); ids=[int(x) for x in FX.fixture_id]
    PS=pd.read_sql("SELECT fixture_id,team,player,COALESCE(minutes,0) minutes,COALESCE(goals,0) goals FROM af_player_stats WHERE fixture_id=ANY(%s)",con,params=(ids,))
    OG=pd.read_sql("SELECT fixture_id,count(*) c FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail='Own Goal' GROUP BY 1",con,params=(ids,)); OGD={int(r.fixture_id):int(r.c) for r in OG.itertuples()}
    SQ={k:x for k,x in PS.groupby('fixture_id')}; Res={}
    for r in FX.itertuples():
        fx=int(r.fixture_id); s=SQ.get(fx)
        if s is None: SK['fixture: no player stats']+=1; continue
        pl={}
        for p in s.itertuples():
            o=pl.get(p.player)
            if o is None: pl[p.player]=dict(min=int(p.minutes),g=int(p.goals),home=(p.team==r.home))
            else: o['min']=max(o['min'],int(p.minutes)); o['g']=max(o['g'],int(p.goals))
        if sum(v['g'] for v in pl.values())+OGD.get(fx,0)!=r.hg+r.ag: SK['fixture: player goals do not reconcile, not traded']+=1; continue
        SK['fixture: usable']+=1; Res[fx]=pl
    P=pd.read_sql(f"SELECT market_id,event_name,market_time,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='TO_SCORE' AND market_time>='{FROM}' AND market_time<'{TO}' AND NOT inplay AND ltp>=1.01 AND ltp<1000",con)
    if P.empty: print(f"{label}: no TO_SCORE prints"); return None
    P['mt']=pd.to_datetime(P.market_time,utc=True); ep=pd.Timestamp('1970-01-01',tz='UTC'); P['tt']=(pd.to_datetime(P.ts,utc=True)-ep)/pd.Timedelta(seconds=1); P['off']=(P.mt-ep)/pd.Timedelta(seconds=1); P=P.sort_values(['market_id','sel','tt'],kind='stable')
    print(f"{label}: prints {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
    Mp={}
    for (ev,mt),_ in P.groupby(['event_name','mt'],sort=False):
        h,_x,a=str(ev).partition(' v '); lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(minutes=20)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
        Mp[(ev,mt)]=loose(norm(h),norm(a),[(q.H,q.A,int(q.fixture_id)) for q in FX.iloc[lo:hi].itertuples()])
    print(f"  events {len(Mp)}, matched {sum(v is not None for v in Mp.values())}",flush=True)
    rows=[]
    for (mid,ev,mt,sel),y in P.groupby(['market_id','event_name','mt','sel'],sort=False):
        fx=Mp.get((ev,mt))
        if fx is None: SK['runner: event not matched']+=1; continue
        if fx not in Res: SK['runner: game not usable']+=1; continue
        e=entry(y.tt.values,y.ltp.values,y.off.iloc[0])
        if e is None: SK['runner: no print in T-30 to the off']+=1; continue
        st,won,home=runner(sel,Res[fx])
        if st=='NOSQUAD': SK['runner: not in squad, not traded']+=1; continue
        if st=='VOID': SK['runner: minutes 0, void']+=1; continue
        if e[1]>200: SK['runner: over 200, not traded']+=1; continue
        rows.append((fx,y.off.iloc[0],sel,home,e[1],won))
    R=pd.DataFrame(rows,columns='g mt sel home p won'.split()); print('  counted:',dict(sorted(SK.items())),flush=True)
    if R.empty: return None
    R['lay']=[lay_settle(step(p,1),w) for p,w in zip(R.p,R.won)]; R['imp']=1/R.p.map(lambda q:step(q,1)); return R
def show(name,x,col='lay',mirror=True):
    if not len(x): print(f"  {name}: n 0"); return None
    m=x.groupby('g').mt.first().median(); a=x[x.mt<=m][col]; b=x[x.mt>m][col]; n=len(x); t=tstat(x[col].values); tg=tstat(x.groupby('g')[col].sum().values)
    ok=passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,x[col].mean())
    print(f"  {name:26s} n {n:5d} games {x.g.nunique():4d} per10 {x[col].mean():+.3f} t {t:5.2f} tg {tg:5.2f} h1 {a.mean() if len(a) else float('nan'):+.3f} (n {len(a)}) h2 {b.mean() if len(b) else float('nan'):+.3f} (n {len(b)}) won {x.won.mean():.3f} implied {x.imp.mean():.3f} PASS {ok and tg>=3.5}")
    return ok and tg>=3.5
print("\n== REGRESSION, Aug-Sep 2026, the window that chose the line: should be near n 921, 214 games, +0.409, t 2.95. NOT evidence.",flush=True)
Rr=run('2026-08-01','2026-10-01','Aug-Sep')
if Rr is None: sys.exit('regression window empty: a code fault')
show('AWAY lay, regression',Rr[~Rr.home])
print("\n== UNSEEN, Jun-Jul 2026",flush=True)
R=run('2026-06-01','2026-08-01','Jun-Jul')
if R is None: print("no trades in the unseen window"); print("\n== SURVIVORS: none"); sys.exit(0)
A=R[~R.home]; P_=show('AWAY lay, THE SCORED LINE',A)
print("\n== mirrors, not scored"); show('HOME lay',R[R.home]); show('ALL lay',R)
A=A.assign(mo=pd.to_datetime(A.mt,unit='s').dt.strftime('%Y-%m'))
for k,x in A.groupby('mo'): show('AWAY lay '+k,x)
for lo,hi in ((1,4),(4,6),(6,10),(10,20),(20,200.01)): show(f'AWAY lay p {lo}-{hi:.0f}',A[(A.p>=lo)&(A.p<hi)])
print("\n== SURVIVORS (standard bar, and t on per-game sums >= 3.5)"); print("AWAY lay PASS" if P_ else "none"); print(f"done {time.time()-T0:.0f}s")
PY
