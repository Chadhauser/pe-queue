#!/bin/bash
set -o pipefail
# 499_engine_patch_check (Finder 2026-11-04, queue item 0i, daily until 7 Nov): does the patched goal engine carry real prices? The number 499 is reused: 450-499 are all taken.
# READ ONLY: no table is written and watchman/GOAL_SIGNAL_LIVE.txt is not touched, as a pass cannot arise at this n and that file is item 00's.
# WINDOW: goal_live_predictions and goal_alerts since 2026-11-03 19:41 UTC. The week before is printed as a baseline.
# SETTLEMENT (item 00's rule): back at real_price less one tick, 10 stake, 2% commission on winnings, result from ft_score, never from the stored outcome. Every alert is counted: priced, unpriced or unsettled.
# RECORDER CHECK: stored prices (a sample of 600 rows) are compared with liq_sample, nearest sample within 90 s, name match as jobs/460; a fixture counts as covered if its name matches a recorder event while it is being predicted. That match is strict, so coverage is understated. watchlist_id is NULL on every row of the window, so names and leagues come from goal_timeline by fixture_id.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30); pd.set_option('display.max_colwidth',44)
CUT='2026-11-03 19:41+00'; BASE='2026-10-27 00:00+00'
def tick_below(p):
    for hi,t in ((2,.01),(3,.02),(4,.05),(6,.1),(10,.2),(20,.5),(30,1),(50,2),(100,5),(1001,10)):
        if p<=hi+1e-9: return round(p-t,2)
def back_pnl(price,won):
    a=tick_below(price)
    if a<=1.01: return np.nan
    return round(10*(a-1)*0.98,4) if won else -10.0
def mapact(a):
    m=re.match(r"BACK (Over|Under) (\d)\.5 Goals",a or "")
    if not m: return None,None,None
    s,k=m.group(1),int(m.group(2))
    if k==2: return 'OU25',s.upper(),2.5
    if k in (1,3): return f'OU{k}5',f"{s.upper()} {k}.5 GOALS",k+.5
    return None,None,k+.5
def won_of(action,ft):
    m=re.match(r"BACK (Over|Under) (\d\.5) Goals",action or "")
    try: h,a=str(ft).split('-'); tot=int(h)+int(a)
    except Exception: return None
    if not m: return None
    return tot>float(m.group(2)) if m.group(1)=='Over' else tot<float(m.group(2))
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): X,Y=norm(a),norm(b); return len(X&Y)/max(1,len(X|Y))
def best_event(h,a,events):
    sc=[]
    for ev in events:
        if ' v ' in ev:
            x,y=ev.split(' v ',1); sc.append((sim(h,x)+sim(a,y),ev))
    sc.sort(key=lambda z:-z[0])
    if not sc: return None,0.0,False
    ok=sc[0][0]>=1.0 and (len(sc)==1 or sc[0][0]-sc[1][0]>=0.3)
    return sc[0][1],sc[0][0],ok
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, worked by hand
assert tick_below(2.06)==2.04 and tick_below(2.0)==1.99 and tick_below(1.06)==1.05
assert abs(back_pnl(2.06,True)-10*1.04*0.98)<1e-9 and back_pnl(2.06,False)==-10.0     # a 2.04: profit 10.40, less 2% = 10.192
assert np.isnan(back_pnl(1.02,True)) and abs(back_pnl(1.06,True)-0.49)<1e-9            # 1.05: profit 0.50, less 2% = 0.49
assert won_of('BACK Over 3.5 Goals','3-0') is False and won_of('BACK Over 3.5 Goals','2-1') is False and won_of('BACK Over 3.5 Goals','3-1') is True
assert won_of('BACK Under 3.5 Goals','0-2') is True and won_of('BACK Under 3.5 Goals',None) is None and won_of('LAY x','1-0') is None
assert mapact('BACK Under 3.5 Goals')==('OU35','UNDER 3.5 GOALS',3.5) and mapact('BACK Over 2.5 Goals')==('OU25','OVER',2.5) and mapact('BACK Over 4.5 Goals')[0] is None
assert best_event('Birmingham','Millwall',['Birmingham v Millwall','Leeds v Hull'])==('Birmingham v Millwall',2.0,True)
assert best_event('Leeds','Hull',['Birmingham v Millwall'])[2] is False
print("checks: OK",flush=True)
T0=time.time()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
P=pd.read_sql("""SELECT p.id,p.captured_at,p.watchlist_id,p.fixture_id,p.minute,p.fav_price::float fav_price,p.under25_price::float under25_price,p.home_sot,p.away_sot,p.home_da,
   p.stats_json->>'stats_source' stats_source FROM goal_live_predictions p WHERE p.captured_at>=%s""",con,params=(CUT,))
