#!/bin/bash
set -o pipefail
# 499_identity_exact (Finder 2026-11-06, queue item 293, Finder's own, source c; entry from jobs/499_cup_ties.sh, runner names from jobs/499_htft_roles.sh): the same bet in two markets before the off. Rule pushed in the queue (fd41c8e) before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,tstat
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
U05='Under 0.5 Goals'; U15='Under 1.5 Goals'; U25='Under 2.5 Goals'
PAIRS=[('U05','OVER_UNDER_05',U05,'CORRECT_SCORE',['0 - 0']),
       ('CS00','CORRECT_SCORE','0 - 0','OVER_UNDER_05',[U05]),
       ('FHU05','FIRST_HALF_GOALS_05',U05,'HALF_TIME_SCORE',['0 - 0']),
       ('HTS00','HALF_TIME_SCORE','0 - 0','FIRST_HALF_GOALS_05',[U05]),
       ('U15','OVER_UNDER_15',U15,'CORRECT_SCORE',['0 - 0','1 - 0','0 - 1']),
       ('FHU15','FIRST_HALF_GOALS_15',U15,'HALF_TIME_SCORE',['0 - 0','1 - 0','0 - 1']),
       ('U25','OVER_UNDER_25',U25,'CORRECT_SCORE',['0 - 0','1 - 0','0 - 1','1 - 1','2 - 0','0 - 2'])]
TY=sorted({p[1] for p in PAIRS}|{p[3] for p in PAIRS}|{'MATCH_ODDS','HALF_TIME','HALF_TIME_FULL_TIME'})
def nm(x): return 'Draw' if x=='The Draw' else x
def htft_legs(x,names,ft):
    """x MO or HT runner; names the three MO names as written in HT/FT runners. HT/FT runners that make up x: at full time when ft, else at half-time."""
    x=nm(x)
    return [f"{o}/{x}" if ft else f"{x}/{o}" for o in names]
def gap(px,others):
    """Traded leg's print and the other side's prints: implied less the sum, in points, raw. None if a print is missing."""
    if px is None or any(o is None for o in others) or not others: return None
    return 100*(1/px-sum(1/o for o in others))
def kind(g,G):
    """DEAR: traded leg implied higher than the other side by G points or more, lay it. CHEAP: lower by G or more, back it."""
    return 'DEAR' if g>=G else 'CHEAP' if g<=-G else None
assert htft_legs('The Draw',['A','B','Draw'],True)==['A/Draw','B/Draw','Draw/Draw']
assert htft_legs('A',['A','B','Draw'],False)==['A/A','A/B','A/Draw']
assert abs(gap(2.0,[4.0,4.0]))<1e-9 and abs(gap(2.0,[2.5])-10)<1e-9 and abs(gap(4.0,[2.0])+25)<1e-9 and gap(None,[2.0]) is None and gap(2.0,[None]) is None and gap(2.0,[]) is None
assert kind(2.0,2)=='DEAR' and kind(-2.0,2)=='CHEAP' and kind(1.99,2) is None and kind(-3.9,4) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dr=load_results(con,TY); print("official markets",len(RS),"dropped, not one winner",dr,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def add(pair,off,ev,g,typ,sel,mk,leg):
    """One candidate: g gap, leg (ts,px). Records both sides at G 2 and 4; a line's game may repeat on MO and HT, thinned later."""
    ts,px=leg; i=last_in(ts,off-1200,off-120)
    if i is None: return
    won=RS[mk][sel]
    for G in (2,4):
        k=kind(g,G)
        if k is None: continue
        L=fill(ts,px,i,'L'); B=fill(ts,px,i,'B')
        rows.append((pair,G,k,off,ev,abs(g),None if L>50 else ly(L,won),None if B>50 else bk(B,won)))
def month_chunks():
    for y,ms in ((2024,range(1,12)),(2026,range(5,12))):
        for m in ms:
            a=pd.Timestamp(y,m,1); yield str(a.date()),str((a+pd.offsets.MonthBegin(1)).date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    ngames=0
    for (ev,off),G_ in X.groupby(['ev','off'],sort=False):
        if ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        ngames+=1; B={}
        for ty,g in G_.groupby('ty',sort=False):
            ids=sorted(g.market_id.unique())
            if len(ids)>1: C['second id']+=1
            mk=ids[0]
            if mk not in RS: C['no official, '+ty]+=1; continue
            B[ty]=(mk,{s:(y.tt.values,y.ltp.values) for s,y in g[g.market_id==mk].groupby('sel',sort=False)})
        def lastp(ty,sel):
            if ty not in B or sel not in B[ty][1]: return None
            ts,px=B[ty][1][sel]; i=last_in(ts,off-1200,off-120)
            return None if i is None else float(px[i])
        for name,ty,sel,oty,osels in PAIRS:
            g=gap(lastp(ty,sel),[lastp(oty,o) for o in osels])
            if g is None: C[name+' a leg unprinted']+=1; continue
            if sel not in RS[B[ty][0]]: C[name+' runner not in result']+=1; continue
            C[name+' read']+=1; add(name,off,ev,g,ty,sel,B[ty][0],B[ty][1][sel])
        h,a=ev.split(' v ',1); names=[h,a,'Draw']
        for name,ty,ft in (('MO','MATCH_ODDS',True),('HT','HALF_TIME',False)):
            if ty not in B or 'HALF_TIME_FULL_TIME' not in B: C[name+' no market']+=1; continue
            for sel in B[ty][1]:
                if nm(sel) not in names: C[name+' name mismatch']+=1; continue
                g=gap(lastp(ty,sel),[lastp('HALF_TIME_FULL_TIME',o) for o in htft_legs(sel,names,ft)])
                if g is None or sel not in RS[B[ty][0]]: C[name+' a leg unprinted']+=1; continue
                C[name+' read']+=1; add(name,off,ev,g,ty,sel,B[ty][0],B[ty][1][sel])
    print(lo,"rows",len(X),"games",ngames,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['pair','G','kind','off','ev','abs_gap','layv','backv'])
# one bet per game per line: the largest gap (only MO and HT can hold more than one runner)
T=T.sort_values('abs_gap',ascending=False).drop_duplicates(['pair','G','kind','off','ev'])
med=T.off.median(); T['h']=np.where(T.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"games",T[['off','ev']].drop_duplicates().shape[0],flush=True)
out=[];ctl=[]
for (p,G,k),x in T.groupby(['pair','G','kind']):
    # the rule: CHEAP back, DEAR lay. Swapped: the control, not scored.
    for scored,col,side in ((k=='CHEAP','backv','back'),(k=='DEAR','layv','lay')):
        y=x[x[col].notna()]
        y=y.assign(**{col:y[col].astype(float)})
        if len(y)<2: continue
        d=line(y[col].values,y.h.values)
        v=y[col].values; xl=np.delete(v,v.argmax()).mean()
        r=dict(line=f"{p} G{G} {k} {side}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(xl,3),PASS=d['PASS'])
        (out if scored else ctl).append(r)
O=pd.DataFrame(out).sort_values('t',ascending=False); K=pd.DataFrame(ctl).sort_values('t',ascending=False)
print("scored lines",len(O)); print(O.head(20).to_string(index=False)); print("worst"); print(O.tail(5).to_string(index=False))
print("control, swapped sides, not scored"); print(K.head(8).to_string(index=False))
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
PY
