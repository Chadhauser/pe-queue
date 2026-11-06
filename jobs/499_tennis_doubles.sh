#!/bin/bash
set -o pipefail
# READ WITH item 278: the lines this job lists as SURVIVORS are a scoring artefact, +0.008 t 0.07 once unresolved games are scored at last-print odds. See 499_doubles_truth.
# 499_tennis_doubles (Finder 2026-11-06, queue item 275, Finder's own, source d): tennis doubles before the off by band, result inferred by item 268's rule, singles as control. Inferred results: nothing here can be staked without unseen months. Read only. No tables written. Rule is in the queue, fixed before prices.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last,lo_,hi_):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
assert infer({'a':1.05,'b':20},1.10,5.0)=='a' and infer({'a':1.05,'b':4},1.10,5.0) is None and infer({'a':1.02},1.10,5.0) is None
BANDS=[(1.01,1.5,'<1.5'),(1.5,2,'1.5-2'),(2,3,'2-3'),(3,6,'3-6'),(6,20,'6-20')]
def band(p):
    for a,b,n in BANDS:
        if a<=p<b: return n
    return None
assert band(1.5)=='1.5-2' and band(1.49)=='<1.5' and band(20) is None and band(3)=='3-6'
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Tennis' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND (event_name LIKE '%/%' OR abs(hashtext(market_id))%4=0)"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B; print("rows",len(P),f"{time.time()-T0:.0f}s",flush=True)
P['tt']=secs(P.ts); P['off']=secs(P.mt); P['dbl']=P.ev.str.contains('/',regex=False); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0]); d=bool(g.dbl.iloc[0]); tag='D ' if d else 'S '
    if (ev,o) in seen: C[tag+'second id']+=1; continue
    seen.add((ev,o))
    if g.sel.nunique()!=2: C[tag+'not two runners']+=1; continue
    pre=g[~g.inplay]; last=g[g.inplay].groupby('sel').ltp.last().to_dict(); en={}
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is not None: en[s]=(float(px[i]),ts,px,i)
    if not en: C[tag+'no pre-off print']+=1; continue
    w=infer(last,1.10,5.0); ws=infer(last,1.03,20.0)
    C[tag+('resolved' if w else 'unresolved')]+=1
    both=len(en)==2 and en[list(en)[0]][0]!=en[list(en)[1]][0]
    out=max(en,key=lambda z:en[z][0]) if both else None
    for s,(p0,ts,px,i) in en.items():
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L'); b_=band(p0)
        if b_ is None: continue
        won=None if w is None else (w==s); won2=None if ws is None else (ws==s)
        rows.append((d,m,o,b_,s==out,p0,None if won is None else bk(pb,won),None if won is None else ly(pl,won),None if won is None else ly(step(pl,2),won),None if won is None else ly(step(pl,4),won),None if won2 is None else ly(pl,won2)))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='dbl m off b out p vb vl l3 l5 ls'.split()); md=float(np.median(D[D.dbl].off)); print("runner rows",len(D),"doubles",int(D.dbl.sum()),"split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out_=[]
def add(nm,x,c):
    z=x[x[c].notna()]
    if len(z)<30: return
    l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out_.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],PASS=l['PASS']))
for g_,tag in ((True,'DOUBLES'),(False,'SINGLES')):
    x=D[D.dbl==g_]
    for _,_,b_ in BANDS:
        add(f"{tag} {b_} back",x[x.b==b_],'vb'); add(f"{tag} {b_} lay",x[x.b==b_],'vl')
    o_=x[x.out&(x.p>=3)&(x.p<20)]
    add(f"{tag} OUTSIDER 3-20 lay",o_,'vl'); add(f"{tag} OUTSIDER 3-20 lay strict",o_,'ls'); add(f"{tag} OUTSIDER 3-20 lay 3 ticks",o_,'l3'); add(f"{tag} OUTSIDER 3-20 lay 5 ticks",o_,'l5')
L=pd.DataFrame(out_); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}")
print(L[L.line.str.startswith('DOUBLES')].sort_values('t',ascending=False).round(3).to_string(index=False))
print("\nSINGLES control"); print(L[L.line.str.startswith('SINGLES')].round(3).to_string(index=False))
print("\n== SURVIVORS (inferred results, so not cleared to stake even if listed)"); S=L[L.PASS&L.line.str.startswith('DOUBLES')]; print(S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
