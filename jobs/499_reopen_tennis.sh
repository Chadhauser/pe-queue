#!/bin/bash
set -o pipefail
# VOID 2026-11-07: no trade reached a real exit, the reopens sit in a match's last minutes, and 67% are replayed states. See reports/finder_2026-11-07_items265-402.md.
# 499_reopen_tennis (Finder 2026-11-07, queue item 398, Finder's own, source a; first Finder read of ip_reopen): tennis, a large move across a suspension, follow or fade at the real touch. Rule pushed in the queue before any price. Read only, no tables written. ip_reopen is live tape on Railway, read here; finder_tlog is the local copy of bf_tennis_log, ends about 00:00 UTC 7 Nov.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
import lib_cand
from lib_cand import line,step,back_hedge,lay_hedge
from lib_official import bk,ly,secs,checks
lib_cand._checks(); checks()
def real(b,l): return b==b and l==l and b>1.0 and l<=b*1.05
def ev(f,p,q): return q*f(p,True)+(1-q)*f(p,False)
def q_last(a,b): x,y=1/a,1/b; return x/(x+y)
def settle(last_s,last_o):
    """Won True or False from the log's last prints, None if neither is settled."""
    if last_s<=1.05: return True
    if last_s>=20: return False
    return None
# known answers, worked by hand
assert real(2.0,2.1) and not real(2.0,2.2) and settle(1.05,20)==True and settle(25,1.1)==False and settle(1.5,2.5) is None
assert abs(back_hedge(2.0,1.8)-10*(2.0/1.81-1)*.98)<1e-9 and abs(lay_hedge(2.0,1.8)-(10*(1-2.0/1.79)))<1e-9
assert abs(q_last(4,1.25)-0.25/1.05)<1e-9 and abs(ev(bk,1.4,.5)-(-3.089))<1e-9
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='300s'")
R=pd.read_sql("SELECT ts,market_id,event_name ev,secs_since_start ss,sel_id,pre_ltp::float8 pre,post_back_px::float8 b,post_lay_px::float8 l FROM ip_reopen WHERE sport='tennis' AND market_type='MATCH_ODDS' ORDER BY ts",rc); rc.close()
R['tt']=secs(R.ts); print(f"reopen rows {len(R):,}, markets {R.market_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); ents=[]
for m,g in R.groupby('market_id',sort=True):
    for t,h in g.groupby('tt',sort=True):
        if len(h)!=2: C['row not two runners']+=1; continue
        q=[]
        for r in h.itertuples():
            if r.pre==r.pre and r.pre>1 and real(r.b,r.l) and 0.5*(r.b+r.l)<=r.pre*0.85: q.append(r)
        if len(q)==1:
            r=q[0]; ents.append((m,r.ev,float(t),r.sel_id,r.pre,r.b,r.l,r.ss)); C['entries']+=1; break
E=pd.DataFrame(ents,columns='m ev t s pre b l ss'.split()); print("markets with a qualifying reopen",len(E),flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TL=pd.read_sql("SELECT max(captured_at) z FROM finder_tlog",con).z.iloc[0]; TE=float(secs(pd.Series([TL])).iloc[0]); print("log ends",TL,flush=True)
rows=[]
for c in range(0,len(E),300):
    e_=E.iloc[c:c+300]; P=pd.read_sql("SELECT market_id,selection_id s,captured_at ts,back_price::float8 b,lay_price::float8 l,last_traded::float8 ltp FROM finder_tlog WHERE market_id=ANY(%s) AND inplay ORDER BY market_id,selection_id,captured_at",con,params=(list(e_.m),))
    P['tt']=secs(P.ts); G={k:x for k,x in P.groupby(['market_id','s'],sort=False)}
    for r in e_.itertuples():
        if r.t>TE-3600: C['reopen in the last hour of the log, left out']+=1; continue
        y=G.get((r.m,r.s))
        ot=[k for k in G if k[0]==r.m and k[1]!=r.s]
        if y is None or not ot: C['no log rows for the market']+=1; continue
        z=G[ot[0]]; ls=y.ltp.dropna(); lo=z.ltp.dropna()
        if not len(ls) or not len(lo): C['no last print']+=1; continue
        ts,bb,ll=y.tt.values,y.b.values,y.l.values; i=np.nonzero((ts>=r.t+300))[0]; x=None
        for k in i:
            if real(bb[k],ll[k]): x=int(k); break
        ab=step(r.b,-1); al=step(r.l,1)
        if ab<=1.01 or al<1.10: C['ladder end']+=1; continue
        if x is not None:
            fo=back_hedge(ab,float(ll[x])); fa=lay_hedge(al,float(bb[x])); C['exit at the touch']+=1; how='exit'
        else:
            w=settle(float(ls.iloc[-1]),float(lo.iloc[-1]))
            if w is None:
                q=q_last(float(ls.iloc[-1]),float(lo.iloc[-1])); fo=ev(bk,r.b,q); fa=ev(ly,r.l,q); C['settled at last-print odds']+=1; how='lpo'
            else: fo=bk(r.b,w); fa=ly(r.l,w); C['settled at the result']+=1; how='res'
        rows.append((r.m,r.t,r.pre,r.b,r.l,fo,fa,how,r.ss))
con.close(); print("counted:",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns='m off pre b l fo fa how ss'.split()); assert not T.duplicated('m').any(); md=float(np.median(T.off)); print("trades",len(T),"split at",pd.Timestamp(md,unit='s',tz='UTC'),"spread pct median",round(float((T.l/T.b-1).median()*100),2),flush=True)
T['band']=pd.cut(T.b,[1,1.5,3,1000],right=False,labels=['<1.5','1.5-3','>=3']); out=[]
for nm,x in [('all',T)]+[(str(k),v) for k,v in T.groupby('band',observed=True)]:
    for s_,c in (('FOLLOW','fo'),('FADE','fa')):
        l=line(x[c].values,np.where(x.off<md,1,2)); out.append(dict(line=f'{nm} {s_}',n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],PASS=l['PASS']))
O=pd.DataFrame(out); print("\n"+O.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\nFADE by exit kind:",T.groupby('how').fa.agg(['size','mean']).round(3).to_dict('index'),"FOLLOW:",T.groupby('how').fo.agg(['size','mean']).round(3).to_dict('index'))
S=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
