#!/bin/bash
set -o pipefail
# 499_cs00_u05_preoff (Finder 2026-11-09, 04:30 UTC run, lane A, queue item 481, Finder's own, source c structural; rule pushed in the queue before this job read a price).
# CS 0-0 and Under 0.5 Goals are the same event in two markets. Before the off, when their last prints disagree, trade the one whose print is the LATER
# (so the signal, the other market's earlier print, was already public, and nothing is forward-filled): lay it if it is the dearer (higher implied), back it if cheaper.
# Window: last pre-off print of each within 30 min before market_time, the two at most 300 s apart. Gap = 100*(1/p_cs - 1/p_u) implied points.
# Scored: LAY_RICH |gap|>=1 and BACK_CHEAP |gap|>=1, one bet a game, one tick adverse, £10 stake or liability, 2% on profit, held to the market's own
# official result (bf_hist_result, one winner), never dropped. Women and youth out. Halves by date median. Read only, no tables written. Prints only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,gc,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step
from lib_official import ly,bk,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
SEL={'CORRECT_SCORE':'0 - 0','OVER_UNDER_05':'Under 0.5 Goals'}
def gap(p_cs,p_u): return 100*(1/p_cs-1/p_u)
def decide(t_cs,p_cs,t_u,p_u,g_min):
    """-> (market traded, side 'L'/'B', |gap|) or None. Trade only the later print; lay if it is dearer, back if cheaper."""
    if abs(t_cs-t_u)>300: return None
    g=gap(p_cs,p_u)
    if abs(g)<g_min: return None
    later='CS' if t_cs>=t_u else 'U'
    rich='CS' if g>0 else 'U'
    return later,('L' if later==rich else 'B'),abs(g)
# known answers, worked by hand
# CS 10.0 (10.0%), U 12.5 (8.0%): gap +2.0, CS dearer. CS printed later -> lay CS; U later -> back U.
assert abs(gap(10.0,12.5)-2.0)<1e-9
assert decide(100,10.0,50,12.5,1.0)==('CS','L',decide(100,10.0,50,12.5,1.0)[2]) and decide(50,10.0,100,12.5,1.0)[:2]==('U','B')
assert decide(0,10.0,400,12.5,1.0) is None and decide(0,10.0,300,12.5,1.0) is not None
assert decide(0,10.0,10,10.5,1.0) is None   # 10.0 v 9.524: gap 0.476 < 1
# tie in time -> CS counts as later (fixed rule)
assert decide(5,12.5,5,10.0,1.0)==('CS','B',decide(5,12.5,5,10.0,1.0)[2])
# lay 10.0 -> 10.5 one tick adverse: liability 10, stake 10/9.5=1.0526, wins 1.0316 after 2%; back 12.5 -> 12.0: wins 110*0.98=107.8
assert step(10.0,1)==10.5 and abs(ly(10.0,False)-10/9.5*0.98)<1e-9 and ly(10.0,True)==-10.0
assert step(12.5,-1)==12.0 and abs(bk(12.5,True)-107.8)<1e-9 and bk(12.5,False)==-10.0
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS={}
for mt in SEL:
    r,dr=load_results(con,[mt]); RS.update(r); print("official",mt,len(r),"dropped (no single winner)",dr,flush=True)
