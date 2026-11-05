#!/bin/bash
set -o pipefail
# 499_goal_timing (Finder 2026-11-05, queue items 130, 131, Finder's own, source a): does the way goals arrived, a burst or just before the break, leave a price error? Rules written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_fixtures, af_events, af_price_map, bf_hist_price (MO, OU25, OU35). Local DB, read-only. Cups 2, 3 excluded. A game whose goal events do not add up to the score is excluded, counted.
# ENTRY first real print in the window, never a forward fill. A goal strictly before the print minute and after the signal changes the known state: dropped, counted. A goal AT the print minute stays at that print: dropping it would select on the future (item 14's look-ahead lesson) and the print may be after the goal, which only costs the test.
# TAPE MINUTE first half 0..46, second half about the match clock from 47 (checked on one event: tape 46 at KO+46 min, tape 47 at KO+66), so 131 also requires the print at least 60 min after kick-off.
# ALL LTP, one tick adverse, 2%, £10 risk, hold to FT, so a passed market settles at the result and a pass is an upper bound. Halves by season. Several entries per game possible on 130: t by game also required.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_000_000_000,3_000_000_000))  # this job only: fail with MemoryError rather than push the box's OOM killer at a daemon
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def band(g): return 'B15-44' if 15<=g<=44 else 'B46-69' if 46<=g<=69 else 'B70-85' if 70<=g<=85 else None
def ou_line(tot): return {1:('OU15',1.5),2:('OU25',2.5),3:('OU35',3.5)}.get(tot)
def clock(mn,ex):
    """(minute, extra) to an order within a half: 45+2 sorts before 46, and 90+3 after 90."""
    return mn+(ex or 0)/100.0
def classify(goals,k):
    """goals: list of (minute, is_home) in order; k>=1 index of the goal. CL = at most 5 min after the previous one, CTRL = at least 20, else None. Same half only, so a goal either side of the break is neither."""
    g,h=goals[k]; pg,ph=goals[k-1]
    d=g-pg
    if d>=20: return 'CTRL'
    if (pg<=45)!=(g<=45): return None
    if d<=5: return 'CL_SAME' if h==ph else 'CL_SWAP'
    return None
def first_in(mm,pp,lo,hi):
    """First print with minute in [lo,hi] on arrays sorted by minute. None if there is none: no fill."""
    i=int(np.searchsorted(mm,lo,side='left'))
    if i>=len(mm) or mm[i]>hi: return None
    return i
def known_goal(goals,k,pm):
    """A goal after index k, in order, strictly before print minute pm: the state has changed and is known. Includes a second goal in goal k's own minute."""
    return any(g<pm for g,_ in goals[k+1:])
def side_fix(rows,hg):
    """rows (minute, is_home, own). Returns (minute, scoring side is home), or None. af credits an own goal to either side depending on the row, so take it as given if the home count matches the score, else flip own goals, else None."""
    raw=[(m,h) for m,h,o in rows]
    if None in [h for _,h in raw]: return None
    if sum(1 for _,h in raw if h)==hg: return raw
    fl=[(m,(not h) if o else h) for m,h,o in rows]
    return fl if sum(1 for _,h in fl if h)==hg else None
def ht_state(hh,ha,fav):
    """Half-time score and pre-match favourite 'H' or 'A': FAV1, DOG1, LEVEL or None."""
    if hh==ha: return 'LEVEL' if hh>=1 else None
    if abs(hh-ha)!=1: return None
    lead='H' if hh>ha else 'A'
    return 'FAV1' if lead==fav else 'DOG1'
