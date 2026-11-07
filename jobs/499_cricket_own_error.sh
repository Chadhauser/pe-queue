#!/bin/bash
set -o pipefail
# 499_cricket_own_error (Finder 2026-11-07, queue items 354 and 357, Finder's own; engine from jobs/499_cricket_outsider.sh). Item 354: a team's own price error, walked forward. Item 357: first in-play touch of a price, hold to result. Rules pushed in the queue before any price. Read only, no tables written. Last-traded prints, inferred results, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
def infer(last):
    lo=[k for k,v in last.items() if v<=1.10]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=5.0 for k,v in last.items() if k!=lo[0]) else None
def lastq(last,s,p_fair):
    """Chance of runner s from the last prints, overround removed; the entry's fair if a print is missing."""
    if len(last)!=2 or s not in last: return p_fair
    o=[k for k in last if k!=s][0]; return (1/last[s])/(1/last[s]+1/last[o])
def score(f,p,s,win,q):
    """f is bk or ly. Resolved: at the result. Unresolved: at last-print odds. None if the ladder end stops the bet."""
    a,b=f(p,True),f(p,False)
    if a is None or b is None: return None
    if win is not None: return a if win==s else b
    return q*a+(1-q)*b
def zof(h,minn): return None if h[2]<minn or h[1]<=0 else h[0]/h[1]**0.5
def label(z,zo):
    if z is None: return None
    if z>=1.5: return None if (zo is not None and zo>=1.5) else 'HIGH'
    if z<=-1.5: return None if (zo is not None and zo<=-1.5) else 'LOW'
    return 'CTRL' if abs(z)<=0.5 else None
def touch(px,T):
    """Index of the first print at or under T, None if there is none or the runner opened at or under T. px: one runner's in-play prints in time order."""
    if not len(px) or px[0]<=T: return None
    w=np.nonzero(np.asarray(px)<=T)[0]
    return int(w[0]) if len(w) else None
