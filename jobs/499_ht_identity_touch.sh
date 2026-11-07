#!/bin/bash
set -o pipefail
# 499_ht_identity_touch (Finder 2026-11-07, queue item 411, pilot, from item 407): X/F on HT/FT v F on MO at the real touch after half-time. Read only, no tables written. About 2 days of tape, so it reads cost and locks, not a verdict.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',100)
def lock_back_hf(b,l,stake=10.0):
    """Back stake at b on HT/FT, lay stake*b/l at l on MO. Returns worst outcome after 2% on the winning market only."""
    s2=stake*b/l
    f_wins=stake*(b-1)*.98-s2*(l-1)
    f_loses=-stake+s2*.98
    return min(f_wins,f_loses)
def lock_lay_hf(l,b,stake=10.0):
    """Lay stake at l on HT/FT, back stake*l/b at b on MO. Same bet, other way round."""
    s2=stake*l/b
    f_wins=-stake*(l-1)+s2*(b-1)*.98
    f_loses=stake*.98-s2
    return min(f_wins,f_loses)
def spread_pts(b,l): return 100*(1/b-1/l)
def side_of(name,ev):
    """F as written on HT/FT to the MO runner. None when the name is in neither side or both."""
    if name=='DRAW': return 'DRAW'
    h,a=[x.upper() for x in ev.split(' v ',1)]
    H,A=name in h,name in a
    return 'HOME' if H and not A else 'AWAY' if A and not H else None
def x_name(xs,names):
    """HT_MO winner as written on HT/FT. HT_MO holds team names or THE DRAW. None unless exactly one name fits."""
    if xs=='THE DRAW': return 'DRAW' if 'DRAW' in names else None
    fit=[n for n in names if n!='DRAW' and (n in xs or xs in n)]
    return fit[0] if len(fit)==1 else None
assert x_name('THE DRAW',{'DRAW','A','B'})=='DRAW' and x_name('LAMPHUN WARRIOR',{'DRAW','LAMPHUN','SUKHOTHAI'})=='LAMPHUN' and x_name('Z',{'DRAW','A'}) is None and x_name('AB',{'DRAW','A','B'}) is None
# known answers, worked by hand
# Back 10 at 3.0, lay 10*3/2.5=12 at 2.5. F wins: 20*.98=19.6 less 12*1.5=18 is +1.6. F loses: -10 + 12*.98=11.76 is +1.76. Worst +1.6.
assert abs(lock_back_hf(3.0,2.5)-1.6)<1e-9
# Back 3.0, lay 3.0: F wins 19.6-20=-0.4. F loses -10+9.8=-0.2. Worst -0.4, no lock.
assert abs(lock_back_hf(3.0,3.0)+0.4)<1e-9
# Lay 10 at 2.5, back 10*2.5/3=8.3333 at 3. F wins: -15 + 16.6667*.98=16.3333 is +1.3333. F loses: 9.8-8.3333=+1.4667. Worst +1.3333.
assert abs(lock_lay_hf(2.5,3.0)-(-15+(25/3)*2*.98))<1e-9 and lock_lay_hf(2.5,3.0)>1.3
assert abs(spread_pts(2.0,2.5)-10)<1e-9
assert side_of('DRAW','A v B')=='DRAW' and side_of('LAMPHUN','Lamphun Warrior v Sukhothai')=='HOME' and side_of('SUKHOTHAI','Lamphun Warrior v Sukhothai')=='AWAY' and side_of('X','Lamphun v Sukhothai') is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HM=pd.read_sql("SELECT event_name ev,sel,ts,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt='HT_MO' AND back_px<=1.2 AND lay_px<=1.2 ORDER BY ts",con)
HX=HM.groupby('ev').tail(1).set_index('ev'); print("games with an HT_MO winner row",len(HX),flush=True)
Q="SELECT event_name ev,mkt,sel,ts,minute,back_px::float8 b,lay_px::float8 l,back_sz::float8 bs,lay_sz::float8 ls FROM liq_sample WHERE mkt=ANY(%s) AND minute>=52 AND back_px IS NOT NULL AND lay_px IS NOT NULL"
D=pd.read_sql(Q,con,params=(['HTFT','MO'],)); con.close(); print("rows",len(D),f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
for ev,g in D.groupby('ev',sort=False):
    if ev not in HX.index: C['no X']+=1; continue
    if ' v ' not in ev: C['no H v A']+=1; continue
    t0=HX.loc[ev,'ts']; xs=HX.loc[ev,'sel']; g=g[g.ts>t0]
    hf=g[g.mkt=='HTFT']; mo=g[g.mkt=='MO'].set_index(['ts','sel'])
    if hf.empty or mo.empty: C['no rows']+=1; continue
    C['games']+=1; names={p for s in hf.sel.unique() for p in s.split('/')}
    xn=x_name(xs,names)
    if xn is None: C['X name unmapped']+=1; continue
    for r in hf.itertuples():
        pp=r.sel.split('/')
        if len(pp)!=2 or pp[0]!=xn: continue
        s=side_of(pp[1],ev)
        if s is None: C['F unmapped']+=1; continue
        k=(r.ts,s)
        if k not in mo.index: C['no MO same ts']+=1; continue
        m=mo.loc[k]
        if isinstance(m,pd.DataFrame): C['MO duplicate']+=1; continue
        rows.append((ev,r.sel,r.ts,r.minute,r.b,r.l,r.bs,r.ls,float(m.b),float(m.l),float(m.bs),float(m.ls)))
print("counts",dict(C),flush=True)
T=pd.DataFrame(rows,columns=['ev','sel','ts','minute','hb','hl','hbs','hls','mb','ml','mbs','mls'])
if T.empty: print("no snapshots\nSURVIVORS\nnone"); sys.exit(0)
T['hs']=spread_pts(T.hb,T.hl); T['ms']=spread_pts(T.mb,T.ml)
print(f"snapshots {len(T):,}, games {T.ev.nunique()}")
print(f"spread points, HT/FT median {T.hs.median():.2f}, MO median {T.ms.median():.2f}")
print(f"lay within 5% of back: HT/FT {(T.hl<=T.hb*1.05).mean():.3f}, MO {(T.ml<=T.mb*1.05).mean():.3f}")
T['lock_b']=[lock_back_hf(b,l) for b,l in zip(T.hb,T.ml)]
T['lock_l']=[lock_lay_hf(l,b) for l,b in zip(T.hl,T.mb)]
T['sz_b']=np.minimum(T.hbs,T.mls); T['sz_l']=np.minimum(T.hls,T.mbs)
T=T.sort_values(['ev','sel','ts'])
for col,sz,lab in (('lock_b','sz_b','back HT/FT, lay MO'),('lock_l','sz_l','lay HT/FT, back MO')):
    T['nx']=T.groupby(['ev','sel'])[col].shift(-1)
    L=T[T[col]>0]
    print(f"\nLOCK {lab}: snapshots {len(L)}, games {L.ev.nunique()}")
    if len(L):
        print(f"  worst per £10 median {L[col].median():.3f}, size on the thinner side median £{L[sz].median():.2f}, next snapshot still locks {(L.nx>0).mean():.3f}")
        print(L[['ev','sel','minute','hb','hl','hbs','hls','mb','ml','mbs','mls',col]].head(8).round(3).to_string(index=False))
print("\nSURVIVORS: a pilot, no bar applies; none",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
