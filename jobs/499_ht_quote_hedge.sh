#!/bin/bash
set -o pipefail
# 499_ht_quote_hedge (Finder 2026-11-07, queue item 412, pilot, from items 410, 411): rest inside the HT/FT book after half-time, hedge on MO when a later print goes through the level. Read only, no tables written. Fills are inferred from sampled prints.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql|PerformanceWarning"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,tstat
import lib_cand; lib_cand._checks()
from lib_wom import tgame
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',100)
def lock_back_hf(b,l,stake=10.0):
    """Backed stake at b on HT/FT, lay stake*b/l at l on MO. Worse outcome after 2% on the winning market only."""
    s2=stake*b/l
    return min(stake*(b-1)*.98-s2*(l-1),-stake+s2*.98)
def lock_lay_hf(l,b,liab=10.0):
    """Laid at l on HT/FT for a liability of 10, back stake*l/b at b on MO. Worse outcome after 2%."""
    stake=liab/(l-1); s2=stake*l/b
    return min(-liab+s2*(b-1)*.98,stake*.98-s2)
def side_of(name,ev):
    if name=='DRAW': return 'DRAW'
    h,a=[x.upper() for x in ev.split(' v ',1)]
    H,A=name in h,name in a
    return 'HOME' if H and not A else 'AWAY' if A and not H else None
def x_name(xs,names):
    if xs=='THE DRAW': return 'DRAW' if 'DRAW' in names else None
    fit=[n for n in names if n!='DRAW' and (n in xs or xs in n)]
    return fit[0] if len(fit)==1 else None
def quote_lay(mb,hb,hl,k):
    """Lay offered k ticks under the MO back, only if strictly inside the HT/FT book."""
    q=step(mb,-k)
    return q if hb<q<hl and q>1.01 else None
def quote_back(ml,hb,hl,k):
    """Back offered k ticks over the MO lay, only if strictly inside the HT/FT book."""
    q=step(ml,k)
    return q if hb<q<hl else None
