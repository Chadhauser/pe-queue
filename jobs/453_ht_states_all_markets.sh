#!/bin/bash
set -o pipefail
# 453 (Finder 2026-11-02, queue item 5): HALF-TIME STATES x EVERY MARKET on bf_hist_price (MO, OU15, OU25, OU35, BTTS; FH excluded).
# HT score from af_fixtures (0-0,1-0,0-1,1-1,2-0,0-2,2-1,1-2, 3+ total). Entry: decision at the first real print at match minute 46-48
# for that selection, FILL at the worse of that print and the next real print within 2 minutes, one tick adverse. Back and lay.
# Exits: SETTLE; NEXTGOAL (first real print at/after next-goal+2); T70 (first real print at/after 70'). If an exit has no print because the market
# SETTLED (OU line passed, BTTS both scored) or because the price went to an extreme and stopped trading, the position is held to the
# first real print at ANY later minute, and if none to 95' it is settled at the RESULT. Nothing is dropped. (First draft skipped
# 'no print, not settled' exits like 315 does: that dropped exactly the losers — e.g. back O3.5 at 0-0 showed a fake +£2.95/£10.) A selection already decided at HT is not traded. A second-half goal at/before the decision minute
# skips the game for that selection (counted). Prints at 1.01 are kept (ltp>=1.01). Splits: pre-match favourite band, league.
# £10 risk, 2% commission. Halves = season 2024 vs 2025. One entry per game per cell (no within-cell correlation; the SAME game appears
# in many cells, so cells are not independent of each other). Output prints SURVIVORS only after the summary tables.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,won):
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        if q is None: r=10*(p-1) if won else -10.0
        else: q=q+tick(q); r=10*(p/q-1)
    else:
        p=p+tick(p); s=10/(p-1)
        if q is None: r=s if not won else -10.0
        else: q=max(1.01,q-tick(q)); r=s*(1-p/q)
    return r*0.98 if r>0 else r
assert abs(pnl('B',2.0,None,True)-9.604)<1e-9 and abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9 and abs(pnl('L',6.0,3.0,False)-(10/5.2)*(1-6.2/2.95))<1e-9
print("P&L unit checks: OK",flush=True)
MK={'MO':('HOME','DRAW','AWAY'),'OU15':('OVER','UNDER'),'OU25':('OVER','UNDER'),'OU35':('OVER','UNDER'),'BTTS':('YES','NO')}
def result(mkt,sel,hg,ag):
    if mkt=='MO': return (hg>ag) if sel=='HOME' else (hg<ag) if sel=='AWAY' else hg==ag
    if mkt=='BTTS': return (hg>0 and ag>0)==(sel=='YES')
    line=float(mkt[2]+'.'+mkt[3]); return (hg+ag>line)==(sel=='OVER')
def decided(mkt,sel,h,a):
    if mkt=='MO': return False
    if mkt=='BTTS': return h>0 and a>0
    return h+a>float(mkt[2]+'.'+mkt[3])
