#!/bin/bash
set -o pipefail
# 480 (Finder 2026-11-04, queue item 25): NAMED TRADERS, one exact version and one relaxed version each, bf_hist_price x af_fixtures/af_events, seasons 2024 v 2025.
# The published texts are not on this box. Every rule below is the queue's wording, and each place the wording leaves a choice is stated as an assumption.
# (a) Psychoff LTD. Lay the draw at the first print in minutes 0..2 at 0-0, draw 3.5-4.5, both teams >= 1.5 GPG over their last 10 finished af_fixtures games. Exits: first goal +2 or +5, or the first print at/after 60', or the first print with draw < 2.5, whichever is first.
#     ASSUMPTION: GPG = goals SCORED per game by that team. Relaxed: draw 3.2-4.8, GPG >= 1.2, at least 5 prior games.
# (b) Webb HT scalp. HT 0-0, back the favourite at the first print at 46-48' when that print is 1.8-2.6, exit first print at/after entry +10. ASSUMPTION: favourite = shorter of HOME/AWAY at the first print in minutes 0..2; the 1.8-2.6 band applies to the HT price. Relaxed: 1.6-3.0.
# (c) Howe second-half goals. HT 0-0, back Over 2.5 at the first print at 46-48' when pre-match Over 2.5 <= 1.75, to settle; extra splits by favourite status and league (item 4b already tested the base). Relaxed: <= 1.90.
# (d) Hargraves lay the 0-0 at 60'. No Over 0.5 on the tape. PROXY: back Over 1.5 at the first print at 60-62' at 0-0 known from goals before the print. It needs two goals, not one, so it is NOT the published trade. Exits: settle, first goal +2, first goal +5. Relaxed: from 55'.
# (e) Berry pre-off: audit is item 0c, not here.
# ENGINE: fill at the worse of the decision print and the next print within 2 min, one tick adverse on the exact ladder. No exit print to 95' = settled at the RESULT, never dropped. 2% commission, £10 risk. Goal strictly before the decision print skips; same-minute goal stays. Games more than 5 min before or 20 min after the af kick-off on their first MO print are dropped blind to the result (job 472).
# Goal-minute exits report +2 and +5 because of the clock leak job 471 found: a pass at +2 must hold at +5. Results print only; no table is written, because runner/runner.sh also runs this file.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def dn(p): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-1,0)])
@lru_cache(maxsize=None)
def up(p): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+1,len(LADA)-1)])
def pnl(side,p,q,won):
    if side=='B':
        a=dn(p)
        if a<=1.01: return None
        r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    else:
        a=up(p); s=10/(a-1)
        r=(s if not won else -10.0) if q is None else s*(1-a/dn(q))
    return r*0.98 if r>0 else r
def rp(arr,a,b):
    for mm in range(max(0,a),min(b,95)+1):
        if not np.isnan(arr[mm]): return mm
    return None
def fill(arr,d,side):
    n=rp(arr,d+1,d+2)
    return arr[d] if n is None else (min(arr[d],arr[n]) if side=='B' else max(arr[d],arr[n]))
def ltd_exit(arr,d,first_goal,k,stop_min=60,stop_px=2.5):
    """Exit minute of the lay-the-draw: earliest print at/after goal+k, at/after stop_min, or the first print after entry under stop_px. None = no print, settle at result."""
    cands=[]
    if first_goal is not None:
        m=rp(arr,first_goal+k,95)
        if m is not None: cands.append(m)
    m=rp(arr,max(stop_min,d+1),95)
    if m is not None: cands.append(m)
    for mm in range(d+1,96):
        if not np.isnan(arr[mm]) and arr[mm]<stop_px: cands.append(mm); break
    return min(cands) if cands else None
