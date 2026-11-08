#!/bin/bash
set -o pipefail
# 499_under_bound (Finder 2026-11-08, 22:55 UTC run, queue item 473, Finder's own, source c structural; built from jobs/315_grid_v2.sh and the lib_cand/lib_official engine).
# With g goals scored, Under g+0.5 wins only if no more goals are scored, and then the current result stands (the Draw if level, the leader if not), so
# P(Under g+0.5) <= P(current result on Match Odds) exactly. GAP = 1/U - 1/M from the two prints at the same tape minute (bf_hist_price, 1-min LTP, no forward fill).
# States g = 1, 2, 3 (OU15, OU25, OU35). Score from af_events via af_price_map. Entry minute 10-87, at least 3 min after the last goal (minute + extra).
# Stale guard, fixed before any price was read: both prints at the entry minute differ from their last print before that goal, Under printed longer than before it
# (it needed one more goal before, so it must lengthen), and M moved the right way (shorter if level or the scorer leads, longer if the trailer scored).
# Classes V2 GAP >= 0.02, V0 0-0.02, C2 -0.02-0 (control), C5 -0.05 to -0.02 (control); first qualifying minute per game per score per class.
# Fill at the worse of the entry-minute print and the next print within 2 min, one tick adverse, GBP 10 risk, 2% on profit, held to the af FT result, never dropped.
# Legs: BACK_M (scored line: V2 ALL), LAY_U, PAIR = (BACK_M + LAY_U) / 2. Women and youth out. Price-map guard: the af winner's last MO print of the game under 1.5.
# FIX once (first run, 8 Nov, two biases found in review that flatter BACK_M; first run V2 BACK_M ALL n 262 -1.543, C5 BACK_M T>60 n 754 +1.023 t 3.41, both VOID):
# map guard now reads the first goal's MO move, not the af winner's last print; a goal is known from 2 min after it, one within 1 min of entry takes the worst prints.
# Halves by season, 2024 v 2025. Standard bar. Read only, no tables written. Prints only (LTP), not a touch: an upper bound on what a taker gets.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,lay_settle
from lib_official import group,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
OU={1:'OU15',2:'OU25',3:'OU35'}
def gap(m,u): return 1/u-1/m
def klass(g):
    if g>=0.02: return 'V2'
    if g>=0: return 'V0'
    if g>=-0.02: return 'C2'
    if g>=-0.05: return 'C5'
    return None
def bk_m(p,won):
    a=step(p,-1); return None if a<=1.01 else back_settle(a,won)
def ly_u(p,won): return lay_settle(step(p,1),won)
def cur_sel(h,a): return 'DRAW' if h==a else ('HOME' if h>a else 'AWAY')
def m_dir_ok(h,a,scorer,m_now,m_ref):
    """M must have moved the right way since the last goal: shorter if level now or the scorer leads, longer if the trailer scored."""
    if h==a: return m_now<m_ref
    lead='h' if h>a else 'a'
    return m_now<m_ref if scorer==lead else m_now>m_ref
def worse(arr,t,side):
    """worse of the print at t and the next print within 2 min (no forward fill)."""
    p=arr[t]
    for k in (1,2):
        if t+k<len(arr) and not np.isnan(arr[t+k]):
            q=arr[t+k]; return max(p,q) if side=='L' else min(p,q)
    return p
