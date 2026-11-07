#!/bin/bash
set -o pipefail
# 499_xx_value (Finder 2026-11-07, queue item 332, Finder's own, source b, from jobs/499_xx_lead.sh): take Matchbook's price when it beats Betfair's mid, hold to the result. Rule pushed in the queue before any price. Read only. Two days of pre-off tape and results inferred from last prints: a pass earns a re-read with official results, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes
from lib_official import secs
from lib_xx import pair,side_of,pick,median_gap,LABS
import lib_xx; lib_xx.checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
def edge_back(ob,mid): return step(ob,-1)/mid-1
def edge_lay(ol,mid): return mid/step(ol,1)-1
def held(side,a,last,s):
    """(value,resolved). a is the fill. Last print 1.10 or under wins, else share of the book at the last prints."""
    f=(lambda w: back_settle(a,w)) if side=='B' else (lambda w: lay_settle(a,w))
    w=[k for k,v in last.items() if v<=1.10]
    if len(w)==1: return f(w[0]==s),True
    t=sum(1/v for v in last.values()); p=(1/last[s])/t
    return p*f(True)+(1-p)*f(False),False
# known answers, worked by hand. Back 3.05 touch fills 3.0, mid 2.9: 3/2.9-1=+3.448%. Lay 2.82 touch fills 2.84, ladder 0.02 under 3, mid 2.9: 2.9/2.84-1=+2.113%.
assert abs(edge_back(3.05,2.9)-(3.0/2.9-1))<1e-9 and abs(edge_lay(2.82,2.9)-(2.9/2.84-1))<1e-9
# Back at 3.0 wins 20*.98=19.6, loses -10. Lay at 3.0: stake 5, wins 5*.98=4.9 if the runner loses, -10 if it wins.
assert held('B',3.0,{'A':1.05,'B':30.},'A')==(19.6,True) and held('B',3.0,{'A':1.05,'B':30.},'B')==(-10.0,True)
assert held('L',3.0,{'A':1.05,'B':30.},'B')==(4.9,True) and held('L',3.0,{'A':1.05,'B':30.},'A')==(-10.0,True)
_v,_r=held('B',3.0,{'A':2.,'B':2.},'A'); assert not _r and abs(_v-4.8)<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
L=psycopg2.connect(creds.pg_local()); lc=L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
X=pd.read_sql("SELECT DISTINCT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,back_sz,lay_px,lay_sz FROM xx_pre_329 WHERE exchange='matchbook'",L)
B=pd.read_sql("SELECT DISTINCT ts,market_id,event_name,sel,minute,back_px::float8 b,lay_px::float8 l,ltp::float8 ltp FROM liq_sample WHERE mkt='MO'",L)
L.close()
B['tt']=secs(B.ts); B=B.sort_values('tt'); X['tt']=secs(X.ts); X['st']=secs(X.start_ts)
BM={m:g for m,g in B.groupby('market_id')}
LAST={m:g.dropna(subset=['ltp']).groupby('sel').ltp.last().to_dict() for m,g in BM.items()}
ENDMIN=B.groupby('market_id').minute.max().to_dict()
SPAN={m:(g.tt.min(),g.tt.max()) for m,g in BM.items()}
PAIRS=[(pair(ev),m) for m,ev in B[['market_id','event_name']].drop_duplicates().itertuples(index=False) if pair(ev)]
C=Counter(); rows=[]
for (xm,ev,st),gx in X.groupby(['market_id','event_name','st'],sort=False):
    C['markets']+=1
    got=pick(pair(ev),[(q,m) for q,m in PAIRS if SPAN[m][0]<=st+7200 and SPAN[m][1]>=st-1800])
    if got is None: C['no Betfair market']+=1; continue
    m,how=got; gb=BM[m]
    if set(gb.sel.unique())!=LABS or gb.duplicated(['sel','tt']).any(): C['Betfair labels or duplicates']+=1; continue
    gx=gx.assign(side=[side_of(s,ev) for s in gx.sel_name])
    if gx.side.isna().any() or set(gx.side.unique())!=LABS: C['runner names not matched']+=1; continue
    bad=False
    for s,bs in gb.groupby('sel'):
        o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&(bs.minute==0)]
        mg=median_gap(o.tt.values,((o.back_px+o.lay_px)/2).values,v.tt.values,((v.b+v.l)/2).values)
        if mg is not None and mg>0.15: bad=True
    if bad: C['wrong pairing, gap over 15%']+=1; continue
    last=LAST.get(m,{})
    if len(last)!=3: C['no last prints']+=1; continue
    C['games read']+=1
    for s,bs in gb.groupby('sel'):
        o=gx[(gx.side==s)].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
        if not len(o) or not len(v): continue
        ot=o.tt.values; ob=o.back_px.values; ol=o.lay_px.values; obs=o.back_sz.values; ols=o.lay_sz.values
        vt=v.tt.values; vm=((v.b+v.l)/2).values; vmin=v.minute.values; done=set()
        for i in np.where((vt>=st-1800)&(vt<=st-120)&(vmin==0))[0]:
            t=vt[i]; j=int(np.searchsorted(ot,t,side='right'))-1
            if j<0 or ot[j]<t-60: continue
            for side,px,sz,ef in (('B',ob[j],obs[j],edge_back),('L',ol[j],ols[j],edge_lay)):
                if px!=px or px is None or not sz>=10: continue
                a=step(px,-1) if side=='B' else step(px,1)
                if a>50 or a<=1.01: continue
                e=ef(px,vm[i]); k='VALUE' if e>=0.02 else 'NEAR' if -0.005<e<0 else None
                if k is None or (k,side) in done: continue
                done.add((k,side)); val,res=held(side,a,last,s); rows.append((k,side,m,ev,s,t,val,res,e,a,ENDMIN.get(m,0)))
