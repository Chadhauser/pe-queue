#!/bin/bash
set -o pipefail
# 499_cricket_touch_preoff (Finder 2026-11-07, queue item 395, Finder's own, source a; entries from jobs/499_cricket_outsider.sh, table cricket_fav_tape first read here): item 271's cricket outsider lay at the real touch. Rule pushed in the queue before any price. Read only, no tables written.
# LINE two-runner cricket, outsider at 3-20 on its last pre-off tape row T-20 to T-2, lay at the tape's real lay_px, worse of it and the next row within 120 s, one tick adverse, 2%, GBP 10 liability, one per game. RESULT official where matched (cricket_matches stops 27 Apr 2026, so expected none), else item 268's rule, else last-print odds. Spread read first: a median over 5 ticks means the lean is gone at any size.
# The tape's catalogue reaches 10 minutes ahead of the start, so pre-off rows are about T-10 on, not T-60 as on item 271. Halves by date, standard bar. 14 days of tape, so n will be far under the bar: this is a read of the cost, not a verdict on the lean.
# FIX 2026-11-07, the one fix: replay rows dropped. This REST tape replays old book states, total_matched falling under the market's earlier high, 17% of in-play rows; job 497 found the same on ip_tape. A row is kept only if total_matched is at or above 0.999 of the market's high so far. The first run did not do this; its numbers are in the report.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
import lib_cand
from lib_cand import line,step,norm,LD
from lib_official import ly,fill,last_in,secs,checks
lib_cand._checks(); checks()
def ticks(a,b):
    """Ladder steps from price a up to price b."""
    return int(np.searchsorted(LD,round(float(b),2)-1e-9))-int(np.searchsorted(LD,round(float(a),2)-1e-9))
def infer(last,lo_=1.10,hi_=5.0):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
def ev_lay(p,q): return (1-q)*ly(p,False)+q*ly(p,True)
def q_last(lo_,lf): a,b=1/lo_,1/lf; return a/(a+b)
# known answers, worked by hand
assert ticks(2.0,2.02)==1 and ticks(3.0,3.05)==1 and ticks(3.0,3.5)==10 and ticks(1.99,2.02)==2 and ticks(6.0,6.2)==1 and ticks(10,11)==2 and ticks(5,5)==0
assert abs(ly(4.9,False)-10/4.0*.98)<1e-9 and ly(4.9,True)==-10.0   # 4.9 one tick adverse is 5.0: stake 2.5, wins 2.45 after 2%, loses 10
assert abs(ev_lay(4.9,0.2)-(-0.04))<1e-9 and abs(q_last(4,1.25)-0.25/1.05)<1e-9
assert infer({'a':1.05,'b':20})=='a' and infer({'a':1.2,'b':20}) is None and infer({'a':1.05}) is None
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',60)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='300s'")
CM=pd.read_sql("SELECT match_date,team1,team2,winner FROM cricket_matches WHERE match_date>='2026-10-01'",rc)
CTE="WITH t AS (SELECT *,total_matched::float8 tm0,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi FROM cricket_fav_tape), c AS (SELECT * FROM t WHERE hi IS NULL OR tm0 IS NULL OR tm0>=hi*0.999) "
print("replay rows dropped, pre-off and in play:",pd.read_sql("WITH t AS (SELECT inplay,total_matched::float8 tm0,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi FROM cricket_fav_tape) SELECT inplay,count(*) n,sum((tm0<hi*0.999)::int) replay FROM t GROUP BY 1",rc).to_dict('records'),flush=True)
A=pd.read_sql(CTE+"SELECT ts,market_id,event_name ev,competition comp,start_time mt,sel_name sel,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp,total_matched::float8 tm FROM c WHERE NOT inplay AND ts>=start_time-interval '20 minutes' AND ts<=start_time-interval '2 minutes'",rc)
B=pd.read_sql(CTE+"SELECT DISTINCT ON (market_id,sel_name) market_id,sel_name sel,ltp::float8 ltp,ts FROM c WHERE inplay ORDER BY market_id,sel_name,ts DESC",rc)
ALLN=pd.read_sql("SELECT market_id,count(DISTINCT sel_name) nr,bool_or(inplay) ip,min(ts) a,max(ts) z,max(start_time) mt FROM cricket_fav_tape GROUP BY 1",rc)
TEND=pd.read_sql("SELECT max(ts) z FROM cricket_fav_tape",rc).z.iloc[0]; rc.close()
print(f"official rows after 1 Oct 2026 {len(CM)}; pre rows {len(A):,}; markets on tape {len(ALLN)}, two-runner {int((ALLN.nr==2).sum())}, ever in play {int(ALLN.ip.sum())}; tape ends {TEND}; {time.time()-T0:.0f}s",flush=True)
ix=defaultdict(list)
for r in CM.itertuples(): ix[frozenset((norm(r.team1),norm(r.team2)))].append((r.match_date,r.winner))
A['tt']=secs(A.ts); A['off']=secs(A.mt); A=A.sort_values('tt',kind='stable')
L=defaultdict(dict); LT={}
for r in B.itertuples(): L[r.market_id][r.sel]=r.ltp; LT[r.market_id]=max(LT.get(r.market_id,0),pd.Timestamp(r.ts).timestamp())
NR=dict(zip(ALLN.market_id,ALLN.nr)); TE=TEND.timestamp()
C=Counter(); rows=[]; seen=set(); SP=[]
for m,g in A.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id']+=1; continue
    seen.add((ev,o))
    if NR.get(m)!=2: C['not two runners']+=1; continue
    en={}
    for s,y in g.groupby('sel',sort=False):
        ts=y.tt.values; i=last_in(ts,o-1200,o-120)
        if i is not None: en[s]=(float(y.ltp.values[i]),y,i)
    if len(en)!=2: C['both runners not priced']+=1; continue
    f,b=sorted(en,key=lambda z:en[z][0])
    if en[f][0]==en[b][0]: C['level']+=1; continue
    px0,y,i=en[b]
    if not 3.0<=px0<20.0: C['outsider outside 3-20']+=1; continue
    bp,lp=y.bp.values[i],y.lp.values[i]; tm=float(y.tm.values[i]); age=(o-y.tt.values[i])/60
    if lp!=lp: C['no lay on the book, no trade']+=1; continue
    gl=y[y.lp.notna()]; tsl=gl.tt.values; j=np.searchsorted(tsl,y.tt.values[i])
    p=fill(tsl,gl.lp.values,j,'L'); pp=fill(y.tt.values,y.ltp.values,i,'L')
    last=L.get(m,{}); win=infer(last); both=(b in last and f in last)
    if not both and o+43200>TE: C['no in-play print yet and under 12 h old, left out']+=1; continue
    if win is None and o+43200>TE: C['unresolved and under 12 h old, left out']+=1; continue
    h_,_,a_=str(ev).partition(' v '); day=pd.Timestamp(g.mt.iloc[0]).date(); hits=[x for dd,x in ix.get(frozenset((norm(h_),norm(a_))),[]) if abs((dd-day).days)<=1]
    offi=None
    if len(hits)==1 and hits[0] is not None:
        tw=[s for s in en if norm(s)==norm(hits[0])]
        if len(tw)==1: offi=tw[0]; C['official scored']+=1
    w_=offi if offi else win
    q_fair=(1/(0.5*(bp+lp)) if bp==bp else 1/px0)
    if w_ is not None:
        v=ly(p,w_==b); vp=ly(pp,w_==b); q=1.0 if w_==b else 0.0
    elif both:
        q=q_last(last[b],last[f]); v=ev_lay(p,q); vp=ev_lay(pp,q); C['unresolved at last-print odds']+=1
    else:
        q=1/step(p,1); v=ev_lay(p,q); vp=ev_lay(pp,1/step(pp,1)); C['no in-play print, zero edge']+=1
    spread=np.nan if bp!=bp else float(ticks(bp,lp))
    rows.append(dict(m=m,ev=ev,comp=y.comp.values[i],off=o,px=px0,bp=bp,lp=lp,p=p,pp=pp,tm=tm,age=age,spread=spread,above=ticks(px0,lp),res=w_ is not None,won=(w_==b) if w_ is not None else np.nan,v=v,vp=vp,mcost=ev_lay(pp,1/pp)-ev_lay(p,1/pp),sp_pct=(lp/bp-1)*100 if bp==bp else np.nan))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows); assert not R.duplicated(['ev','off']).any(); print("games",len(R),"resolved",int(R.res.sum()),"date range",pd.Timestamp(R.off.min(),unit='s'),pd.Timestamp(R.off.max(),unit='s'),"entry age median min",round(R.age.median(),1),flush=True)
