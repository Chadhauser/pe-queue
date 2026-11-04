#!/bin/bash
set -o pipefail
# 499_greyhound_results (Finder 2026-11-04, queue item 61): greyhound results are on the box in greyhound_racecards_today, so hold-to-result reopens (item 46 was blocked for want of results). The number 499 is reused: 450-499 are all taken.
# JOIN: London date of market_time, track, dog name without its "1. " prefix. GATE: >= 80% of the card races with a winner, inside the tape's dates, must join to one tape market with exactly one winner on it; below that the item is BLOCKED and nothing is scored.
# ENTRY: the last real print at least N minutes before the scheduled off (T-1, T-5), so the entry does not need to know which print was the last; no print in the 15 minutes before that, no entry. One tick adverse; settled at the result, 2% commission, back stake 10, lay liability 10. A dog with no finish position in a race that has a winner lost; it is not dropped. Dead heats are removed and counted.
# LINES: price band, market rank by entry price, trap, track; back and lay; halves by median date. Only about 5 months overlap, so both halves share a season.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
def back_settle(p,won):
    a=step(p,-1)
    return np.nan if a<=1.01 else (10*(a-1)*0.98 if won else -10.0)
def lay_settle(p,won):
    a=step(p,1)
    return -10.0 if won else 10/(a-1)*0.98
def dog(s): return re.sub(r'[^a-z0-9]','',re.sub(r'^\s*\d+\.\s*','',str(s)).lower())
def track(e):
    m=re.match(r'^(.*?)\s+\d+(st|nd|rd|th)\s+\w+$',str(e)); return (m.group(1) if m else str(e)).strip().lower()