# known answers, worked by hand
assert infer({'a':1.05,'b':20})=='a' and infer({'a':1.2,'b':5}) is None and infer({'a':1.05,'b':4.9}) is None and infer({'a':1.02}) is None
assert abs(lastq({'a':2.0,'b':2.0},'a',.9)-0.5)<1e-9 and abs(lastq({'a':1.25,'b':5.0},'a',.1)-0.8)<1e-9 and lastq({'a':2.0},'a',.3)==.3
# back 2.04 fills 2.02: wins 9.996, loses 10; unresolved at 0.5: -0.002
assert abs(score(bk,2.04,'a','a',0)-9.996)<1e-9 and score(bk,2.04,'a','b',0)==-10.0 and abs(score(bk,2.04,'a',None,.5)+0.002)<1e-9
assert score(bk,1.01,'a','a',0) is None and abs(score(ly,2.0,'a','b',0)-10/1.02*.98)<1e-9
assert touch([2.0,1.6,1.5,1.4],1.5)==2 and touch([1.5,1.2],1.5) is None and touch([2.0,1.6],1.5) is None and touch([],1.5) is None
assert label(2,None)=='HIGH' and label(2,2) is None and label(-2,0)=='LOW' and label(.4,3)=='CTRL' and label(1,0) is None
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
A['tt']=secs(A.ts); A['off']=secs(A.mt)
A=A.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
GA={m:g for m,g in A.groupby('market_id',sort=False)}
MIDS=pd.read_sql("SELECT DISTINCT market_id FROM bf_hist_other WHERE "+Q0+" AND inplay",con).market_id.tolist(); MIDS.sort()
print(f"pre rows {len(A)}, in-play markets {len(MIDS)}, {time.time()-T0:.0f}s",flush=True)
def chunks():
    """In-play prints 300 markets at a time: the whole set does not fit the job's memory cap. No market spans two chunks, so nothing is cut."""
    for c in range(0,len(MIDS),300):
        B=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE "+Q0+" AND market_id=ANY(%s) AND inplay AND ts<=market_time+interval '12 hours'",con,params=(MIDS[c:c+300],))
        if not len(B): continue
        B['tt']=secs(B.ts); B['off']=secs(B.mt); B=B.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
        for m,g in B.groupby('market_id',sort=True): yield m,g
        if (c//300)%5==0: print(f"  {c+300}/{len(MIDS)}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); seen=set(); G=[]; IPV=[]; IPN=Counter()
TS=(1.50,1.30,1.15,1.05)
for m,g in chunks():
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id']+=1; continue
    seen.add((ev,o)); run={s:(y.tt.values,y.ltp.values) for s,y in g.groupby('sel',sort=False)}
    if len(run)!=2: C['not two runners in play']+=1; continue
    last={s:float(v[1][-1]) for s,v in run.items()}; win=infer(last); C['resolved' if win else 'unresolved']+=1
    a,b=list(run); fp={s:float(run[s][1][0]) for s in run}; fav=a if fp[a]<fp[b] else b if fp[b]<fp[a] else None
    # item 357
    for s in run:
        q=lastq(last,s,.5); ts,px=run[s]; roles=[]
        if s==fav: roles.append('FAV')
        if fp[s]>2.0: roles.append('OUT')
        for T in TS:
            i=touch(px,T)
            if i is None: continue
            for ro in roles:
                IPN[(ro,T,'trigger')]+=1
                if i+1>=len(px):
                    IPN[(ro,T,'no next print')]+=1
                    x=score(ly,float(px[i]),s,win,q)
                    if x is not None: IPV.append((ro,T,'LAYX',m,o,s,x,float(px[i]),win==s if win else np.nan))
                    continue
                nx=float(px[i+1])
                for nm,f in (('BACK',bk),('LAY',ly)):
                    x=score(f,nx,s,win,q)
                    if x is not None: IPV.append((ro,T,nm,m,o,s,x,nx,win==s if win else np.nan))
                x=score(ly,nx,s,win,q)
                if x is not None: IPV.append((ro,T,'LAYX',m,o,s,x,nx,win==s if win else np.nan))
    # item 354: pre-off entry on both runners
    pre=GA.get(m)
    if pre is None: C['no pre-off prints']+=1; continue
    en={}
    for s,y in pre.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-3600,o-120)
        if i is not None: en[s]=(ts,px,i)
    if len(en)!=2 or set(en)!=set(run): C['both runners not priced pre-off']+=1; continue
    G.append((m,o,a,b,en[a],en[b],win,last))
con.close(); print("counted:",dict(sorted(C.items())),f"games for 354 {len(G)}, {time.time()-T0:.0f}s",flush=True); assert len(G)>1000
# ---- item 354
G.sort(key=lambda z:z[1]); H=defaultdict(lambda:[0.,0.,0]); rows=[]; i=0
day=lambda o:int(o//86400)
while i<len(G):
    j=i
    while j<len(G) and day(G[j][1])==day(G[i][1]): j+=1
    for (m,o,a,b,ea,eb,win,last) in G[i:j]:
        pa=float(ea[1][ea[2]]); pb=float(eb[1][eb[2]]); fa=(1/pa)/(1/pa+1/pb)
        za,zb=zof(H[a],15),zof(H[b],15)
        for s,e,fs,z,zo in ((a,ea,fa,za,zb),(b,eb,1-fa,zb,za)):
            lab=label(z,zo)
            if not lab: continue
            ts,px,k=e; q=lastq(last,s,fs)
            for nm,f,sd in (('back',bk,'B'),('lay',ly,'L')):
                p=fill(ts,px,k,sd)
                if p>50: continue
                x=score(f,p,s,win,q)
                if x is not None: rows.append((lab,nm,m,o,s,x,float(px[k]),win==s if win else np.nan))
    for (m,o,a,b,ea,eb,win,last) in G[i:j]:
        if not win: continue
        pa=float(ea[1][ea[2]]); pb=float(eb[1][eb[2]]); fa=(1/pa)/(1/pa+1/pb); wa=1 if win==a else 0
        for k,ff,ww in ((a,fa,wa),(b,1-fa,1-wa)):
            H[k][0]+=ww-ff; H[k][1]+=ff*(1-ff); H[k][2]+=1
    i=j
R=pd.DataFrame(rows,columns='st side m off who v px won'.split()); assert not R.duplicated(['st','side','m','who']).any()
out=[]
for (st,side),x in R.groupby(['st','side']):
    l=line(x.v.values,np.where(x.off<np.median(x.off),1,2)); out.append(dict(line=f'{st} {side}',n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],maxwin=l['maxwin'],won=x.won.astype(float).mean(),imp=(1/x.px).mean(),teams=x.who.nunique(),PASS=bool(l['PASS'] and st!='CTRL')))
