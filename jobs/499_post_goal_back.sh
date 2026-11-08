#!/bin/bash
set -o pipefail
# 499_post_goal_back (Finder 2026-11-08, queue item 474, Finder's own, source a moves, from item 473's control lean C5 BACK_M T>60 n 754 +1.023 t 3.41).
# IN-SAMPLE READ: the same two seasons item 473 used, so no line here can PASS as a find; it asks only whether 473's lean needs the Under condition at all.
# Every goal that leaves g = 1..4 goals; entry at the first tape minute in [goal+3, goal+6] (minute + extra) with a fresh MO print of the current result
# (differs from its last print before the goal and moved the right way, the same guard as 473), and no further goal at or before the entry minute.
# Back the current result (Draw if level, else the leader), fill at the worse of that print and the next within 2 min, one tick adverse, GBP 10, 2% on profit,
# held to the af FT result, never dropped. One entry per goal (several per game, correlated: distinct games printed). Lines by goal minute band, state, g,
# and by item 473's GAP class where an Under g+0.5 print exists at the same minute. Halves by season 2024 v 2025. Read only.
# FIX once (first run, 8 Nov, two biases found in review, both flattering a back of the leader; the first run's G76+ g1 n 348 +0.713 t 4.63 is VOID):
# (1) the map guard read the af winner's last MO print, dropping lost leads the tape never printed; now it reads only the first goal's move;
# (2) entries in the minute of the next goal were dropped; now only a goal 2+ min before the entry stops it, and a goal within 1 min is charged the worst print in t-3..t+2.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle
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
    return 'FAR'
def bk_m(p,won):
    a=step(p,-1); return None if a<=1.01 else back_settle(a,won)
def cur_sel(h,a): return 'DRAW' if h==a else ('HOME' if h>a else 'AWAY')
def m_dir_ok(h,a,scorer,m_now,m_ref):
    if h==a: return m_now<m_ref
    lead='h' if h>a else 'a'
    return m_now<m_ref if scorer==lead else m_now>m_ref
def worse_b(arr,t):
    p=arr[t]
    for k in (1,2):
        if t+k<len(arr) and not np.isnan(arr[t+k]): return min(p,arr[t+k])
    return p
def worst_b(arr,t):
    """lowest print in t-3..t+2: the worst back fill when a goal lands within a minute of the entry"""
    w=arr[max(t-3,0):t+3]; w=w[~np.isnan(w)]; return float(w.min())
def first_goal_ok(book,gz):
    """scorer's MO implied: last print at or before raw minute - 1 v first print in minute+extra+1 .. +4 must rise by more than 0.03"""
    A=book.get(('MO','HOME' if gz[2]=='h' else 'AWAY'))
    if A is None: return False
    pre=A[:max(gz[0],0)]; pre=pre[~np.isnan(pre)]; post=A[gz[1]+1:gz[1]+5]; post=post[~np.isnan(post)]
    if len(pre)==0 or len(post)==0: return False
    return 1/post[0]-1/pre[-1]>0.03