# watchlist_id is NULL on every row of the window, so names and leagues come from goal_timeline by fixture_id
ids=[int(x) for x in P.fixture_id.dropna().unique()]
NM=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,league_name league FROM goal_timeline WHERE fixture_id=ANY(%s) ORDER BY fixture_id",con,params=(ids,))
P=P.merge(NM,on='fixture_id',how='left')
HS=set(pd.read_sql("SELECT DISTINCT fixture_id FROM goal_stats_live WHERE captured_at>=%s",con,params=(CUT,)).fixture_id)
P['has_stats']=P.fixture_id.isin(HS)
B=pd.read_sql("""SELECT count(*) n,count(fav_price) fav,count(under25_price) u25,count(home_sot) sot FROM goal_live_predictions WHERE captured_at>=%s AND captured_at<%s""",con,params=(BASE,CUT))
A=pd.read_sql("""SELECT id,sent_at,strategy_id,fixture,minute,score,action,target_price_min::float tmin,target_price_max::float tmax,settled,ft_score,outcome,
   real_price::float real_price,real_lay_price::float real_lay,real_price_ts,real_event FROM goal_alerts WHERE sent_at>=%s ORDER BY sent_at""",con,params=(CUT,))
BA=pd.read_sql("SELECT count(*) n,count(real_price) priced FROM goal_alerts WHERE sent_at>=%s AND sent_at<%s",con,params=(BASE,CUT))
P['captured_at']=pd.to_datetime(P.captured_at,utc=True); A['sent_at']=pd.to_datetime(A.sent_at,utc=True); A['real_price_ts']=pd.to_datetime(A.real_price_ts,utc=True)
print(f"predictions {len(P)}, {P.captured_at.min()} .. {P.captured_at.max()}, fixtures {P.fixture_id.nunique()}, watchlist null {P.watchlist_id.isna().sum()}, league null {P.league.isna().sum()}; alerts {len(A)}; {time.time()-T0:.0f}s",flush=True)
print(f"BASELINE {BASE} to the patch: predictions n {int(B.n[0])}, fav {B.fav[0]/max(1,B.n[0]):.1%}, under25 {B.u25[0]/max(1,B.n[0]):.1%}, sot {B.sot[0]/max(1,B.n[0]):.1%}; alerts n {int(BA.n[0])}, real_price {BA.priced[0]/max(1,BA.n[0]):.1%}")
# recorder, chunked by day, only the markets needed
lo=min(P.captured_at.min(),A.sent_at.min() if len(A) else P.captured_at.min())-pd.Timedelta(minutes=5); hi=pd.Timestamp.now(tz='UTC'); F=[]; d=lo
while d<hi:
    e=min(d+pd.Timedelta(hours=8),hi)
    F.append(pd.read_sql("""SELECT ts,event_name,mkt,sel,back_px::float back_px,lay_px::float lay_px FROM liq_sample WHERE ts>=%s AND ts<%s AND
       ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel IN ('OVER','UNDER')) OR (mkt='OU15' AND sel IN ('OVER 1.5 GOALS','UNDER 1.5 GOALS')) OR (mkt='OU35' AND sel IN ('OVER 3.5 GOALS','UNDER 3.5 GOALS')))""",con,params=(d.to_pydatetime(),e.to_pydatetime()))); d=e
L=pd.concat(F,ignore_index=True); L['ts']=pd.to_datetime(L.ts,utc=True); con.close()
print(f"recorder rows {len(L)}, events {L.event_name.nunique()}; {time.time()-T0:.0f}s",flush=True)
Ev=L.groupby('event_name').ts.agg(['min','max'])
# fixture -> recorder event, using events live while the fixture is predicted
FX=P.groupby(['fixture_id','league','home_team','away_team'],dropna=False).agg(rows=('id','size'),t0=('captured_at','min'),t1=('captured_at','max'),fav=('fav_price','count'),u25=('under25_price','count'),sot=('home_sot','count'),has_stats=('has_stats','max')).reset_index()
print(f"fixtures with a name from goal_timeline {FX.home_team.notna().sum()} of {len(FX)}; with goal_stats_live rows {int(FX.has_stats.sum())}; home_sot fill on those fixtures {P[P.has_stats].home_sot.notna().mean():.1%} (n {int(P.has_stats.sum())}), elsewhere {P[~P.has_stats].home_sot.notna().mean():.1%} (n {int((~P.has_stats).sum())})")
ev=[];sc=[];ok=[]
for r in FX.itertuples():
    cand=Ev[(Ev['max']>=r.t0-pd.Timedelta(minutes=5))&(Ev['min']<=r.t1+pd.Timedelta(minutes=5))].index.tolist()
    a,b,c=best_event(r.home_team,r.away_team,cand); ev.append(a); sc.append(b); ok.append(c)