L=pd.DataFrame(out).sort_values('t',ascending=False); print("\n== ITEM 354, 4 lines plus control, by t\n",L.round(3).to_string(index=False))
print("teams with 15 or more resolved games:",sum(1 for v in H.values() if v[2]>=15),"top by z:",sorted(((round(zof(v,15),2),k,v[2]) for k,v in H.items() if v[2]>=15),reverse=True)[:6],"bottom:",sorted(((round(zof(v,15),2),k,v[2]) for k,v in H.items() if v[2]>=15))[:6])
W=L[L.PASS]; print(f"\n== SURVIVORS 354: {len(W)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
# ---- item 357
P=pd.DataFrame(IPV,columns='ro T side m off s v px won'.split())
print("\n== ITEM 357 triggers and unfilled:",{f"{k[0]} {k[1]} {k[2]}":v for k,v in sorted(IPN.items(),key=lambda z:str(z[0]))})
out=[]; assert not P[P.side!='LAYX'].duplicated(['ro','T','side','m','s']).any()
for (ro,T,side),x in P.groupby(['ro','T','side']):
    if side=='LAYX': continue
    l=line(x.v.values,np.where(x.off<np.median(x.off),1,2)); d=dict(line=f'{ro} {T} {side}',n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],maxwin=l['maxwin'],won=x.won.astype(float).mean(),imp=(1/x.px).mean(),games=x.m.nunique()); ok=l['PASS']
    if side=='LAY':
        z=P[(P.ro==ro)&(P['T']==T)&(P.side=='LAYX')]; lx=line(z.v.values,np.where(z.off<np.median(z.off),1,2)); d.update(n_x=lx['n'],per10_x=lx['per10'],t_x=lx['t']); ok=ok and lx['PASS']
    d['PASS']=bool(ok); out.append(d)
L=pd.DataFrame(out).sort_values('t',ascending=False); print(L.round(3).to_string(index=False))
W=L[L.PASS]; print(f"\n== SURVIVORS 357: {len(W)} of {len(L)}\n",W.round(3).to_string(index=False) if len(W) else "none")
# Review, added after the first read and cannot change a verdict: is the lead in scoring of unresolved games, in a few huge lay stakes, or in the fills far below the level?
print("\n== 357 diagnostics, not tests: resolved games only, and without the 10 largest wins")
d=[]
for ro,T,side in (('OUT',1.5,'LAY'),('OUT',1.3,'LAY'),('FAV',1.5,'LAY'),('OUT',1.3,'LAYX'),('OUT',1.5,'BACK')):
    x=P[(P.ro==ro)&(P['T']==T)&(P.side==side)]; r=x[x.won.notna()]; u=x[x.won.isna()]; v=np.sort(r.v.values)
    d.append(dict(line=f'{ro} {T} {side}',n=len(x),all=x.v.mean(),n_res=len(r),resolved=r.v.mean(),t_res=line(r.v.values,np.ones(len(r)))['t'],no_top10=v[:-10].mean(),n_unres=len(u),unres_sum=u.v.sum(),res_sum=r.v.sum()))
print(pd.DataFrame(d).round(3).to_string(index=False))
x=P[(P.ro=='OUT')&(P['T']==1.5)&(P.side=='LAY')&P.won.notna()]; b=pd.cut(x.px,[1,1.1,1.3,1.5,100],right=True)
print("OUT 1.5 LAY, resolved, by fill print:\n",x.groupby(b,observed=True).agg(n=('v','size'),per10=('v','mean'),won=('won',lambda s:s.astype(float).mean()),imp=('px',lambda s:(1/s).mean())).round(3).to_string())
print(f"total {time.time()-T0:.0f}s")
PY
