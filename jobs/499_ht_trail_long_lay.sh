#!/bin/bash
set -o pipefail
# 499_ht_trail_long_lay (Finder 2026-11-05, queue item 93, Finder's own, source a, from jobs/499_ht_double_change.sh): backing a team one down at HT at >12 lost -3.77 per 10 in both seasons. Does the lay pay after one tick, at a £10 liability? Rule fixed before any lay was read. Read only.
# TAPE 2024, 2025: first real print in 47..50, filled at the higher of it and the next print within 2 min, one tick adverse, to the result, 2% on profit. No trade if a goal is logged at af minute 46 up to the print minute. Band on the print before the tick.
# UNSEEN Jul-Sep 2026 bf_hist_other, entry by wall clock KO+64..67 min as job 499_ht_double_change, same goal guard.
# LTP ONLY a lay at an LTP plus one tick at a long in-play price is an upper bound: real spreads there are wide. A pass needs liq_sample before anyone reads it as money.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def entry_wall(ts,px,ko):
    """First print in KO+64..KO+67 min, filled at the higher of it and the next print within 2 min, as a lay is."""
    i=first_idx(ts,ko+64*60,ko+67*60)
    if i is None: return None
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]<=ts[i]+120: p=max(p,float(px[i+1]))
    return i,p
def goal_seen(goal_minutes,t,ko):
    lim=46+(t-ko-63*60)/60+1
    return any(46<=g<=lim for g in goal_minutes)
BANDS=[('12-20',12,20),('20-30',20,30),('30-50',30,50),('50+',50,1001),('all >12',12,1001)]
def table(T):
    o=[]
    for nm,lo,hi in BANDS:
        x=T[(T.p>lo)&(T.p<=hi)]
        if not len(x): continue
        d=line(x.v.values,x.h.values); o.append(dict(band=nm,n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],win_rate=round((x.v==-10).mean(),4),implied=round((1/x.p).mean(),4),PASS=d['PASS']))
    return pd.DataFrame(o)
# known answers: lay at print 20, one tick adverse 21, stake 10/20 = 0.5. Team loses: +0.5 x 0.98 = 0.49. Team wins: -10.
assert step(20.0,1)==21.0 and abs(lay_settle(21.0,False)-0.49)<1e-9 and lay_settle(21.0,True)==-10.0
_T=pd.DataFrame(dict(p=[13.,25.,40.,60.,11.],v=[.7,-10.,.2,.1,5.],h=[1,1,2,2,1],g=[1,2,3,4,5])); _o=table(_T).set_index('band')
assert _o.loc['12-20','n']==1 and _o.loc['all >12','n']==4 and abs(_o.loc['all >12','per10']-(.7-10+.2+.1)/4)<1e-3 and _o.loc['all >12','h1']==round((.7-10)/2,3)    # 11 is outside every band
assert _o.loc['all >12','win_rate']==.25
_t=np.array([3900.,3950.]); _p=np.array([20.,23.]); assert entry_wall(_t,_p,0)==(0,23.)
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
def goals_of(ids):
    E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(ids,)); g=defaultdict(list)
    for r in E.itertuples(): g[r.fixture_id].append(int(r.minute))
    return g
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.season IN (2024,2025) AND abs(f.ht_hg-f.ht_ag)=1""",con)
goals=goals_of(list(map(int,G.fixture_id))); px=defaultdict(dict)
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,minute,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute BETWEEN 47 AND 52 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    for (e,s),g in P.groupby(['event_id','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][s]=a
rows=[]
for r in G.itertuples():
    sel,won=('HOME',r.hg>r.ag) if r.ht_hg<r.ht_ag else ('AWAY',r.ag>r.hg); arr=px.get(r.event_id,{}).get(sel)
    if arr is None: continue
    d=next((m for m in range(47,51) if arr[m]==arr[m]),None)
    if d is None or any(46<=g<=d for g in goals.get(r.fixture_id,[])): continue
    p0=float(arr[d]); p=p0
    for k in (d+1,d+2):
        if arr[k]==arr[k]: p=max(p,float(arr[k])); break
    rows.append((p,lay_settle(step(p,1),won),1 if r.season==2024 else 2,r.event_id))
T=pd.DataFrame(rows,columns=['p','v','h','g']); L=table(T); print(f"\n== TAPE 2024, 2025, games {len(G)}, trades at any price {len(T)}, {time.time()-T0:.0f}s"); print(L.to_string(index=False),flush=True)
print("(win_rate is the share the team came back to win; implied is the mean of 1/print)")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,ht_hg,ht_ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ht_hg IS NOT NULL AND abs(ht_hg-ht_ag)=1 AND kickoff>='2026-07-01' AND kickoff<'2026-10-01'",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:t.timestamp()); F['H']=F.home.map(norm); F['A']=F.away.map(norm); F=F.sort_values('ks').reset_index(drop=True); ksv=F.ks.values; goals=goals_of(list(map(int,F.fixture_id)))
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",('MATCH_ODDS','MATCH_ODDT','MATCH_ODDT'))
seen=defaultdict(list)
for mid in [r[0] for r in cur.fetchall() if '|' in r[0]]:
    _,ev,mt=mid.split('|',2)
    if ' v ' not in ev: continue
    ms=pd.Timestamp(mt).timestamp(); lo,hi=np.searchsorted(ksv,ms-1200),np.searchsorted(ksv,ms+1200,side='right')
    if hi<=lo: continue
    h,_,a=ev.partition(' v '); idx=loose(norm(h),norm(a),[(F.H.iat[i],F.A.iat[i],i) for i in range(lo,hi)])
    if idx is not None: seen[idx].append((mid,h.strip(),a.strip(),ms))
items=[]
for i,v in seen.items():
    if len(v)!=1: continue
    mid,h,a,ms=v[0]; f=F.iloc[i]
    nm,won=(h,f.hg>f.ag) if f.ht_hg<f.ht_ag else (a,f.ag>f.hg); items.append((mid,nm,won,ms,f.fixture_id))
mids=list({x[0] for x in items}); PX={}
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    P['tt']=(pd.to_datetime(P.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
    for (m,s),g in P.groupby(['market_id','sel'],sort=False): g=g.sort_values('tt'); PX[(m,s)]=(g.tt.values,g.ltp.values)
con.close(); rows=[]; ct=defaultdict(int)
for mid,nm,won,ms,fx in items:
    g=PX.get((mid,nm))
    if g is None: ct['no_runner']+=1; continue
    e=entry_wall(g[0],g[1],ms)
    if e is None: ct['no_print']+=1; continue
    if goal_seen(goals.get(fx,[]),g[0][e[0]],ms): ct['goal_seen']+=1; continue
    rows.append((e[1],lay_settle(step(e[1],1),won),1,mid)); ct['ok']+=1
U=pd.DataFrame(rows,columns=['p','v','h','g']); print(f"\n== UNSEEN Jul-Sep 2026, games with one down at HT matched {len(items)}; outcomes {dict(ct)}; {time.time()-T0:.0f}s"); print(table(U).drop(columns=['h2','n2','PASS']).to_string(index=False))
print("\nSURVIVORS (2024-25 tape only, as the bar reads; LTP only)"); P=L[L.PASS]; print(P.to_string(index=False) if len(P) else "none"); print(f"done {time.time()-T0:.0f}s")
PY