FX['event']=ev; FX['score']=sc; FX['covered']=ok
print("\n== PREDICTIONS: fill rates overall")
print(f"rows {len(P)}, fav_price {P.fav_price.notna().mean():.1%}, under25_price {P.under25_price.notna().mean():.1%}, home_sot {P.home_sot.notna().mean():.1%}, stats_source=goal_stats_live {(P.stats_source=='goal_stats_live').mean():.1%}; other stats_source values {P.stats_source.value_counts(dropna=False).to_dict()}")
G=FX.groupby('league',dropna=False).agg(fixtures=('rows','size'),rows=('rows','sum'),fav=('fav','sum'),u25=('u25','sum'),sot=('sot','sum'),covered_fx=('covered','sum'))
cov=FX[FX.covered].groupby('league',dropna=False).agg(cov_rows=('rows','sum'),cov_fav=('fav','sum'),cov_u25=('u25','sum'))
G=G.join(cov).fillna(0)
for c,n,d_ in (('fav%','fav','rows'),('u25%','u25','rows'),('sot%','sot','rows'),('cov_fav%','cov_fav','cov_rows'),('cov_u25%','cov_u25','cov_rows')):
    G[c]=(100*G[n]/G[d_].replace(0,np.nan)).round(1)
print("\n== per league (cov_ = fixtures matched to a recorder event)")
print(G[['fixtures','covered_fx','rows','fav%','u25%','sot%','cov_rows','cov_fav%','cov_u25%']].sort_values('rows',ascending=False).to_string())
tot=FX[FX.covered]; print(f"\nALL fixtures covered by the recorder: {int(FX.covered.sum())} of {len(FX)}; on covered rows fav {tot.fav.sum()/max(1,tot.rows.sum()):.1%}, under25 {tot.u25.sum()/max(1,tot.rows.sum()):.1%}")
print("\n== fixtures NOT covered: fixture v best recorder name (first 20, most rows first)")
print(FX[~FX.covered].sort_values('rows',ascending=False).head(20)[['league','home_team','away_team','rows','fav','event','score']].round(2).to_string(index=False))
print("\n== covered fixtures with the lowest fav fill (first 20)")
y=FX[FX.covered].copy(); y['fav%']=(100*y.fav/y.rows).round(1); y['u25%']=(100*y.u25/y.rows).round(1)
print(y.sort_values(['fav%','rows'],ascending=[True,False]).head(20)[['league','home_team','away_team','event','rows','fav%','u25%']].to_string(index=False))
# are the stored prices the recorder's prices?
Lk=L.sort_values('ts')
def nearest(ev_,mk,sl,t):
    g=Lk[(Lk.event_name==ev_)&(Lk.mkt==mk)&(Lk.sel==sl)]
    if len(g)==0: return None
    i=(g.ts-t).abs().idxmin(); s=g.loc[i]
    return s if abs((s.ts-t).total_seconds())<=90 else None
Pm=P.merge(FX[FX.covered][['fixture_id','event']],on='fixture_id')
S=Pm[Pm.fav_price.notna()|Pm.under25_price.notna()]; S=S.sample(min(len(S),600),random_state=1); rows=[]
for r in S.itertuples():
    h=nearest(r.event,'MO','HOME',r.captured_at); a=nearest(r.event,'MO','AWAY',r.captured_at); u=nearest(r.event,'OU25','UNDER',r.captured_at)
    hb=h.back_px if h is not None else np.nan; ab=a.back_px if a is not None else np.nan; ub=u.back_px if u is not None else np.nan
    rows.append((r.fav_price,hb,ab,r.under25_price,ub,r.minute))