# known answers, worked by hand
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.02,True) is None
assert band(14) is None and band(15)=='B15-44' and band(44)=='B15-44' and band(45) is None and band(46)=='B46-69' and band(70)=='B70-85' and band(85)=='B70-85' and band(86) is None
assert ou_line(2)==('OU25',2.5) and ou_line(3)==('OU35',3.5) and ou_line(1)==('OU15',1.5) and ou_line(0) is None and ou_line(4) is None
_g=[(10,True),(13,True),(40,False),(44,False),(46,True),(80,True)]
assert classify(_g,1)=='CL_SAME' and classify(_g,2)=='CTRL' and classify(_g,3)=='CL_SAME' and classify(_g,4) is None and classify(_g,5)=='CTRL'
assert classify([(30,True),(70,False)],1)=='CTRL' and classify([(44,True),(46,True)],1) is None   # control may cross the break, as the queue rule says; a cluster may not
assert classify([(10,True),(15,False)],1)=='CL_SWAP' and classify([(10,True),(16,False)],1) is None and classify([(10,True),(30,False)],1)=='CTRL' and classify([(10,True),(29,False)],1) is None
_m=np.array([3,5,9,12]); _p=np.array([2.,3.,4.,5.])
assert first_in(_m,_p,5,9)==1 and first_in(_m,_p,6,9)==2 and first_in(_m,_p,10,11) is None and first_in(_m,_p,13,20) is None
assert known_goal([(10,True),(14,True)],0,15) and not known_goal([(10,True),(15,True)],0,15) and not known_goal([(10,True)],0,15) and known_goal([(10,True),(10,False)],0,15) and not known_goal([(5,True),(10,False)],1,15)
assert side_fix([(5,True,False),(9,False,True)],1)==[(5,True),(9,False)] and side_fix([(5,True,False),(9,False,True)],2)==[(5,True),(9,True)] and side_fix([(5,True,False),(9,False,False)],2) is None and side_fix([(5,None,False)],0) is None
assert ht_state(1,0,'H')=='FAV1' and ht_state(1,0,'A')=='DOG1' and ht_state(0,1,'A')=='FAV1' and ht_state(1,1,'H')=='LEVEL' and ht_state(0,0,'H') is None and ht_state(2,0,'H') is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.season,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league_id NOT IN (2,3)""",con)
G=G.drop_duplicates('event_id').reset_index(drop=True); print(f"mapped games {len(G)} {G.season.value_counts().to_dict()}",flush=True)
E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,coalesce(extra,0) ex,is_home,detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
print(f"goal rows {len(E)}; is_home null {int(E.is_home.isna().sum())}",flush=True)
E['o']=[clock(a,b) for a,b in zip(E.mn,E.ex)]; E=E.sort_values(['fixture_id','o'])
RAW=defaultdict(list); GL={}
for a,b,c_,d_ in zip(E.fixture_id,E.mn,E.is_home,E.detail): RAW[int(a)].append((int(b),None if c_ is None or c_!=c_ else bool(c_),d_=='Own Goal'))
SK=Counter(); rows=[]; ctrl=[]; K=[]
T=[]
for r in G.itertuples():
    g=RAW.get(int(r.fixture_id),[])
    if len(g)!=r.hg+r.ag: SK['events differ from score']+=1; continue
    f=side_fix(g,r.hg)
    if f is None: SK['sides do not add up, flipped or not']+=1; continue
    GL[int(r.fixture_id)]=f; T.append(r)
print(f"games kept {len(T)} of {len(G)}; {dict(SK)}",flush=True); SK=Counter()
def add(item,lab,sel,side,fx,season,px,won):
    v=bk(px,won) if side=='BACK' else ly(px,won)
    if v is None: SK['back at 1.01, no bet']+=1; return
    rows.append((item,lab,sel,side,fx,1 if season==2024 else 2,float(px),bool(won),float(v)))
# first run was SIGKILLed loading all prices at once on a 7 GB box: one chunk of games in memory at a time, trades only kept
NROW=0
for c0 in range(0,len(T),300):
    TC=T[c0:c0+300]
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float4 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','OU35') AND sel IN ('HOME','DRAW','AWAY','OVER','UNDER') AND minute>=0 AND minute<=99 AND ltp>=1.01 AND ltp<1000",con,params=([r.event_id for r in TC],))
    P['ltp']=P.ltp.astype(float).round(2); P['m']=pd.to_datetime(P.m,utc=True).dt.tz_localize(None); P=P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel','minute']); NROW+=len(P)
    Q={k:(v.minute.values,v.ltp.values,v.m.values) for k,v in P.groupby(['event_id','mkt','sel'])}; del P
    for r in TC:
        g=GL[int(r.fixture_id)]; fx=int(r.fixture_id); tot=r.hg+r.ag; res='H' if r.hg>r.ag else 'A' if r.ag>r.hg else 'D'
        ko=pd.to_datetime(r.kickoff,utc=True).tz_localize(None)
        # ---- 130
        for k in range(1,len(g)):
            c=classify(g,k); b=band(g[k][0])
            if c is None or b is None: continue
            gm=g[k][0]; hs=sum(1 for x,h in g[:k+1] if h); as_=k+1-hs; lab=f'{c} {b}'
            cands=[]
            ln=ou_line(k+1)
            if ln:
                cands+=[(ln[0],'OVER','OVER',tot>ln[1]),(ln[0],'UNDER','UNDER',tot<ln[1])]
            cands.append(('MO','DRAW','DRAW',res=='D'))
            if hs>as_: cands+=[('MO','HOME','LEAD',res=='H'),('MO','AWAY','TRAIL',res=='A')]
            elif as_>hs: cands+=[('MO','AWAY','LEAD',res=='A'),('MO','HOME','TRAIL',res=='H')]
            for mk,sel,name,won in cands:
                z=Q.get((r.event_id,mk,sel))
                if z is None: SK['130 no tape']+=1; continue
                i=first_in(z[0],z[1],gm+5,gm+9)
                if i is None: SK['130 no print']+=1; continue
                pm=int(z[0][i])
                if known_goal(g,k,pm): SK['130 later goal before print']+=1; continue
                for side in ('BACK','LAY'): add(130,lab,name,side,fx,r.season,z[1][i],won)
        # ---- 131
        if r.ht_hg is None or r.ht_ag is None or r.ht_hg!=r.ht_hg: SK['131 no ht score']+=1; continue
        fh=[(x,h) for x,h in g if x<=45]
        if len(fh)!=r.ht_hg+r.ht_ag or sum(1 for _,h in fh if h)!=r.ht_hg: SK['131 first-half events differ from ht score']+=1; continue
        if not fh: continue
        zh=Q.get((r.event_id,'MO','HOME')); za=Q.get((r.event_id,'MO','AWAY'))
        if zh is None or za is None: SK['131 no MO']+=1; continue
        ih=first_in(zh[0],zh[1],0,2); ia=first_in(za[0],za[1],0,2)
        if ih is None or ia is None: SK['131 no first print']+=1; continue
        if zh[1][ih]==za[1][ia]: SK['131 no favourite']+=1; continue
        if any(x<max(zh[0][ih],za[0][ia]) for x,_ in g): SK['131 goal before first print']+=1; continue
        fav='H' if zh[1][ih]<za[1][ia] else 'A'; st=ht_state(int(r.ht_hg),int(r.ht_ag),fav)
        if st is None: continue
        tm='LATE' if fh[-1][0]>=40 else 'EARLY'; lab=f'{tm} {st}'; n=len(fh); ln=ou_line(n)
        cands=[('MO','DRAW','DRAW',res=='D')]
        if st=='LEVEL':
            d='A' if fav=='H' else 'H'
            cands+=[('MO','HOME' if fav=='H' else 'AWAY','FAV',res==fav),('MO','HOME' if d=='H' else 'AWAY','DOG',res==d)]
        else:
            lead='H' if r.ht_hg>r.ht_ag else 'A'; tr='A' if lead=='H' else 'H'
            cands+=[('MO','HOME' if lead=='H' else 'AWAY','LEAD',res==lead),('MO','HOME' if tr=='H' else 'AWAY','TRAIL',res==tr)]
        if ln: cands+=[(ln[0],'OVER','OVER',tot>ln[1]),(ln[0],'UNDER','UNDER',tot<ln[1])]
        for mk,sel,name,won in cands:
            z=Q.get((r.event_id,mk,sel))
            if z is None: SK['131 no tape']+=1; continue
            i=first_in(z[0],z[1],47,51)
            if i is None: SK['131 no print']+=1; continue
            el=(pd.Timestamp(z[2][i])-ko).total_seconds()/60
            if el<60: SK['131 print under 60 min after KO']+=1; continue
            pm=int(z[0][i])
            if any(45<x<pm for x,_ in g): SK['131 second-half goal before print']+=1; continue
            for side in ('BACK','LAY'): add(131,lab,name,side,fx,r.season,z[1][i],won)
    if c0%3000==0: print(f"  games {c0} of {len(T)}, price rows {NROW:,}, trades {len(rows):,}, {time.time()-T0:.0f}s",flush=True)
con.close(); print(f"price rows {NROW:,}, {time.time()-T0:.0f}s",flush=True)
print("counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns=['item','a','sel','side','fx','h','x','won','v'])
def tb(k,x):
    l=line(x.v.values,x.h.values); tg=tstat(x.groupby('fx').v.sum().values)
    return dict(item=k[0],a=k[1],sel=k[2],side=k[3],n=l['n'],games=x.fx.nunique(),per10=l['per10'],t=l['t'],t_game=tg,n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),PASS=l['PASS'] and tg>=3.5)
O=pd.DataFrame([tb(k,x) for k,x in R.groupby(['item','a','sel','side'])])
isctl=O.a.str.startswith('CTRL')|O.a.str.startswith('EARLY')
for it,x in O[~isctl].groupby('item'):
    big=x[x.n>=300]
    print(f"\n== item {it}: lines {len(x)}, n>=300 {len(big)}, positive there {int((big.per10>0).sum())}, pass {int(x.PASS.sum())}; by chance about {len(x)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=100"); print(x[x.n>=100].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
    print("worst 3"); print(x[x.n>=100].sort_values('t').head(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== long-price check: lines with |per10| >= 2, n>=100, biggest single price and P&L, and the mean without the 3 biggest wins")
for k,x in R.groupby(['item','a','sel','side']):
    if len(x)>=100 and abs(x.v.mean())>=2 and not k[1].startswith(('CTRL','EARLY')):
        print(' ',*k,f"n {len(x)} per10 {x.v.mean():.3f} max price {x.x.max():.1f} max win {x.v.max():.1f} trimmed {np.sort(x.v.values)[:-3].mean():.3f}")
print("\n== controls, not counted as lines: top 8 by t"); print(O[isctl].sort_values('t',ascending=False).head(8).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== signal v control, per10, same selection and band")
piv=O.assign(group=O.a.str.split().str[0],b=O.a.str.split().str[1]).pivot_table(index=['item','b','sel','side'],columns='group',values='per10').round(3); print(piv.to_string())
S=O[O.PASS&~isctl]; print(f"\n== SURVIVORS: {len(S)} of {int((~isctl).sum())} (bar: n>=300, n>=150 per half, both halves > 0, t and t by game >= 3.5, mean >= +0.15, LTP upper bound)\n",S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
