#!/bin/bash
set -o pipefail
# 499_ht_double_change (Finder 2026-11-05, queue item 92, Finder's own, source a, from jobs/499_subs_signal.sh): backing a team one down at HT made +0.709 with 2+ changes (n 707, t 0.50) v -2.177 with none (n 3,119) and -2.566 with one (n 1,149). A contrast picked after seeing the table, so it is read on a season it has not seen. Rule fixed before any 2026 price was read: back the team, MO, hold to the result, bands all and <=6. Read only.
# TAPE 2024, 2025 (bf_hist_price): the same entry as item 87, with the entry price bands and the largest win removed, to see whether the contrast is one big price. Reading only.
# UNSEEN af_events and af_fixtures Jul-Sep 2026 x bf_hist_other MATCH_ODDS, names matched side to side with lib_cand.loose, market time within 20 min of the af kick-off. Runner names must be the event's own.
# CLOCK this tape has wall clock only. Restart is taken as kick-off + 63 min. Entry is the first in-play print in KO+64..KO+67 min, about 47-50 of the match, filled at the worse of it and the next print within 2 min, one tick adverse. No print: no trade. No trade if a goal with af minute <= 46 + (print - KO - 63 min) + 1, counted, so a goal the market has seen is not traded through. The clock is an estimate: a late restart can put a print before the changes are visible, an early one after a goal the guard misses.
# BAR n >= 300 is out of reach on 3 months (about 120 expected), so this cannot pass. A positive read gets a forward item, a negative one closes the contrast.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def ch_state(me,op,n46):
    return f"CH{min(n46,2)}" if me==op-1 else None
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def entry_wall(ts,px,ko):
    """ts seconds ascending, ko seconds. (print index, worse-of-next fill for a back) in KO+64..KO+67 min, or None."""
    i=first_idx(ts,ko+64*60,ko+67*60)
    if i is None: return None
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]<=ts[i]+120: p=min(p,float(px[i+1]))
    return i,p
def goal_seen(goal_minutes,t,ko):
    lim=46+(t-ko-63*60)/60+1
    return any(46<=g<=lim for g in goal_minutes)
def summary(name,v,h=None):
    v=np.asarray(v,dtype=float)
    if len(v)==0: return dict(line=name,n=0)
    s=np.sort(v); d=dict(line=name,n=len(v),per10=round(v.mean(),3),t=round(tstat(v),2),no_top_win=round(s[:-1].mean(),3) if len(v)>1 else np.nan,top_win=round(s[-1],1))
    if h is not None:
        h=np.asarray(h); d['h1']=round(v[h==1].mean(),3) if (h==1).any() else np.nan; d['h2']=round(v[h==2].mean(),3) if (h==2).any() else np.nan
    return d
