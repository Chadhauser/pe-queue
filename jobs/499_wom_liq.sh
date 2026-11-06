#!/bin/bash
set -o pipefail
# 499_wom_liq (Finder 2026-11-06, queue items 194 and 196, source b Webb and source a volume): weight of money and matched-volume confirmation in play, football MO, liq_sample, real touch. Rules pushed before prices were read (queue commit 1105be6). The number 499 is reused: 450-499 are all taken.
# See DATA DEFECT below. Snapshots about 64 s apart. Entry at the NEXT snapshot, exit at the first two-sided snapshot H minutes after entry, one tick adverse each way, 2% on profit, £10 risk (lib_wom, lib_cand). Market gone before exit = settled from the last print, unresolved counted. MO does not settle early, so no line-passed case.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_wom import ticks,trade_h,table,two_sided
T0=time.time(); GAP=180
def imb_state(i):
    return 'BH' if i>=0.75 else 'LH' if i<=0.25 else 'CTRL' if 0.40<=i<=0.60 else None
assert [imb_state(x) for x in (0.75,0.25,0.5,0.7,0.6,0.4)]==['BH','LH','CTRL',None,'CTRL','CTRL']
def windows(m,lo): return ((m>=lo)&(m<=40))|((m>=50)&(m<=75))
assert windows(np.array([4,5,40,41,50,75,76]),5).tolist()==[False,True,True,False,True,True,False]
def vol_class(dv5,base,mv):
    v='SURGE' if dv5>=3*base and dv5>=500 else 'QUIET' if dv5<=base else None
    a=abs(mv); s='JUMP' if a>=0.15 else 'SMALL' if a>=0.03 else None
    return (v,s) if v and s else None
assert vol_class(1500,400,-.05)==('SURGE','SMALL') and vol_class(400,100,.05) is None and vol_class(100,100,.2)==('QUIET','JUMP') and vol_class(1500,400,.01) is None
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("""SELECT extract(epoch from ts)::float8 t,market_id,event_name ev,sel,minute::float8 m,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp,back_sz::float8 bs,lay_sz::float8 ls,back3_sz::float8 b3,lay3_sz::float8 l3,total_matched::float8 tm
 FROM liq_sample WHERE mkt='MO'""",con); con.close()
# DATA DEFECT found 2026-11-06 by a re-run that did not reproduce: exact duplicate rows, and markets whose home runner is recorded as a second AWAY, so ties sorted at random and two runners were mixed. Duplicates dropped; those markets dropped whole, as the runner cannot be told. Sort is fully determined.
_n=len(D); D=D.drop_duplicates(); _x=D[D.duplicated(['market_id','sel','t'],keep=False)].market_id.unique()
print(f"data: exact duplicates dropped {_n-len(D)}, markets dropped for two runners under one label {len(_x)} ({D.market_id.isin(_x).sum()} rows)",flush=True)
D=D[~D.market_id.isin(_x)].sort_values(['market_id','sel','t'],kind='mergesort')
print(f"MO rows {len(D):,}, markets {D.market_id.nunique():,}, games {D.ev.nunique():,}, {pd.to_datetime(D.t.min(),unit='s')}..{pd.to_datetime(D.t.max(),unit='s')}; b3>=bs on {(D.b3>=D.bs-1e-6).mean():.3f} of rows, read as a 3-level sum, not proven",flush=True)
S=Counter(); WOM=[]; VOL=[]
for (mk,sel),x in D.groupby(['market_id','sel'],sort=False):
    t,m,ltp,bp,lp,b3,l3,tm=[x[c].values for c in 't m ltp bp lp b3 l3 tm'.split()]; ev=x.ev.iloc[0]; n=len(t)
    if n<5: S['short market']+=1; continue
    mid=(bp+lp)/2
    with np.errstate(invalid='ignore',divide='ignore'):
        book=(bp>=1.2)&(lp<=10)&(lp>bp)
        spr=np.where(book,ticks(np.where(book,bp,2.0),np.where(book,lp,2.0)),99)<=4
        ok=book&spr
        imb=b3/(b3+l3)
        stable=np.r_[False,(np.abs(mid[1:]/mid[:-1]-1)<=0.05)&((t[1:]-t[:-1])<=GAP)]
    base=ok&stable&((b3+l3)>=100)&windows(m,5)
    # item 194
    seen=set()
    for i in np.where(base)[0]:
        st=imb_state(imb[i])
        if st is None: continue
        for pers in (1,3):
            if (st,pers) in seen: continue
            if pers==3 and not (i>=2 and t[i]-t[i-2]<=2*GAP and imb_state(imb[i-1])==st and imb_state(imb[i-2])==st and ok[i-1] and ok[i-2]): continue
            seen.add((st,pers)); k=i+1; S['194 signal']+=1
            if k>=n or t[k]-t[i]>GAP or not ok[k]: S['194 no entry']+=1; continue
            band='<2.5' if bp[i]<2.5 else '2.5-10'
            for side in ('back','lay'):
                for H in (2,5,10):
                    p,e,how,w=trade_h(side,t,bp,lp,ltp,k,H); S['194 '+how]+=1; S['194 wide exit']+=w
                    if p is not None: WOM.append((st,pers,side,H,band,p,e,ev,t[k]))
    # item 196
    seen=set(); gate=ok&windows(m,15)
    for i in np.where(gate)[0]:
        if i<20 or not ok[i-5] or t[i]-t[i-5]>5*GAP/2 or t[i-5]-t[i-20]>15*GAP/2: continue
        dv5=tm[i]-tm[i-5]; base15=(tm[i-5]-tm[i-20])/3; mv=np.log(mid[i]/mid[i-5])
        if not (dv5==dv5 and base15==base15 and mv==mv): continue
        c=vol_class(dv5,base15,mv)
        if c is None or c in seen: continue
        seen.add(c); k=i+1; S['196 signal']+=1
        if k>=n or t[k]-t[i]>GAP or not ok[k]: S['196 no entry']+=1; continue
        band='<2.5' if bp[i]<2.5 else '2.5-10'; fol='back' if mv<0 else 'lay'      # mid fell = shortened
        for how_,side in (('follow',fol),('fade','lay' if fol=='back' else 'back')):
            for H in (5,10):
                p,e,how,w=trade_h(side,t,bp,lp,ltp,k,H); S['196 '+how]+=1; S['196 wide exit']+=w
                if p is not None: VOL.append((c[0],c[1],how_,H,band,p,e,ev,t[k]))
print("counts",dict(sorted(S.items())),flush=True)
R=pd.DataFrame(WOM,columns='state pers side H band pnl exact ev ts'.split())
P1=table(R,['state','pers','side','H','band'],'ITEM 194 weight of money, football MO in play',control=('state','CTRL'))
V=pd.DataFrame(VOL,columns='vol size how H band pnl exact ev ts'.split())
P2=table(V,['vol','size','how','H','band'],'ITEM 196 matched volume and the move, football MO in play')
print("\n== SURVIVORS (n >= 300, 150 per half, t >= 3.5, both halves > 0, mean >= +0.15; t counts up to 3 runners a game, see tg)")
for nm,P in (('194',P1),('196',P2)):
    print(nm,'none' if P.empty else P.round(3).to_string(index=False))
print(f"total {time.time()-T0:.0f}s")
PY