Q=pd.DataFrame(rows,columns=['fav','hb','ab','u25','ub','minute'])
Qf=Q[Q.fav.notna()&(Q.hb.notna()|Q.ab.notna())].copy(); Qf['fav_rec']=Qf[['hb','ab']].min(axis=1); Qf['d']=(Qf.fav-Qf.fav_rec); Qf['side']=(Qf[['hb','ab']].sub(Qf.fav,axis=0).abs().min(axis=1))
Qu=Q[Q.u25.notna()&Q.ub.notna()].copy(); Qu['d']=Qu.u25-Qu.ub
print(f"\n== stored price v recorder back, nearest within 90 s, sample of {len(S)}")
if len(Qf): print(f"fav n {len(Qf)}: median |fav - lower of home, away| {Qf.d.abs().median():.3f}, within 2% {(Qf.d.abs()/Qf.fav_rec<=.02).mean():.1%}; median |fav - closer of home, away| {Qf.side.median():.3f}, within 2% {(Qf.side/Qf.fav<=.02).mean():.1%}")
if len(Qu): print(f"under25 n {len(Qu)}: median |diff| {Qu.d.abs().median():.3f}, mean diff {Qu.d.mean():+.3f}, within 2% {(Qu.d.abs()/Qu.ub<=.02).mean():.1%}")
# alerts
print("\n== ALERTS since the patch, every one")
rows=[]
for r in A.itertuples():
    mk,sl,line=mapact(r.action); w=won_of(r.action,r.ft_score)
    home,away=(r.fixture.split(' v ',1)+[''])[:2]
    cand=Ev[(Ev['max']>=r.sent_at-pd.Timedelta(minutes=5))&(Ev['min']<=r.sent_at+pd.Timedelta(minutes=5))].index.tolist()
    evn,sc_,ok_=best_event(home,away,cand)
    s=nearest(evn,mk,sl,r.sent_at) if (ok_ and mk) else None
    rb=s.back_px if s is not None else np.nan; rl=s.lay_px if s is not None else np.nan
    gap=(r.sent_at-r.real_price_ts).total_seconds() if pd.notna(r.real_price_ts) else np.nan
    status=('real_price' if pd.notna(r.real_price) else ('no_line_recorded' if not mk else ('no_event_match' if not ok_ else ('no_sample_90s' if s is None else ('recorder_has_price' if pd.notna(rb) and rb>1.01 else 'no_back_at_touch')))))
    used=r.real_price if pd.notna(r.real_price) else np.nan
    rows.append(dict(id=r.id,strategy=r.strategy_id,fixture=r.fixture[:30],m=r.minute,score=r.score,action=r.action.replace('BACK ','').replace(' Goals',''),band=f"{r.tmin}-{r.tmax}",real=r.real_price,real_lay=r.real_lay,gap_s=gap,rec_back=rb,rec_lay=rl,in_band=(r.tmin<=r.real_price<=r.tmax) if pd.notna(r.real_price) else None,ft=r.ft_score,stored=r.outcome,won=w,status=status,pnl=(back_pnl(used,w) if (pd.notna(used) and w is not None) else np.nan),pnl_rec=(back_pnl(rb,w) if (pd.notna(rb) and rb>1.01 and w is not None) else np.nan),ev=evn,simsc=round(sc_,2)))
R=pd.DataFrame(rows)
print(R[['id','strategy','fixture','m','score','action','band','real','real_lay','gap_s','rec_back','rec_lay','in_band','ft','stored','status','pnl','pnl_rec']].to_string(index=False))
print("\n== alert names v recorder"); print(R[['fixture','ev','simsc','status']].to_string(index=False))
print("\n== was the alert's line ever recorded for that event in the window? rows per market")
for r in R.itertuples():
    mk=mapact(A[A.id==r.id].action.iloc[0])[0]; g=L[L.event_name==r.ev]
    print(f"  {r.id} {r.fixture}: wants {mk}; "+", ".join(f"{m} {int((g.mkt==m).sum())}" for m in ('MO','OU15','OU25','OU35')))
n=len(R)
print(f"\nalerts {n}; real_price {R.real.notna().sum()} = {R.real.notna().mean():.1%}; in band of those {R.in_band.dropna().astype(bool).mean() if R.in_band.notna().any() else float('nan'):.1%}; status {R.status.value_counts().to_dict()}")
mm=R[R.won.notna()&R.stored.notna()]; print(f"stored outcome disagrees with ft_score on {int(((mm.stored=='WIN')!=(mm.won.astype(bool))).sum())} of {len(mm)}")
print("\n== SETTLEMENT at real_price less a tick, 10 stake, 2%")
def line(name,x):
    x=x.dropna()
    if len(x)==0: print(f"{name}: n 0"); return
    print(f"{name}: n {len(x)}, per 10 {x.mean():+.3f}, t {tstat(x):.2f}, sum {x.sum():+.2f}")
line("real_price as stored",R.pnl); line("recorder back from this job's own match",R.pnl_rec)
for sid,g in R.groupby('strategy'): line(f"  {sid} stored",g.pnl); line(f"  {sid} recorder",g.pnl_rec)
print(f"\n== SURVIVORS: 0 (largest possible n is {n}, bar is 300; GOAL_SIGNAL_LIVE.txt not touched)")
print(f"elapsed {time.time()-T0:.0f}s")
PY
