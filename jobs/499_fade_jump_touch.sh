#!/bin/bash
set -o pipefail
# 499_fade_jump_touch (Finder 2026-11-06, queue item 301, Finder's own, source a; from jobs/499_flip_flow.sh, jobs/499_dnb_touch.sh): fade the jump at the off at the real touch, games after the tape's end. Rule pushed in the queue before these prices. Read only, no tables written.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,tstat
from lib_official import bk,ly,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
def jump(pre,first):
    """Implied points pre less first; None unless 1 to 8 points."""
    g=100*(1/pre-1/first)
    return g if 1<=abs(g)<=8 else None
def winner(last):
    w=[k for k,v in last.items() if v<=1.10]
    return w[0] if len(w)==1 else None
def value(side,px,last,s):
    """(pnl,resolved). side B or L; last {runner: last ltp}."""
    f=bk if side=='B' else ly; win,lose=f(px,True),f(px,False)
    if win is None: return None,False
    w=winner(last)
    if w is not None: return (win if w==s else lose),True
    t=sum(1/v for v in last.values()); p=(1/last[s])/t
    return p*win+(1-p)*lose,False
# known answers, worked by hand
assert abs(jump(2.0,2.1)-2.38095)<1e-4 and abs(jump(2.0,1.9)+2.63158)<1e-4 and jump(2.0,2.02) is None and jump(2.0,3.0) is None
assert winner({'A':1.05,'B':30.})=='A' and winner({'A':1.5,'B':3.}) is None and winner({'A':1.05,'B':1.09}) is None
assert value('L',2.0,{'A':1.05,'B':30.},'A')==(-10.0,True) and abs(value('B',2.04,{'A':1.05,'B':30.},'A')[0]-9.996)<1e-9
_v,_r=value('L',2.0,{'A':2.,'B':2.},'A'); assert not _r and abs(_v-(10/1.02*.98-10)/2)<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT market_id,min(ts) FILTER (WHERE minute>=1) t1 FROM liq_sample WHERE mkt=ANY(%s) GROUP BY 1",con,params=(['MO','OU25'],)).dropna()
FIRST=dict(zip(F.market_id,secs(F.t1)))
Pre=pd.read_sql("SELECT DISTINCT ts,market_id,event_name ev,mkt,sel,ltp::float8 ltp FROM liq_sample WHERE mkt=ANY(%s) AND minute=0 AND ltp>=1.01 AND ltp<1000 AND ts>now()-interval '30 days'",con,params=(['MO','OU25'],))
Fi=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,mkt,sel,minute,ts,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt=ANY(%s) AND minute>=1 ORDER BY market_id,sel,ts",con,params=(['MO','OU25'],))
La=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,sel,ltp::float8 ltp,minute FROM liq_sample WHERE mkt=ANY(%s) AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,sel,ts DESC",con,params=(['MO','OU25'],))
con.close()
print(f"pre rows {len(Pre):,}, first rows {len(Fi):,}, last rows {len(La):,}, {time.time()-T0:.0f}s",flush=True)
Pre['tt']=secs(Pre.ts); Fi['tt']=secs(Fi.ts)
LAST={m:dict(zip(g.sel,g.ltp)) for m,g in La.groupby('market_id')}; ENDMIN=La.groupby('market_id').minute.max().to_dict()
FI={m:g for m,g in Fi.groupby('market_id')}
C=Counter(); rows=[]; WANT={'MO':{'HOME','DRAW','AWAY'},'OU25':{'OVER','UNDER'}}
for (m,ev,mk),g in Pre.groupby(['market_id','ev','mkt'],sort=False):
    C[mk+' markets']+=1
    if m not in FI or m not in LAST or m not in FIRST: C[mk+' no in-play']+=1; continue
    t1=FIRST[m]; f=FI[m]; g=g[g.tt<=t1-120]
    if not len(g): C[mk+' no pre row 120 s before']+=1; continue
    if g.duplicated(['sel','tt']).any(): C[mk+' two rows one label one time']+=1; continue
    if set(LAST[m])!=WANT[mk] : C[mk+' labels not as expected']+=1; continue
    pr=g.sort_values('tt').groupby('sel').tail(1).set_index('sel').ltp.to_dict()
    best=None
    for r in f.itertuples():
        if not 1<=r.minute<=3: C[mk+' first row past minute 3']+=1; continue
        if r.sel not in pr or r.ltp!=r.ltp or r.ltp<1.01 or r.b!=r.b or r.l!=r.l or r.b<1.01 or r.l<=r.b: C[mk+' row unusable']+=1; continue
        j=jump(pr[r.sel],r.ltp)
        if j is None: continue
        if best is None or abs(j)>abs(best[0]): best=(j,r)
    if best is None: C[mk+' no jump 1-8']+=1; continue
    j,r=best; C[mk+' read']+=1; res=[]
    for lab,side in (('fade','B' if j>0 else 'L'),('follow','L' if j>0 else 'B')):
        px=r.b if side=='B' else r.l
        if px>50: C[mk+' over 50']+=1; continue
        v,rs=value(side,px,LAST[m],r.sel)
        if v is not None: rows.append((mk,lab,'BACK' if side=='B' else 'LAY',m,ev,r.tt,v,rs,ENDMIN.get(m,0)))
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['mk','lab','side','m','ev','tt','v','res','endmin'])
med=T.tt.median(); T['h']=np.where(T.tt<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"games",T.ev.nunique(),"resolved share",round(T.res.mean(),3),"last row at minute 85+",round((T.endmin>=85).mean(),3),flush=True)
o=[]
for (mk,lab),x in T.groupby(['mk','lab']):
    d=line(x.v.values,x.h.values); v=x.v.values; y=x[x.res]
    o.append(dict(line=f"{mk} {lab}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),res_only=round(y.v.mean(),3),PASS=d['PASS'] and lab=='fade'))
O=pd.DataFrame(o).sort_values('t',ascending=False); print(O.to_string(index=False))
print("by side, fade"); print(T[T.lab=='fade'].groupby(['mk','side']).v.agg(['count','mean']).round(3).to_string())
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
PY