def gpg_table(F):
    """Rolling goals scored per game over a team's previous finished games, strictly before kickoff."""
    rows=[]
    for r in F.itertuples():
        rows.append((r.home,r.kickoff,r.fixture_id,int(r.hg))); rows.append((r.away,r.kickoff,r.fixture_id,int(r.ag)))
    D=pd.DataFrame(rows,columns=['team','ko','fx','gf']).sort_values(['team','ko','fx'])
    out={}
    for team,g in D.groupby('team',sort=False):
        hist=[]
        for x in g.itertuples():
            if hist: out[(x.fx,team)]=(sum(hist[-10:])/len(hist[-10:]),len(hist[-10:]))
            hist.append(x.gf)
    return out
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and dn(4.0)==3.95 and up(4.0)==4.1
assert abs(pnl('L',4.0,3.0,False)-(10/3.1)*(1-4.1/2.98)) <1e-9   # lay fills 4.1, stake 10/3.1, exit 3.0 fills 2.98: a loss, no commission
assert abs(pnl('L',4.0,6.0,False)-(10/3.1)*(1-4.1/5.9)*0.98)<1e-9 # draw drifts: profit less 2%
assert pnl('L',4.0,None,True)==-10.0 and abs(pnl('L',4.0,None,False)-10/3.1*0.98)<1e-9
assert abs(pnl('B',2.0,1.5,False)-10*(1.99/1.51-1)*0.98)<1e-9 and abs(pnl('B',2.0,3.0,False)-10*(1.99/3.05-1))<1e-9
_a=np.full(96,np.nan); _a[1]=4.0; _a[20]=5.0; _a[30]=2.4; _a[60]=3.0; _a[70]=3.0
assert ltd_exit(_a,1,10,2)==20        # goal at 10: first print at/after 12 is 20
assert ltd_exit(_a,1,None,2)==30      # no goal: price under 2.5 at 30 comes before the 60' stop
_b=np.full(96,np.nan); _b[1]=4.0; _b[60]=3.0
assert ltd_exit(_b,1,None,2)==60      # time stop
_c=np.full(96,np.nan); _c[1]=4.0
assert ltd_exit(_c,1,None,2) is None  # no later print: result
_F=pd.DataFrame([dict(home='A',away='B',kickoff=pd.Timestamp('2025-01-01'),fixture_id=1,hg=2,ag=0),dict(home='A',away='C',kickoff=pd.Timestamp('2025-01-08'),fixture_id=2,hg=4,ag=1),dict(home='B',away='A',kickoff=pd.Timestamp('2025-01-15'),fixture_id=3,hg=1,ag=1)])
_G=gpg_table(_F); assert (1,'A') not in _G and _G[(2,'A')]==(2.0,1) and _G[(3,'A')]==(3.0,2) and _G[(3,'B')]==(0.0,1)   # strictly prior games only
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.league_id,f.league,f.kickoff,f.home,f.away,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
F=pd.read_sql("SELECT fixture_id,home,away,kickoff,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL",con)
GPG=gpg_table(F); print("games",len(G),"| af_fixtures for GPG",len(F),flush=True)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append(int(r.minute))
for k in goals: goals[k].sort()
T=[]; SK=defaultdict(int); t0=time.time()
def add(rule,ver,ex,g,x,split=None):
    if x is None: return
    T.append((rule,ver,ex,g.event_id,int(g.season),f"{g.league_id} {g.league}",split,x))