# known answers, worked by hand
# 1-1, Draw 3.0 (0.3333), Under 2.5 2.5 (0.40): GAP 0.0667 V2; Under 3.2 (0.3125): GAP -0.0208 C5; Under 3.1 (0.3226): -0.0108 C2; Under 2.95: +0.0056 V0
assert klass(gap(3.0,2.5))=='V2' and klass(gap(3.0,3.2))=='C5' and klass(gap(3.0,3.1))=='C2' and klass(gap(3.0,2.95))=='V0' and klass(gap(3.0,4.0)) is None
# back M 3.0 -> 2.98, wins 19.8*0.98 = 19.404; lay U 2.5 -> 2.52, stake 10/1.52 = 6.5789, wins 6.447 after 2%, loses 10
assert abs(bk_m(3.0,True)-19.8*0.98)<1e-9 and bk_m(3.0,False)==-10.0 and abs(ly_u(2.5,False)-10/1.52*0.98)<1e-9 and ly_u(2.5,True)==-10.0
# pair at 1-1 with those prints: ends 1-1 -> (19.404 - 10)/2 = 4.702; ends 2-2 -> (19.404 + 6.447)/2; ends 2-1 -> (-10 + 6.447)/2
assert abs((bk_m(3.0,True)+ly_u(2.5,True))/2-4.702)<1e-9
assert cur_sel(1,1)=='DRAW' and cur_sel(2,1)=='HOME' and cur_sel(0,1)=='AWAY'
assert m_dir_ok(1,1,'a',3.0,4.0) and not m_dir_ok(1,1,'a',4.2,4.0) and m_dir_ok(2,0,'h',1.2,1.6) and m_dir_ok(2,1,'a',1.6,1.2) and not m_dir_ok(2,1,'a',1.15,1.2)
def first_goal_ok(book,gz):
    """scorer's MO implied: last print at or before raw minute - 1 v first print in minute+extra+1 .. +4 must rise by more than 0.03"""
    A=book.get(('MO','HOME' if gz[2]=='h' else 'AWAY'))
    if A is None: return False
    pre=A[:max(gz[0],0)]; pre=pre[~np.isnan(pre)]; post=A[gz[1]+1:gz[1]+5]; post=post[~np.isnan(post)]
    if len(pre)==0 or len(post)==0: return False
    return 1/post[0]-1/pre[-1]>0.03
_b=np.full(96,np.nan); _b[0:5]=[3.0,2.9,np.nan,1.8,1.7]
assert first_goal_ok({('MO','HOME'):_b},(2,2,'h')) and not first_goal_ok({('MO','HOME'):_b},(2,2,'a'))
x=np.array([2.0,np.nan,2.2,2.4]); assert worse(x,0,'L')==2.2 and worse(x,0,'B')==2.0 and worse(x,2,'B')==2.2 and worse(x,3,'L')==2.4
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.hg, f.ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
print("games:",len(G),"| seasons:",G.season.value_counts().to_dict(),flush=True)
G=G[G.season.isin([2024,2025])]
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, coalesce(extra,0) AS extra, is_home, detail FROM af_events
 WHERE fixture_id = ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples():
    side=('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')
    goals[r.fixture_id].append((int(r.minute),int(r.minute)+int(r.extra),side))