# known answers
assert ch_state(0,1,0)=='CH0' and ch_state(1,2,1)=='CH1' and ch_state(0,1,3)=='CH2' and ch_state(1,1,2) is None and ch_state(0,2,2) is None
_t=np.array([3800.,3900.,3950.,4100.]); _p=np.array([3.0,4.0,3.5,9.0])
assert entry_wall(_t,_p,0)==(1,3.5)                                         # 64 min is 3840 s; first print 3900 at 4.0; next at 3950 is lower, back takes 3.5
assert entry_wall(np.array([3800.,4100.]),np.array([3.,4.]),0) is None      # nothing inside 3840..4020
assert goal_seen([46],3900,0) and goal_seen([49],3900,0) and not goal_seen([50],3900,0) and not goal_seen([30],3900,0)    # 3900 s is 65 min: limit 46+2+1 = 49
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and bk(1.01,True) is None
_s=summary('x',[10.,-10.,-10.,50.],[1,1,2,2]); assert _s['n']==4 and _s['per10']==10.0 and _s['no_top_win']==round(-10/3,3) and _s['top_win']==50.0 and _s['h1']==0.0 and _s['h2']==20.0
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
def load_events(ids):
    E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home,type FROM af_events WHERE fixture_id=ANY(%s) AND is_home IS NOT NULL AND (type='subst' OR (type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')))",con,params=(ids,))
    goals=defaultdict(list); n46=defaultdict(int)
    for r in E.itertuples():
        if r.type=='Goal': goals[r.fixture_id].append(int(r.minute))
        elif int(r.minute)==46: n46[(r.fixture_id,bool(r.is_home))]+=1
    return goals,n46
# ---- TAPE
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.season IN (2024,2025) AND f.ht_hg<>f.ht_ag""",con)
goals,n46=load_events(list(map(int,G.fixture_id))); rows=[]; px=defaultdict(dict)
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,minute,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute BETWEEN 47 AND 52 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    for (e,s),g in P.groupby(['event_id','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][s]=a
for r in G.itertuples():
    b=px.get(r.event_id)
    if not b: continue
    gm=goals.get(r.fixture_id,[])
    for ih,sel,me,op,won in ((True,'HOME',r.ht_hg,r.ht_ag,r.hg>r.ag),(False,'AWAY',r.ht_ag,r.ht_hg,r.ag>r.hg)):
        st=ch_state(me,op,n46.get((r.fixture_id,ih),0)); arr=b.get(sel)
        if st is None or arr is None: continue
        d=next((m for m in range(47,51) if arr[m]==arr[m]),None)
        if d is None or any(46<=g<=d for g in gm): continue
        p=float(arr[d])
        for k in (d+1,d+2):
            if arr[k]==arr[k]: p=min(p,float(arr[k])); break
        a=step(p,-1)
        if a<=1.01: continue
        rows.append((st,1 if r.season==2024 else 2,p,back_settle(a,won)))
T=pd.DataFrame(rows,columns=['st','h','p','v']); T['band']=pd.cut(T.p,[1,3,6,12,1001],labels=['<=3','3-6','6-12','>12'])
print(f"\n== TAPE 2024, 2025, reading only; trades {len(T)}, {time.time()-T0:.0f}s")
o=[]
for st,x in T.groupby('st'):
    o.append(summary(f"{st} all",x.v.values,x.h.values)); o.append(summary(f"{st} <=6",x[x.p<=6].v.values,x[x.p<=6].h.values))
    for b,y in x.groupby('band',observed=True): o.append(summary(f"{st} {b}",y.v.values,y.h.values))
print(pd.DataFrame(o).to_string(index=False),flush=True)
# ---- UNSEEN
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,ht_hg,ht_ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ht_hg IS NOT NULL AND kickoff>='2026-07-01' AND kickoff<'2026-10-01'",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:t.timestamp()); F['H']=F.home.map(norm); F['A']=F.away.map(norm); F=F.sort_values('ks').reset_index(drop=True)
goals,n46=load_events(list(map(int,F.fixture_id))); ksv=F.ks.values; print(f"\n== UNSEEN af games Jul-Sep 2026 {len(F)}",flush=True)
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",('MATCH_ODDS','MATCH_ODDT','MATCH_ODDT'))
ids=[r[0] for r in cur.fetchall() if '|' in r[0]]; MK={}; seen=defaultdict(list); print(f"MATCH_ODDS markets on the tape {len(ids)}, {time.time()-T0:.0f}s",flush=True)
for mid in ids:
    _,ev,mt=mid.split('|',2)
    if ' v ' not in ev: continue
    ms=pd.Timestamp(mt).timestamp(); lo,hi=np.searchsorted(ksv,ms-1200),np.searchsorted(ksv,ms+1200,side='right')
    if hi<=lo: continue
    h,_,a=ev.partition(' v '); idx=loose(norm(h),norm(a),[(F.H.iat[i],F.A.iat[i],i) for i in range(lo,hi)])
    if idx is not None: seen[idx].append((mid,h.strip(),a.strip(),ms))
one={k:v[0] for k,v in seen.items() if len(v)==1}; print(f"af games matched to one market {len(one)}; matched to several, dropped {sum(len(v)>1 for v in seen.values())}; {time.time()-T0:.0f}s",flush=True)
st_ct=defaultdict(int); rows=[]; items=[]
for i,(mid,h,a,ms) in one.items():
    f=F.iloc[i]
    for ih,me,op,won,name in ((True,f.ht_hg,f.ht_ag,f.hg>f.ag,h),(False,f.ht_ag,f.ht_hg,f.ag>f.hg,a)):
        s=ch_state(me,op,n46.get((f.fixture_id,ih),0))
        if s: items.append((mid,name,s,won,ms,f.fixture_id,f.ks))
print(f"team states in matched games {len(items)}",flush=True)
mids=list({x[0] for x in items}); PX={}
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    P['tt']=(pd.to_datetime(P.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
    for (m,s),g in P.groupby(['market_id','sel'],sort=False): g=g.sort_values('tt'); PX[(m,s)]=(g.tt.values,g.ltp.values)
con.close()
for mid,name,s,won,ms,fx,ks in items:
    g=PX.get((mid,name))
    if g is None: st_ct['no_runner_rows']+=1; continue
    e=entry_wall(g[0],g[1],ms)
    if e is None: st_ct['no_print']+=1; continue
    if goal_seen(goals.get(fx,[]),g[0][e[0]],ms): st_ct['goal_seen']+=1; continue
    a=step(e[1],-1)
    if a<=1.01: st_ct['floor']+=1; continue
    rows.append((s,e[1],back_settle(a,won),fx)); st_ct['ok']+=1
U=pd.DataFrame(rows,columns=['st','p','v','fx']); print("trade outcomes",dict(st_ct),flush=True)
o=[]
for st,x in U.groupby('st'):
    o.append(summary(f"{st} all",x.v.values)); o.append(summary(f"{st} <=6",x[x.p<=6].v.values))
print(pd.DataFrame(o).to_string(index=False))
print("\nSURVIVORS: none can pass at this n; the read is the sign of CH2 and its gap to CH0"); print(f"done {time.time()-T0:.0f}s")
PY