# known answers, worked by hand
assert step(3.0,-2)==2.96 and step(3.0,2)==3.1
assert quote_lay(3.0,2.5,3.5,2)==2.96 and quote_lay(3.0,2.96,3.5,2) is None and quote_lay(3.0,2.5,2.96,2) is None
assert quote_back(3.0,2.5,3.5,2)==3.1 and quote_back(3.0,2.5,3.1,2) is None
# Backed 10 at 3.1, MO lay still 3.0: lay 10.3333. F wins 21*.98=20.58 - 20.6667=-0.0867. F loses -10+10.1267=+0.1267. Worst -0.0867: 2 ticks do not pay the commission at this price
assert abs(lock_back_hf(3.1,3.0)-(21*.98-(31/3)*2))<1e-9 and lock_back_hf(3.1,3.0)<0
# Backed 10 at 3.0, hedge lay at 2.5, +1.6 worked earlier
assert abs(lock_back_hf(3.0,2.5)-1.6)<1e-9
# Laid at 2.5 for liability 10 (stake 6.6667), back 6.6667*2.5/3=5.5556 at 3. F wins -10+11.1111*.98=+0.8889. F loses 6.5333-5.5556=+0.9778. Worst +0.8889
assert abs(lock_lay_hf(2.5,3.0)-(-10+(50/9)*2*.98))<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HM=pd.read_sql("SELECT event_name ev,sel,ts FROM liq_sample WHERE mkt='HT_MO' AND back_px<=1.2 AND lay_px<=1.2 ORDER BY ts",con)
HX=HM.groupby('ev').tail(1).set_index('ev'); print("games with an HT_MO winner row",len(HX),flush=True)
D=pd.read_sql("SELECT event_name ev,mkt,sel,ts,minute,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt=ANY(%s) AND minute>=52",con,params=(['HTFT','MO'],)); con.close()
print("rows",len(D),f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); F=[]; offered=Counter()
for ev,g in D.groupby('ev',sort=False):
    if ev not in HX.index or ' v ' not in ev: C['no X']+=1; continue
    g=g[g.ts>HX.loc[ev,'ts']]
    hf=g[g.mkt=='HTFT']; mo=g[g.mkt=='MO'].drop_duplicates(['ts','sel'],keep=False)
    if hf.empty or mo.empty: C['no rows']+=1; continue
    names={p for s in hf.sel.unique() for p in s.split('/') if '/' in s}
    xn=x_name(HX.loc[ev,'sel'],names)
    if xn is None: C['X unmapped']+=1; continue
    C['games']+=1
    M={s:y.sort_values('ts') for s,y in mo.groupby('sel')}
    for sel,y in hf.groupby('sel'):
        pp=sel.split('/')
        if len(pp)!=2 or pp[0]!=xn: continue
        s=side_of(pp[1],ev)
        if s is None or s not in M: C['F unmapped']+=1; continue
        y=y.sort_values('ts').drop_duplicates('ts'); m=M[s]
        J=y.merge(m[['ts','b','l']].rename(columns=dict(b='mb',l='ml')),on='ts')
        if len(J)<2: continue
        done=set()
        t=(J.ts.values-J.ts.values[0])/np.timedelta64(1,'s')
        for i in range(len(J)-1):
            r=J.iloc[i]; n=J.iloc[i+1]
            if t[i+1]-t[i]>120: continue
            if any(pd.isna(v) for v in (r.b,r.l,r.mb,r.ml)): continue
            for k in (2,4):
                for kindq,q in (('LAYQ',quote_lay(r.mb,r.b,r.l,k)),('BACKQ',quote_back(r.ml,r.b,r.l,k))):
                    if q is None or (kindq,k) in done: continue
                    offered[(kindq,k)]+=1
                    if pd.isna(n.ltp) or n.ltp==r.ltp: continue
                    filled=(n.ltp<q) if kindq=='LAYQ' else (n.ltp>q)
                    if not filled: continue
                    done.add((kindq,k))
                    hedge=n.mb if kindq=='LAYQ' else n.ml
                    if pd.isna(hedge): v=-10.0; C['no hedge book']+=1
                    else: v=lock_lay_hf(q,float(hedge)) if kindq=='LAYQ' else lock_back_hf(q,float(hedge))
                    base=r.mb if kindq=='LAYQ' else r.ml
                    F.append((kindq,k,ev,sel,r.ts,int(n.minute),q,float(n.ltp),float(base),None if pd.isna(hedge) else float(hedge),float(v)))
print("counts",dict(C),"offered snapshots",{f"{a} K{b}":v for (a,b),v in offered.items()},flush=True)
T=pd.DataFrame(F,columns=['q','k','ev','sel','ts','minute','level','print','mo0','mo1','v'])
if T.empty: print("no fills\nSURVIVORS\nnone"); sys.exit(0)
T['tt']=(pd.to_datetime(T.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); med=T.tt.median(); T['h']=np.where(T.tt<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),flush=True)
out=[]
for (q,k),x in T.groupby(['q','k']):
    d=line(x.v.values,x.h.values); v=x.v.values; tg=tgame(v,x.ev.values)
    sl=(100*(1/x.mo1-1/x.mo0)).abs().median()
    out.append(dict(line=f"{q} K{k}",n=d['n'],games=x.ev.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),tg=round(tg,2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3) if len(v)>1 else None,pos=round((v>0).mean(),3),worst=round(v.min(),2),hedge_slip=round(sl,2),PASS=bool(d['PASS'] and tg>=3.5)))
O=pd.DataFrame(out).sort_values('tg',ascending=False); print(O.to_string(index=False))
print("worst fills"); print(T.sort_values('v').head(6)[['q','k','ev','sel','minute','level','print','mo0','mo1','v']].round(3).to_string(index=False))
print("best fills"); print(T.sort_values('v').tail(6)[['q','k','ev','sel','minute','level','print','mo0','mo1','v']].round(3).to_string(index=False))
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