C=Counter(); rows=[]
def chunks():
    for y,ms in ((2022,range(8,13)),(2023,range(1,13)),(2024,range(1,11)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            while a<e:
                b=min(a+pd.Timedelta(days=10),e); yield str(a.date()),str(b.date()); a=b
for lo,hi in chunks():
    X=pd.read_sql("""SELECT market_id,event_id,event_name ev,market_type mkt,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other
                     WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>=%s AND market_time<%s AND NOT inplay
                       AND ts>=market_time-interval '30 minutes' AND ts<=market_time AND sel=ANY(%s) AND ltp>=1.01 AND ltp<1000""",
                  con,params=(list(SEL),lo,hi,list(SEL.values())))
    if X.empty: continue
    X=X[[SEL[m]==s for m,s in zip(X.mkt,X.sel)]]
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'],keep='last')
    L=X.groupby('market_id',sort=False).tail(1)   # last pre-off print of each market
    for eid,G in L.groupby('event_id',sort=False):
        C['events']+=1
        if set(G.mkt)!=set(SEL) or len(G)!=2: C['not both markets']+=1; continue
        cs=G[G.mkt=='CORRECT_SCORE'].iloc[0]; u=G[G.mkt=='OVER_UNDER_05'].iloc[0]; ev=cs.ev
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if cs.market_id not in RS or u.market_id not in RS: C['no official']+=1; continue
        w_cs=RS[cs.market_id].get(SEL['CORRECT_SCORE']); w_u=RS[u.market_id].get(SEL['OVER_UNDER_05'])
        if w_cs is None or w_u is None: C['sel not in result']+=1; continue
        if w_cs!=w_u: C['CS and U0.5 results disagree']+=1
        d=decide(cs.tt,cs.ltp,u.tt,u.ltp,0.0)
        if d is None: C['prints over 300 s apart']+=1; continue
        later,side,g=d; p=cs.ltp if later=='CS' else u.ltp; won=w_cs if later=='CS' else w_u
        v=ly(p,won) if side=='L' else bk(p,won)
        if v is None: C['back at ladder floor']+=1; continue
        rows.append(dict(ev=ev,off=float(cs.off),later=later,side=side,g=g,px=p,won=bool(won),v=v,gap_s=abs(cs.tt-u.tt),
                         mins=(float(cs.off)-max(cs.tt,u.tt))/60))
    del X,L; gc.collect()
    print(lo,"pairs",len(rows),f"{time.time()-T0:.0f}s",flush=True)
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); T=T[T.px<=50].copy(); T['yr']=pd.to_datetime(T.off,unit='s').dt.year
print("games with a pair",len(T),"0-0 rate",round(T.won.mean(),3),"median prints apart s",T.gap_s.median(),"median mins before off",round(T.mins.median(),1))
print("gap distribution (implied points)",T.g.describe(percentiles=[.5,.75,.9,.95,.99]).round(3).to_dict())
def row(nm,x):
    v=x.v.astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    med=x.off.median(); h=np.where(x.off<=med,1,2); d=line(v,h)
    return dict(line=nm,n=d['n'],games=x[['ev','off']].drop_duplicates().shape[0],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),
                n1=d['n1'],n2=d['n2'],won=round(x.won.mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
LR=T[(T.side=='L')]; BC=T[(T.side=='B')]
o=[row('LAY_RICH g>=1 *',LR[LR.g>=1]),row('BACK_CHEAP g>=1 *',BC[BC.g>=1])]
r=[]
for gm in (0.5,2.0,3.0):
    r+=[row(f'LAY_RICH g>={gm}',LR[LR.g>=gm]),row(f'BACK_CHEAP g>={gm}',BC[BC.g>=gm])]
for k in ('CS','U'):
    r+=[row(f'LAY_RICH g>=1 on {k}',LR[(LR.g>=1)&(LR.later==k)]),row(f'BACK_CHEAP g>=1 on {k}',BC[(BC.g>=1)&(BC.later==k)])]
for y in sorted(T.yr.unique()):
    r+=[row(f'{y} LAY_RICH g>=1',LR[(LR.g>=1)&(LR.yr==y)]),row(f'{y} BACK_CHEAP g>=1',BC[(BC.g>=1)&(BC.yr==y)])]
r+=[row('CONTROL lay every later print',T.assign(v=[ly(p,w) for p,w in zip(T.px,T.won)])),
    row('CONTROL back every later print',T.assign(v=[bk(p,w) for p,w in zip(T.px,T.won)]).dropna(subset=['v']))]
print("== ITEM 481, scored lines marked *\n",pd.DataFrame(o).to_string(index=False))
print("\n-- reading lines, cannot pass\n",pd.DataFrame(r).to_string(index=False))
S=[s for s in o if s.get('PASS')]
print("\n== SURVIVORS"); print(pd.DataFrame(S).to_string(index=False) if S else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