print("\n== SPREAD at entry, ticks between back and lay, the test the rule reads first")
z=R[R.spread.notna()]
print(f"all: median {z.spread.median():.0f} ticks; share <=1 {float((z.spread<=1).mean()):.3f}, <=2 {float((z.spread<=2).mean()):.3f}, <=5 {float((z.spread<=5).mean()):.3f}; spread % median {z.sp_pct.median():.2f}; lay touch above the print, ticks, median {R.above.median():.0f}; verdict if over 5: {'LEAN GONE AT ANY SIZE' if z.spread.median()>5 else 'read on'}")
def tb(x,by):
    return x.groupby(by,observed=True).agg(n=('v','size'),spread_med=('spread','median'),spread_pct=('sp_pct','median'),above_print=('above','median'),model_cost=('mcost','mean'),at_print=('vp','mean'),at_touch=('v','mean'),won=('won',lambda s:s.astype(float).mean()),imp=('px',lambda s:(1/s).mean())).round(3)
print("by price\n",tb(R,pd.cut(R.px,[3,4,6,10,20],right=False)).to_string())
print("by total matched at entry\n",tb(R,pd.cut(R.tm,[0,2000,10000,50000,250000,1e12])).to_string())
R['mon']=pd.to_datetime(R.off,unit='s').dt.strftime('%m-%d')
top=R.comp.value_counts().head(10).index; print("by competition, ten largest\n",tb(R[R.comp.isin(top)],'comp').sort_values('n',ascending=False).to_string())
md=float(np.median(R.off)); out=[]
for nm,x,c in (('REAL TOUCH (scored)',R,'v'),('REAL TOUCH, resolved only',R[R.res],'v'),('REAL TOUCH, lay within 10 ticks of the print',R[R.above<=10],'v'),('SAME GAMES AT THE PRINT, control',R,'vp')):
    if len(x)<2: continue
    l=line(x[c].values,np.where(x.off<md,1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],PASS=l['PASS'] and 'scored' in nm))
O=pd.DataFrame(out); print("\n",O.round(3).to_string(index=False))
print("\nmodel cost of the touch per GBP 10, no results involved, EV at the print's implied chance, print fill minus touch fill: mean",round(R.mcost.mean(),3),"median",round(R.mcost.median(),3))
print("for scale: item 271 +0.402 resolved, item 279 all games at last-print odds +0.247, official 490 games +0.452")
S=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