T=pd.DataFrame(rows,columns=['k','side','m','ev','s','tt','v','res','e','a','endmin'])
print("counts",dict(sorted(C.items())),flush=True)
out=[]
if len(T):
    med=T.tt.median(); T['h']=np.where(T.tt<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"resolved share",round(T.res.mean(),3),"last row minute 85+",round((T.endmin>=85).mean(),3),flush=True)
    def rd(name,d,can):
        if not len(d): return
        a=d[d.h==1].v; b=d[d.h==2].v; mean=d.v.mean(); t=tstat(d.v); tg=tstat(d.groupby('m').v.sum())
        ok=can and passes(len(d),len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,mean) and tg>=3.5
        out.append(dict(line=name,n=len(d),per10=round(mean,3),t=round(t,2),t_game=round(tg,2),h1=round(a.mean(),3) if len(a) else None,n1=len(a),h2=round(b.mean(),3) if len(b) else None,n2=len(b),games=d.m.nunique(),edge=round(100*d.e.mean(),2),maxwin=round(d.v.max(),2),resolved=round(d.res.mean(),3),PASS='PASS' if ok else ''))
    for k in ('VALUE','NEAR'):
        K=T[T.k==k]; can=k=='VALUE'
        rd(f"{k} ALL",K,can); rd(f"{k} BACK",K[K.side=='B'],can); rd(f"{k} LAY",K[K.side=='L'],can)
    K=T[T.k=='VALUE']
    for lo,hi in ((1,2),(2,4),(4,10),(10,50)): rd(f"ctx VALUE fill {lo}-{hi}",K[(K.a>=lo)&(K.a<hi)],False)
    rd("ctx VALUE resolved only, flatters",K[K.res],False)
    R=pd.DataFrame(out).sort_values('t',ascending=False); print(R.to_string(index=False),flush=True)
    print("== SURVIVORS:",[r for r in R[R.PASS=='PASS'].line] or 'none')
else: print("== SURVIVORS: none, no trades")
print(f"run {time.time()-T0:.0f}s")
PY