for k in goals: goals[k].sort(key=lambda z:(z[1],z[0]))
C=Counter(); rows=[]
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("""SELECT event_id, event_name, minute, mkt, sel, ltp::float8 ltp FROM bf_hist_price WHERE mkt IN ('MO','OU15','OU25','OU35')
                     AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 AND ltp>1.01 AND ltp<1000""",con,params=(list(sub.event_id),))
    names=P.drop_duplicates('event_id').set_index('event_id').event_name.to_dict()
    px={}
    for (eid,mkt,sel),g in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(96,np.nan); arr[g.minute.values]=g.ltp.values
        px.setdefault(eid,{})[(mkt,sel)]=arr
    del P
    for g in sub.itertuples():
        book=px.get(g.event_id)
        if not book: C['no prints']+=1; continue
        ev=names.get(g.event_id,'')
        if group(ev or ''): C['women or youth']+=1; continue
        hg,ag=int(g.hg),int(g.ag); win=cur_sel(hg,ag)
        gl=goals.get(g.fixture_id,[])
        if len(gl)!=hg+ag: C['goal events != FT score']+=1; continue
        # FIX once (first run): the guard read the af winner's last MO print, which drops lost leads the tape never printed; now the first goal's move only
        if gl and not first_goal_ok(book,gl[0]): C['guard: tape did not move at the first af goal (bad map)']+=1; continue
        C['games kept']+=1
        seen=set()
        for t in range(10,88):
            # FIX once (first run): a goal in the entry minute moved the state at once, so the old state's entries in a goal's own minute were dropped;
            # now a goal is known only from 2 min after it, and a goal within 1 min of the entry is charged the worst prints in t-3..t+2
            past=[z for z in gl if z[1]<=t-2]
            if not past: continue
            nxt=next((z[1] for z in gl if z[1]>t-2),999); amb=abs(nxt-t)<=1
            tot=len(past)
            if tot not in OU: continue
            last=past[-1]
            if t<last[1]+3: continue
            h=sum(1 for z in past if z[2]=='h'); a=tot-h
            cs=cur_sel(h,a); M=book.get(('MO',cs)); U=book.get((OU[tot],'UNDER'))
            if M is None or U is None: continue
            m=M[t]; u=U[t]
            if np.isnan(m) or np.isnan(u) or m>50 or u>50 or m<=1.01 or u<=1.01: continue
            k=klass(gap(m,u))
            if k is None: continue
            key=(h,a,k)
            if key in seen: continue
            # stale guard: last print before the goal (raw minute - 1 and earlier)
            ref=last[0]-1
            mr=M[:ref+1][~np.isnan(M[:ref+1])] if ref>=0 else np.array([]); ur=U[:ref+1][~np.isnan(U[:ref+1])] if ref>=0 else np.array([])
            if len(mr)==0 or len(ur)==0: C['guard: no pre-goal print']+=1; seen.add(key); continue
            if not (u>ur[-1] and m!=mr[-1] and m_dir_ok(h,a,last[2],m,mr[-1])): C['guard: stale or wrong-way print '+k]+=1; continue
            seen.add(key)
            if amb:
                C['next goal within 1 min of entry: worst prints']+=1
                wm=M[max(t-3,0):t+3]; wu=U[max(t-3,0):t+3]; mf=float(np.nanmin(wm)); uf=float(np.nanmax(wu))
            else: mf=worse(M,t,'B'); uf=worse(U,t,'L')
            mwon=(cs==win); uwon=(hg+ag==tot)
            b=bk_m(mf,mwon); l=ly_u(uf,uwon)
            if b is None: C['back M at ladder floor']+=1; continue
            rows.append(dict(eid=g.event_id,season=int(g.season),k=k,state='LEVEL' if h==a else 'LEAD',g=tot,t=t,m=m,u=u,gap=gap(m,u),
                             BACK_M=b,LAY_U=l,PAIR=(b+l)/2,mwon=mwon,uwon=uwon))
    print(f"  {min(i+1000,len(G))}/{len(G)} games | trades {len(rows)} | {time.time()-T0:.0f}s",flush=True)
print("\ncounts:",dict(C),flush=True)
R=pd.DataFrame(rows)
if R.empty: print("no trades"); print("\nSURVIVORS\nnone"); sys.exit(0)
R['h']=np.where(R.season==2024,1,2)
print("\ntrades by class:",R.k.value_counts().to_dict(),"| distinct games by class:",R.groupby('k').eid.nunique().to_dict())
print("win rates by class (M won, U won, mean M print, mean U print):")
print(R.groupby('k').agg(n=('m','size'),m_won=('mwon','mean'),u_won=('uwon','mean'),m_imp=('m',lambda s:(1/s).mean()),u_imp=('u',lambda s:(1/s).mean())).round(3).to_string())
out=[]
subsets={'ALL':lambda d:d,'LEVEL':lambda d:d[d.state=='LEVEL'],'LEAD':lambda d:d[d.state=='LEAD'],'T<=60':lambda d:d[d.t<=60],'T>60':lambda d:d[d.t>60],
         'G1':lambda d:d[d.g==1],'G2':lambda d:d[d.g==2],'G3':lambda d:d[d.g==3]}
for k in ('V2','V0','C2','C5'):
    for leg in ('BACK_M','LAY_U','PAIR'):
        for sn,f in subsets.items():
            d=f(R[R.k==k])
            if len(d)<20: continue
            L=line(d[leg].values,d.h.values); L.update(cls=k,leg=leg,sub=sn,games=d.eid.nunique()); out.append(L)
T=pd.DataFrame(out)[['cls','leg','sub','n','games','per10','t','n1','h1','n2','h2','maxwin','PASS']]
print(f"\n{len(T)} lines (n >= 20); scored line V2 BACK_M ALL:")
print(T[(T.cls=='V2')&(T.leg=='BACK_M')&(T['sub']=='ALL')].round(3).to_string(index=False))
print("\ntop 25 by t:"); print(T.sort_values('t',ascending=False).head(25).round(3).to_string(index=False))
print("\nall ALL lines:"); print(T[T['sub']=='ALL'].round(3).to_string(index=False))
print("\nSURVIVORS"); S=T[T.PASS]
print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