_b=np.full(96,np.nan); _b[0:5]=[3.0,2.9,np.nan,1.8,1.7]
assert first_goal_ok({('MO','HOME'):_b},(2,2,'h')) and not first_goal_ok({('MO','HOME'):_b},(2,2,'a'))
assert worst_b(np.array([2.0,1.9,np.nan,2.1,2.2,1.8,1.5]),3)==1.8
def band(gm): return 'G<=45' if gm<=45 else 'G46-60' if gm<=60 else 'G61-75' if gm<=75 else 'G76+'
assert band(45)=='G<=45' and band(60)=='G46-60' and band(61)=='G61-75' and band(76)=='G76+'
assert klass(gap(3.0,2.5))=='V2' and klass(gap(3.0,4.0))=='FAR'
x=np.array([2.0,np.nan,1.9]); assert worse_b(x,0)==1.9 and worse_b(x,2)==1.9
assert abs(bk_m(3.0,True)-19.8*0.98)<1e-9 and bk_m(1.02,True) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.hg, f.ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
G=G[G.season.isin([2024,2025])]; print("games:",len(G),flush=True)
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
        if group(names.get(g.event_id,'') or ''): C['women or youth']+=1; continue
        hg,ag=int(g.hg),int(g.ag); win=cur_sel(hg,ag)
        gl=goals.get(g.fixture_id,[])
        if len(gl)!=hg+ag: C['goal events != FT score']+=1; continue
        # FIX (first run, 8 Nov, honesty not crash): the map guard read the af winner's LAST MO print, which drops games whose late equaliser
        # the tape never printed, so it threw out lost leads; now the guard reads only the first goal: the scorer's MO implied must rise > 0.03
        if gl and not first_goal_ok(book,gl[0]): C['guard: tape did not move at the first af goal (bad map)']+=1; continue
        C['games kept']+=1
        for j,gz in enumerate(gl):
            tot=j+1
            if tot>4: break
            h=sum(1 for z in gl[:j+1] if z[2]=='h'); a=tot-h; cs=cur_sel(h,a); M=book.get(('MO',cs))
            if M is None: continue
            nxt=gl[j+1][1] if j+1<len(gl) else 999
            ref=gz[0]-1; mr=M[:max(ref,0)+1]; mr=mr[~np.isnan(mr)] if ref>=0 else np.array([])
            if len(mr)==0: C['no pre-goal print']+=1; continue
            ent=None
            for t in range(gz[1]+3,min(gz[1]+6,90)+1):
                # FIX (first run, 8 Nov): 't>=nxt: break' dropped entries in the minute of the next goal, where the print may be pre-goal and a
                # trader would have been on; now only a goal two or more minutes earlier is known and stops the entry
                if nxt<=t-2: break
                m=M[t]
                if np.isnan(m) or m>50 or m<=1.01: continue
                if m!=mr[-1] and m_dir_ok(h,a,gz[2],m,mr[-1]): ent=t; break
            if ent is None: C['no fresh print in goal+3..+6']+=1; continue
            amb=abs(nxt-ent)<=1
            if amb: C['next goal within 1 min of entry: worst print t-3..t+2']+=1
            k='NOU'
            if tot in OU:
                U=book.get((OU[tot],'UNDER'))
                if U is not None and not np.isnan(U[ent]) and U[ent]>1.01: k=klass(gap(M[ent],U[ent]))
            b=bk_m(worst_b(M,ent) if amb else worse_b(M,ent),cs==win)
            if b is None: C['ladder floor']+=1; continue
            rows.append(dict(eid=g.event_id,season=int(g.season),band=band(gz[1]),state='LEVEL' if h==a else 'LEAD',g=tot,k=k,t=ent,m=M[ent],won=cs==win,BACK_M=b))
    print(f"  {min(i+1000,len(G))}/{len(G)} games | trades {len(rows)} | {time.time()-T0:.0f}s",flush=True)
print("\ncounts:",dict(C),flush=True)
R=pd.DataFrame(rows); R['h']=np.where(R.season==2024,1,2)
out=[]
def add(name,d):
    if len(d)<30: return
    L=line(d.BACK_M.values,d.h.values); L.update(sub=name,games=d.eid.nunique(),won=d.won.mean(),imp=(1/d.m).mean()); out.append(L)
add('ALL',R)
for b in sorted(R.band.unique()):
    add(b,R[R.band==b])
    for s in ('LEVEL','LEAD'): add(b+' '+s,R[(R.band==b)&(R.state==s)])
    for gg in (1,2,3,4): add(b+f' g{gg}',R[(R.band==b)&(R.g==gg)])
    for k in ('V2','V0','C2','C5','FAR','NOU'): add(b+' '+k,R[(R.band==b)&(R.k==k)])
late=R[R.band.isin(['G61-75','G76+'])]; add('G61+',late)
for k in ('V2','V0','C2','C5','FAR','NOU'): add('G61+ '+k,late[late.k==k])
add('G61+ C2+C5',late[late.k.isin(['C2','C5'])]); add('G61+ not C2/C5',late[~late.k.isin(['C2','C5'])])
T=pd.DataFrame(out)[['sub','n','games','per10','t','n1','h1','n2','h2','won','imp','maxwin','PASS']]
print("\nscored line (in-sample, cannot be a find): G61+"); print(T[T['sub']=='G61+'].round(3).to_string(index=False))
print("\nall lines:"); print(T.round(3).to_string(index=False))
print("\nSURVIVORS (in-sample only; a survivor here is a lead for an unseen read, not a pass)"); S=T[T.PASS]
print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