def known_before(gl,m): return any(x<m for x in gl)
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]; ids=list(sub.event_id)
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25') AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    P=P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel','minute'])
    fm=P[(P.mkt=='MO')&(P.minute<=2)].groupby('event_id').m.min().to_dict()
    px={}
    for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(96,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b: SK['no prints']+=1; continue
        if g.event_id in fm:
            lag=(pd.Timestamp(fm[g.event_id])-pd.Timestamp(g.kickoff)).total_seconds()/60
            if lag<-5 or lag>20: SK['off the kick-off']+=1; continue
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag); hh,ha=int(g.ht_hg),int(g.ht_ag); H=b.get(('MO','HOME')); A=b.get(('MO','AWAY')); D=b.get(('MO','DRAW'))
        def first(arr):
            if arr is None: return None
            m=rp(arr,0,2); return None if m is None else arr[m]
        hp,ap=first(H),first(A)
        fs=None if hp is None or ap is None or hp==ap else ('H' if hp<ap else 'A')
        # (a) LTD
        if D is not None:
            d=rp(D,0,2)
            if d is not None and not known_before(gl,d):
                gh=GPG.get((g.fixture_id,g.home)); ga=GPG.get((g.fixture_id,g.away))
                if gh and ga:
                    draw=hg==ag; first_g=next((x for x in gl if x>=d),None)
                    px0=D[d]
                    for ver,lo,hi,mn,cnt in (('exact',3.5,4.5,1.5,10),('relaxed',3.2,4.8,1.2,5)):
                        if lo<=px0<=hi and gh[0]>=mn and ga[0]>=mn and gh[1]>=cnt and ga[1]>=cnt:
                            p=fill(D,d,'L')
                            for k in (2,5):
                                e=ltd_exit(D,d,first_g,k)
                                q=None if e is None else D[e]
                                add('a Psychoff LTD',ver,f'G{k}/60/<2.5',g,pnl('L',p,q,draw))
                            add('a Psychoff LTD',ver,'settle',g,pnl('L',p,None,draw))
        # (b) Webb
        if hh==0 and ha==0 and fs:
            arr=H if fs=='H' else A
            d=rp(arr,46,48)
            if d is not None and not known_before([x for x in gl if x>45],d):
                won=(hg>ag) if fs=='H' else (ag>hg)
                for ver,lo,hi in (('exact',1.8,2.6),('relaxed',1.6,3.0)):
                    if lo<=arr[d]<=hi:
                        e=rp(arr,d+10,95)
                        add('b Webb HT scalp',ver,'+10',g,pnl('B',fill(arr,d,'B'),None if e is None else arr[e],won))
        # (c) Howe
        O=b.get(('OU25','OVER'))
        if O is not None and hh==0 and ha==0:
            m0=rp(O,0,2); d=rp(O,46,48)
            if m0 is not None and d is not None and not known_before([x for x in gl if x>45],d):
                over=hg+ag>2.5; fstat='HF' if (hp is not None and hp<=1.8 and fs=='H') else 'AF' if (ap is not None and ap<=1.8 and fs=='A') else 'NF'
                for ver,cap in (('exact',1.75),('relaxed',1.90)):
                    if O[m0]<=cap:
                        x=pnl('B',fill(O,d,'B'),None,over)
                        add('c Howe 2H goals',ver,'settle',g,x)
                        add('c Howe 2H goals',ver,'settle',g,x,split='fav '+fstat)
        # (d) Hargraves proxy
        O15=b.get(('OU15','OVER'))
        if O15 is not None:
            for ver,start in (('exact-proxy',60),('relaxed-proxy',55)):
                d=rp(O15,start,start+2)
                if d is None or known_before(gl,d): continue
                won=hg+ag>1.5; p=fill(O15,d,'B'); nx=next((x for x in gl if x>=d),None)
                add('d Hargraves O1.5 proxy',ver,'settle',g,pnl('B',p,None,won))
                for k in (2,5):
                    e=None if nx is None else rp(O15,nx+k,95)
                    add('d Hargraves O1.5 proxy',ver,f'G{k}',g,pnl('B',p,None if e is None else O15[e],won))
    print(f"  {min(i+1500,len(G))}/{len(G)} | trades {len(T)} | {int(time.time()-t0)}s",flush=True)
print("skips:",dict(SK),flush=True)
R=pd.DataFrame(T,columns=['rule','ver','exit','ev','season','league','split','x'])
def tstat(v): return v.mean()/(v.std(ddof=1)/np.sqrt(len(v))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
def summ(d,**k):
    a=d[d.season==2024].x; b=d[d.season==2025].x; n=len(d); t=tstat(d.x)
    return dict(**k,n=n,games=d.ev.nunique(),per10=d.x.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,PASS=n>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and a.mean()>0 and b.mean()>0 and d.x.mean()>=0.15)
base=R[R.split.isna()]
S=pd.DataFrame([summ(d,rule=r,ver=v,exit=e) for (r,v,e),d in base.groupby(['rule','ver','exit'])])
assert not base.duplicated(['rule','ver','exit','ev']).any()
print("\n== RULES\n",S.round(3).to_string(index=False))
Sp=pd.DataFrame([summ(d,rule=r,ver=v,split=s) for (r,v,s),d in R[R.split.notna()].groupby(['rule','ver','split'])])
print("\n== HOWE by favourite status\n",Sp.round(3).to_string(index=False))
Lg=pd.DataFrame([summ(d,rule=r,ver=v,exit=e,league=l) for (r,v,e,l),d in base.groupby(['rule','ver','exit','league']) if len(d)>=100])
print(f"\n== league splits with n>=100: {len(Lg)}; n>=300: {int((Lg.n>=300).sum())}; top 10 by t\n",Lg.sort_values('t',ascending=False).head(10).round(3).to_string(index=False))
allp=pd.concat([S,Sp,Lg],ignore_index=True); W=allp[allp.PASS==True]
print(f"\n== SURVIVORS: {len(W)} of {len(allp)} lines")
print(W.round(3).to_string(index=False) if len(W) else "none")
PY