assert result('OU25','OVER',2,1) and not result('BTTS','YES',2,0) and decided('OU15','UNDER',1,1) and not decided('OU35','OVER',2,1)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag, f.ht_hg, f.ht_ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
def st(h,a): return '3+' if h+a>=3 else f"{h}-{a}"
G['state']=[st(int(h),int(a)) for h,a in zip(G.ht_hg,G.ht_ag)]
print("games:",len(G),"| HT states:",G.state.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, is_home, detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal'
 AND detail IN ('Normal Goal','Penalty','Own Goal')""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples():
    side=('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')
    goals[r.fixture_id].append((int(r.minute),side))
for k in goals: goals[k].sort()
def score(gl,m): return (sum(1 for g,s in gl if g<=m and s=='h'), sum(1 for g,s in gl if g<=m and s=='a'))
def rp(arr,a,b):
    for mm in range(max(0,a),min(b,96)+1):
        if not np.isnan(arr[mm]): return mm
    return None
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
cells=defaultdict(lambda:[0,0.0,0.0,0,0.0,0,0.0]); SK=defaultdict(int); t0=time.time(); ntr=0
def put(key,season,r):
    c=cells[key]; c[0]+=1; c[1]+=r; c[2]+=r*r
    if season==2024: c[3]+=1; c[4]+=r
    else: c[5]+=1; c[6]+=r
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','OU35','BTTS') AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    px={}
    for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b: continue
        H=b.get(('MO','HOME')); A=b.get(('MO','AWAY'))
        fb='n/a' if H is None or A is None or np.isnan(H[0]) or np.isnan(A[0]) else favband(min(H[0],A[0]))
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag); hh,ha=int(g.ht_hg),int(g.ht_ag)
        g2=[m for m,s in gl if m>45]
        for (mkt,sel),arr in b.items():
            if sel not in MK.get(mkt,()) or decided(mkt,sel,hh,ha): continue
            d=rp(arr,46,48)
            if d is None: SK['no 46-48 print']+=1; continue
            if g2 and g2[0]<=d: SK['2H goal before decision']+=1; continue
            n1=rp(arr,d+1,d+2); won=result(mkt,sel,hg,ag)
            nxt=next((m for m in g2 if m>d),None)
            for side in ('B','L'):
                p=arr[d] if n1 is None else (min(arr[d],arr[n1]) if side=='B' else max(arr[d],arr[n1]))
                if p>50: continue
                for ex in ('SETTLE','NEXTGOAL','T70'):
                    q=None
                    if ex=='NEXTGOAL':
                        if nxt is None or nxt+2>95: q=None
                        else:
                            e=rp(arr,nxt+2,95)
                            if e is not None: q=arr[e]
                            else: q=None; SK[f'{mkt} NEXTGOAL no print to 95 -> settled at result']+=1
                    elif ex=='T70':
                        e=rp(arr,70,95)
                        if e is not None: q=arr[e]
                        else: q=None; SK[f'{mkt} T70 no print to 95 -> settled at result']+=1
                    r=pnl(side,p,q,won)
                    if r is None: continue
                    ntr+=1; s=int(g.season)
                    put((g.state,mkt,sel,side,ex,'*','*'),s,r); put((g.state,mkt,sel,side,ex,fb,'*'),s,r); put((g.state,mkt,sel,side,ex,'*',g.league),s,r)
    print(f"  {min(i+1500,len(G))}/{len(G)} games | trades {ntr} | cells {len(cells)} | {int(time.time()-t0)}s",flush=True)
print("skips (counted):",dict(SK))
R=pd.DataFrame([k+tuple(v) for k,v in cells.items()],columns=['state','mkt','sel','side','exit','fav','league','n','s','ss','n1','s1','n2','s2'])
R['per10']=R.s/R.n; R['sd']=np.sqrt(np.maximum(R.ss/R.n-R.per10**2,1e-9)); R['t']=R.per10/(R.sd/np.sqrt(R.n))
R['h1']=R.s1/R.n1.replace(0,np.nan); R['h2']=R.s2/R.n2.replace(0,np.nan)
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)
cols=['state','mkt','sel','side','exit','fav','league','n','per10','t','n1','h1','n2','h2','PASS']
T=R[R.n>=300]
print(f"\n==== HT STATES x MARKETS: {len(R)} cells, {len(T)} with n>=300 ====")
print("\n== top 15 by t (n>=300)"); print(T.sort_values('t',ascending=False).head(15)[cols].round(3).to_string(index=False))
print("\n== top 10 by t, base level only (no fav/league split)"); print(T[(T.fav=='*')&(T.league=='*')].sort_values('t',ascending=False).head(10)[cols].round(3).to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} (of {len(T)} cells at n>=300)"); print(S.head(40)[cols].round(3).to_string(index=False) if len(S) else "none")
PY
