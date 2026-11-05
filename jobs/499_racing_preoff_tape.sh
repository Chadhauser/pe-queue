#!/bin/bash
set -o pipefail
# 499_racing_preoff_tape (Finder 2026-11-05, queue items 169, 170; from jobs/499_greyhound_momentum.sh): horses on the two-year BASIC tape, rules as written in the queue before prices were read (commit 0820fac).
# 169: follow or fade a pre-off move, closed before the off. The signal print is never the entry print, so back/lay bounce cannot make the signal. Entry is the runner's last print: settle at win_lose, else charge -10, counted.
# 170: last print T-5 to T-1 to BSP. House rule charges one tick at the BSP exit; the no-tick figure is context. Equal-profit greening at BSP cannot be sized in advance, so 170's figures are a mean, an upper bound on what a real order gets.
# TAPE: last-traded prints only, no book, so any pass is an upper bound and earns a real-touch test, not a stake. Local DB. Read-only. No secrets printed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,random,math,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,net,line,back_hedge,lay_hedge,back_settle,lay_settle
from lib_official import fill,last_in,checks
checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2400; M=60.0
WIN={'EARLY':(-45,-20,-15,-10,-5),'LATE':(-20,-10,-8,-5,-3)}
BANDS=('<3','3-6','6-12','12-20')
def band(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else '12-20' if p<=20 else None
def cls(r): return 'SHORT' if r<=0.90+1e-9 else 'DRIFT' if r>=1.10-1e-9 else 'FLAT' if 0.98-1e-9<=r<=1.02+1e-9 else None
def dir170(r): return 'SHORT' if r<=0.95+1e-9 else 'DRIFT' if r>=1.05-1e-9 else 'FLAT'
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def sig169(ts,px,T,w):
    """(ratio, entry index) from one runner's pre-off prints, or None. ts in seconds, T the scheduled off."""
    a,b,c,d,e=[T+x*M for x in WIN[w]]
    i=last_in(ts,a,b); j=last_in(ts,c,d)
    if i is None or j is None: return None
    k=j+1
    if k>=len(ts) or ts[k]>e: return None
    return float(px[j]/px[i]),k
def trade169(ts,px,k,side,won):
    """Value of a trade entered at index k. side B or L. Returns (value, closed before the off?) or (None, ...) if unpriceable."""
    f=fill(ts,px,k,side); last=k==len(ts)-1; q=float(px[-1])
    if side=='B':
        a=step(f,-1)
        if a<=1.01: return None,not last
        if last: return (back_settle(a,won) if won is not None else -10.0),False
        return back_hedge(a,q),True
    a=step(f,1)
    if last: return (lay_settle(a,won) if won is not None else -10.0),False
    return lay_hedge(a,q),True
def bsp_pl(side,x,bsp,tick=True):
    """Entry at print x one tick adverse, exit at BSP, one tick adverse if tick."""
    if side=='B':
        a=step(x,-1)
        if a<=1.01: return None
        return back_hedge(a,bsp) if tick else net(10*(a/bsp-1))
    a=step(x,1)
    return lay_hedge(a,bsp) if tick else net(10/(a-1)*(1-a/bsp))
# known answers, worked by hand
assert band(2.99)=='<3' and band(3.0)=='3-6' and band(6.0)=='6-12' and band(12.0)=='12-20' and band(20.0)=='12-20' and band(20.5) is None
assert cls(0.90)=='SHORT' and cls(0.91) is None and cls(1.10)=='DRIFT' and cls(1.09) is None and cls(1.0)=='FLAT' and cls(1.02)=='FLAT' and cls(0.97) is None
assert dir170(0.95)=='SHORT' and dir170(1.05)=='DRIFT' and dir170(1.0)=='FLAT'
_T=100000.0; _ts=np.array([_T-30*M,_T-12*M,_T-8*M,_T-2*M]); _px=np.array([5.0,4.5,4.6,4.0])
_s=sig169(_ts,_px,_T,'EARLY'); assert abs(_s[0]-0.9)<1e-9 and _s[1]==2           # 4.5/5.0, entry is the next print, not the signal
assert sig169(_ts[:2],_px[:2],_T,'EARLY') is None                                 # no print after the signal: no trade
assert sig169(np.array([_T-30*M,_T-12*M,_T-4*M]),np.array([5.,4.5,4.6]),_T,'EARLY') is None   # next print after the T-5 limit: no forward-fill
assert sig169(np.array([_T-12*M,_T-8*M]),np.array([4.5,4.6]),_T,'EARLY') is None  # no reference print: no trade
# back: print 4.6, next print is 6 minutes on so no fill move, 4.5 after a tick; out at 4.0 + tick = 4.1: 10*(4.5/4.1-1)=0.97561, less 2% = 0.956098
_v,_c=trade169(_ts,_px,2,'B',None); assert _c and abs(_v-0.956098)<1e-5
# lay: 4.6 + tick = 4.7, s=10/3.7, out at 4.0 - tick = 3.95: s*(1-4.7/3.95) = -0.513171... no commission on a loss
_v,_c=trade169(_ts,_px,2,'L',None); assert _c and abs(_v-(10/3.7*(1-4.7/3.95)))<1e-9 and _v<0
# entry is the last print: result, or -10 when the result is unknown; never dropped
_v,_c=trade169(_ts,_px,3,'B',True); assert not _c and abs(_v-10*(3.95-1)*0.98)<1e-9
_v,_c=trade169(_ts,_px,3,'B',False); assert _v==-10.0
_v,_c=trade169(_ts,_px,3,'B',None); assert _v==-10.0 and not _c
_v,_c=trade169(_ts,_px,3,'L',None); assert _v==-10.0
_v,_c=trade169(_ts,_px,3,'L',False); assert abs(_v-10/(4.1-1)*0.98)<1e-9
assert abs(bsp_pl('B',5.0,4.0)-net(10*(4.9/4.1-1)))<1e-9 and abs(bsp_pl('B',5.0,4.0,False)-net(10*(4.9/4.0-1)))<1e-9
assert abs(bsp_pl('L',5.0,6.0,False)-net(10/4.1*(1-5.1/6.0)))<1e-9 and bsp_pl('B',1.02,1.5) is None
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT event_dt,selection_name,bsp::float8,win_lose FROM racing_bsp WHERE market='win' AND event_dt>='2024-08-30' AND bsp>1")
BS=defaultdict(list)
for dt,nm,b,w in cur.fetchall(): BS[(dt.date().isoformat(),fold(nm))].append((dt,b,w))
print(f"racing_bsp win runner-days {len(BS)}; same name twice in a day {sum(len(v)>1 for v in BS.values())}, not used | {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id,market_time FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
MK=cur.fetchall(); random.Random(169).shuffle(MK); print(f"GB and IE WIN markets {len(MK)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); A=[]; B=[]; OFFS=Counter(); DONE=0
for c_ in range(0,len(MK),400):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; break
    ids=[m[0] for m in MK[c_:c_+400]]; DONE+=len(ids)
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Horse Racing' AND market_id=ANY(%s) AND market_type='WIN' AND NOT inplay AND ts>=market_time-interval '46 minutes' AND ltp>=1.01 AND ltp<1000""",(ids,))
    d=pd.DataFrame(cur.fetchall(),columns='m T sel ts p'.split())
    if d.empty: continue
    d=d.drop_duplicates(['m','sel','ts']).sort_values(['m','sel','ts'],kind='stable')
    for mk,g in d.groupby('m',sort=False):
        T=float(g['T'].iloc[0]); day=pd.Timestamp(T,unit='s',tz='UTC'); dk=day.date().isoformat(); R={}
        for s,x in g.groupby('sel',sort=False):
            rec=BS.get((dk,fold(s)))
            if rec and len(rec)==1:
                off=abs((rec[0][0]-day.tz_localize(None).to_pydatetime()).total_seconds())/3600
                OFFS[round(off,0)]+=1
                rec=rec[0] if off<=2.01 else None
            else: rec=None
            R[s]=(x.ts.values,x.p.values,rec)
        SK['markets with pre-off prints']+=1
        # ---- 169
        for w in WIN:
            cand=[]
            for s,(ts,px,rec) in R.items():
                z=sig169(ts,px,T,w)
                if z is None: continue
                r,k=z; c=cls(r); bd=band(float(px[k]))
                if c is None or bd is None: continue
                cand.append((c,bd,abs(math.log(r)),s,k))
            for c in ('SHORT','DRIFT','FLAT'):
                cc=[x for x in cand if x[0]==c]
                for bd in BANDS+('ALL',):
                    y=[x for x in cc if bd=='ALL' or x[1]==bd]
                    if not y: continue
                    x=sorted(y,key=lambda v:(-v[2],v[3]))[0]; ts,px,rec=R[x[3]]; k=x[4]; won=None if rec is None else bool(rec[2])
                    for side in 'BL':
                        v,closed=trade169(ts,px,k,side,won)
                        if v is None: SK['169 bottom of ladder']+=1; continue
                        if not closed: SK[f'169 entry was last print, result {"known" if won is not None else "charged -10"}']+=1
                        A.append((w,c,bd,side,T,mk,v,closed,float(px[k])))
        # ---- 170
        cand=[]
        for s,(ts,px,rec) in R.items():
            i=last_in(ts,T-5*M,T-1*M)
            if i is None: continue
            bd=band(float(px[i]))
            if bd is None: continue
            if rec is None: SK['170 no BSP']+=1; continue
            j=last_in(ts,T-20*M,T-10*M); cand.append((s,float(px[i]),bd,None if j is None else dir170(float(px[i]/px[j])),rec[1]))
        for ddd in ('ANY','SHORT','DRIFT','FLAT'):
            cc=[x for x in cand if ddd=='ANY' or x[3]==ddd]
            for bd in BANDS+('ALL',):
                y=[x for x in cc if bd=='ALL' or x[2]==bd]
                if not y: continue
                x=sorted(y,key=lambda v:(v[1],v[0]))[0]
                for side in 'BL':
                    v=bsp_pl(side,x[1],x[4]); g0=bsp_pl(side,x[1],x[4],False)
                    if v is None: continue
                    B.append((ddd,bd,side,T,mk,v,g0,x[1],x[4]))
    if (c_//400)%10==0: print(f"  {DONE}/{len(MK)} markets, A {len(A)} B {len(B)} | {time.time()-T0:.0f}s",flush=True)
con.close()
print(f"markets read {DONE} of {len(MK)}; counts {dict(sorted(SK.items()))}\nhours between tape off and racing_bsp event_dt, on name-day matches: {sorted(OFFS.items())[:6]}",flush=True)
def table(D,keys,val='v'):
    out=[]
    for kk,x in D.groupby(keys):
        md=np.median(x['T'].values); l=line(x[val].values,np.where(x['T'].values<md,1,2)); kk=kk if isinstance(kk,tuple) else (kk,)
        s=x['T'].values<pd.Timestamp('2025-09-01',tz='UTC').timestamp()
        out.append(dict(zip(keys,kk))|dict(n=l['n'],races=x.m.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],s24=x[val].values[s].mean() if s.any() else np.nan,s25=x[val].values[~s].mean() if (~s).any() else np.nan,PASS=l['PASS']))
    return pd.DataFrame(out).sort_values('t',ascending=False)
A=pd.DataFrame(A,columns='w c bd side T m v closed px'.split()); B=pd.DataFrame(B,columns='d bd side T m v g0 px bsp'.split())
if A.empty or B.empty: print("ERROR: no trades, no verdict"); sys.exit(1)
A['rule']=np.where(A.c=='FLAT','CTRL_'+A.side,np.where((A.c=='SHORT')==(A.side=='B'),'FOLLOW','FADE'))
TA=table(A,['w','c','bd','rule'])
_o=A[~A.closed].groupby(['w','c','bd','rule']).size(); TA['last_print']=[int(_o.get((r.w,r.c,r.bd,r.rule),0)) for r in TA.itertuples()]
print("\n== 169 CONTROL (FLAT, not gated)\n",TA[TA.c=='FLAT'].round(3).to_string(index=False))
G=TA[TA.c!='FLAT']; print(f"\n== 169 GATED {len(G)} lines, per £10, by t\n",G.round(3).to_string(index=False),flush=True)
TB=table(B,['d','bd','side']); TB0=table(B,['d','bd','side'],'g0').set_index(['d','bd','side'])
TB['per10_notick']=[TB0.loc[(r.d,r.bd,r.side),'per10'] for r in TB.itertuples()]
print(f"\n== 170 GATED {len(TB)} lines, per £10, by t; no-tick exit is context\n",TB.round(3).to_string(index=False),flush=True)
print("\n== 170 calibration: favourite print v BSP, mean log(BSP/print)",round(float(np.log(B[(B.d=='ANY')&(B.bd=='ALL')&(B.side=='B')].bsp/B[(B.d=='ANY')&(B.bd=='ALL')&(B.side=='B')].px).mean()),4))
SV=pd.concat([G[G.PASS].assign(item=169),TB[TB.PASS].assign(item=170)])
print(f"\n== SURVIVORS: {len(SV)} of {len(G)+len(TB)}\n",SV.round(3).to_string(index=False) if len(SV) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