def entry_print(mins,px,N,window=15):
    # mins: minutes to off of each print, in time order; last print at least N before the off, within window
    best=None
    for m,p in zip(mins,px):
        if N<=m<=N+window: best=p
    return best
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, worked by hand
assert abs(back_settle(3.0,True)-(10*1.98*0.98))<1e-9 and back_settle(3.0,False)==-10.0   # a 2.98: profit 19.80, less 2% = 19.404
assert lay_settle(3.0,True)==-10.0 and abs(lay_settle(3.0,False)-(10/2.05*0.98))<1e-9      # a 3.05: wins 4.878, less 2% = 4.780
assert np.isnan(back_settle(1.01,True))
assert dog('1. Insane View')==dog("Insane  View") and dog("6. O'Malley's Boy")=='omalleysboy' and track('Central Park 15th Sep')=='central park' and track('Star Pelaw 3rd Nov')=='star pelaw'
assert entry_print([20,10,3,0.5],[5,6,7,8],1)==7 and entry_print([20,10,3,0.5],[5,6,7,8],5)==6 and entry_print([40,30],[5,6],5) is None and entry_print([0.5],[5],1) is None
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
C=pd.read_sql("SELECT race_date,track,race_id,race_time,greyhound,trap_number,finish_position FROM greyhound_racecards_today",con)
C['tk']=C.track.str.strip().str.lower(); C['d']=C.greyhound.map(dog); C['date']=pd.to_datetime(C.race_date).dt.date
C=C.drop_duplicates(['race_id','d']); print(f"card rows {len(C)}, races {C.race_id.nunique()}, dates {C.date.min()} to {C.date.max()}",flush=True)
F=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    x=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s",con,params=(a,b))
    F.append(x); print(f"  {a} rows {len(x)} {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(F,ignore_index=True); P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True)
P['mins']=(P.mt-P.t)/pd.Timedelta(minutes=1); P=P.sort_values(['market_id','sel','t'])
print(f"tape markets {P.market_id.nunique()}, dates {P.mt.min():%Y-%m-%d} to {P.mt.max():%Y-%m-%d}")
Mk=P.drop_duplicates(['market_id','sel'])[['market_id','event_name','mt','sel']].copy()
Mk['tk']=Mk.event_name.map(track); Mk['d']=Mk.sel.map(dog); lo=Mk.mt.dt.tz_convert('Europe/London'); Mk['date']=lo.dt.date; Mk['hhmm']=Mk.mt.dt.strftime('%H:%M')  # the card's race_time is UTC: 430 of 430 joined rows on two BST days sit exactly 60 min from London time
J=Mk.merge(C[['date','tk','d','race_id','race_time','trap_number','finish_position']],on=['date','tk','d'],how='left')
first,last=Mk.date.min(),Mk.date.max(); Cw=C[(C.date>=first)&(C.date<=last)]
cards_w=Cw[Cw.finish_position==1].race_id.unique(); cards_all=Cw.race_id.nunique()
hit=J.dropna(subset=['race_id'])
# one market per race, and a race time that agrees
mk_per_race=hit.groupby('race_id').market_id.nunique(); rc_per_mk=hit.groupby('market_id').race_id.nunique()
good_mk=rc_per_mk[rc_per_mk==1].index; hit=hit[hit.market_id.isin(good_mk)]; winners=hit[hit.finish_position==1].groupby('market_id').d.nunique()
one=winners[winners==1].index; dead=int((winners>1).sum()); joined=hit[hit.market_id.isin(one)].race_id.nunique()
rate=joined/max(1,len(cards_w))
tm=hit.drop_duplicates('market_id'); print(f"race time agrees with the UTC market time on {(tm.hhmm==tm.race_time).mean():.3f} of {len(tm)} joined markets")
print(f"tape runners with a card row in joined markets {J[J.market_id.isin(one)].race_id.notna().mean():.3f}")
print(f"card races in the tape's dates {cards_all}, with a winner {len(cards_w)}; joined to one market with exactly one winner {joined}; dead heats {dead}; GATE {rate:.3f} v 0.80")
print(f"tape markets in those dates {Mk.market_id.nunique()}, scored {len(one)} = {len(one)/Mk.market_id.nunique():.3f} of the tape")
if rate<0.80:
    print("\n== SURVIVORS: none; join gate SHUT, item BLOCKED"); sys.exit(0)
# a tape runner missing from a joined race's card still ran or was withdrawn: unknown, so that whole race goes, and is counted
miss=J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique(); use=[m for m in one if m not in set(miss)]
print(f"races removed as a tape runner is not on the card: {len(miss)}; scored races {len(use)}")
R0=J[J.market_id.isin(use)].copy(); R0['won']=R0.finish_position==1
PX={k:(g.mins.values,g.ltp.values) for k,g in P[P.market_id.isin(use)].groupby(['market_id','sel'],sort=False)}
rows=[]
for r in R0.itertuples():
    mn,px=PX.get((r.market_id,r.sel),([],[]))
    for N in (1,5):
        p=entry_print(mn,px,N)
        if p is not None: rows.append(dict(m=r.market_id,mt=r.mt,tk=r.tk,trap=r.trap_number,N=N,p=p,won=r.won,back=back_settle(p,r.won),lay=lay_settle(p,r.won)))
R=pd.DataFrame(rows); MED=R.mt.median(); R['half']=np.where(R.mt<=MED,1,2); print(f"entries {len(R)}; median date {MED:%Y-%m-%d}")
R['rank']=R.groupby(['m','N']).p.rank(method='first'); R['pb']=pd.cut(R.p,[1,2,3,5,8,13,21,1001],labels=['<=2','2-3','3-5','5-8','8-13','13-21','21+'])
print("\n== CALIBRATION, entry print against the result; book = sum of 1/p per race")
for N in (1,5):
    x=R[R.N==N]; b=x.assign(i=1/x.p).groupby('m').i.sum()
    print(f"T-{N}: runners {len(x)}, races {x.m.nunique()}, median book {b.median():.3f}, favourite won {x[x['rank']==1].won.mean():.3f} of {int((x['rank']==1).sum())} at mean implied {(1/x[x['rank']==1].p).mean():.3f}")
    print(x.assign(i=1/x.p).groupby('pb',observed=True).agg(n=('won','size'),implied=('i','mean'),won=('won','mean')).round(3).T.to_string())
L=[]
def add(x,name):
    for sd in ('back','lay'):
        v=x.dropna(subset=[sd])
        if len(v)<30: continue
        a=v[v.half==1][sd]; b=v[v.half==2][sd]; cl=v.groupby('m')[sd].sum()
        L.append(dict(line=f"{name} {sd}",n=len(v),races=v.m.nunique(),per10=v[sd].mean(),t=tstat(v[sd]),t_race=tstat(cl),h1=a.mean(),n1=len(a),h2=b.mean(),n2=len(b)))
for N in (1,5):
    x=R[R.N==N]; add(x,f"T-{N} all")
    for k,g in x.groupby('pb',observed=True): add(g,f"T-{N} price {k}")
    for k,g in x.groupby('rank'):
        if k<=6: add(g,f"T-{N} rank {int(k)}")
    for k,g in x.groupby('trap'): add(g,f"T-{N} trap {int(k)}")
    for k,g in x.groupby('tk'): add(g,f"T-{N} track {k}")
T=pd.DataFrame(L); T['PASS']=(T.n>=300)&(T.n1>=150)&(T.n2>=150)&(T.h1>0)&(T.h2>0)&(T.t>=3.5)&(T.per10>=0.15)
print(f"\nlines {len(T)}, with n >= 300 {int((T.n>=300).sum())}")
print("\n== TOP 15 by t, n >= 300"); print(T[T.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
S=T[T.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(T)} lines")
if len(S): print(S.sort_values('t',ascending=False).round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
