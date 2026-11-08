#!/bin/bash
set -o pipefail
# 499_bsp_loc_unseen (Finder 2026-11-08, queue item 469; item 468's code, jobs/499_bsp_loc.sh, with one change): BSP and win_lose from Railway bfsp_history (read only),
# scored ONLY on tape runners with no racing_bsp row, the runners item 468 could not price. Primary line LAY k=1.25 ALL, fixed before prices; the rest printed for reading.
# 468's header, unchanged rules:
# p = runner's last pre-off print T-5 to T-1 min. BACK LOC fills iff BSP >= k*p, LAY LOC fills iff BSP <= p/k (k=1.0 strict). Entry at BSP one tick adverse (house rule), held to win_lose.
# Full fill assumed at BSP: a LOC with its limit at the BSP can part-fill, so any pass is an upper bound and earns a forward paper test, not a stake.
# Several runners a race can fill, so t is read per trade and per race (race sums); the gate uses the smaller. Local DB. Read-only. No secrets printed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,math,datetime,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,net,back_settle,lay_settle,tstat,passes
from lib_official import last_in,checks
checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2700; M=60.0
BANDS=('<3','3-6','6-12','12-20','20-50')
KS=(1.0,1.1,1.25)
def band(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else '12-20' if p<20 else '20-50' if p<=50 else None
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def fills(side,k,p,bsp):
    if k==0: return True
    if side=='B': return bsp>p if k==1.0 else bsp>=k*p-1e-9
    return bsp<p if k==1.0 else bsp<=p/k+1e-9
def pl(side,bsp,won):
    if side=='B':
        a=step(bsp,-1)
        return None if a<=1.01 else back_settle(a,won)
    return lay_settle(step(bsp,1),won)
def tline(v,h,race):
    v=np.asarray(v,float); h=np.asarray(h); n=len(v); n1=int((h==1).sum()); n2=n-n1
    m=v.mean() if n else np.nan; t=tstat(v) if n>2 else np.nan
    rs=pd.Series(v).groupby(np.asarray(race)).sum().values; tr=tstat(rs) if len(rs)>2 else np.nan
    h1=v[h==1].mean() if n1 else np.nan; h2=v[h==2].mean() if n2 else np.nan
    tg=np.nanmin([t,tr]) if n>2 else np.nan
    return dict(n=n,races=len(rs),per10=m,t=t,t_race=tr,h1=h1,h2=h2,n1=n1,n2=n2,PASS=bool(n>2 and passes(n,n1,n2,tg,h1,h2,m)))
# known answers, worked by hand
assert band(2.99)=='<3' and band(3.0)=='3-6' and band(19.9)=='12-20' and band(20.0)=='20-50' and band(50.0)=='20-50' and band(50.5) is None
assert fills('B',1.0,5.0,5.1) and not fills('B',1.0,5.0,5.0) and fills('B',1.1,5.0,5.5) and not fills('B',1.1,5.0,5.4) and fills('B',1.25,4.0,5.0)
assert fills('L',1.0,5.0,4.9) and not fills('L',1.0,5.0,5.0) and fills('L',1.25,5.0,4.0) and not fills('L',1.25,5.0,4.1) and fills('L',0,5.0,99)
# back at BSP 5.0: one tick adverse 4.9, win 10*3.9*0.98=38.22, lose -10
assert abs(pl('B',5.0,True)-38.22)<1e-9 and pl('B',5.0,False)==-10.0
# lay at BSP 5.0: 5.1, liability 10, stake 10/4.1, horse loses +10/4.1*0.98, wins -10
assert abs(pl('L',5.0,False)-10/4.1*0.98)<1e-9 and pl('L',5.0,True)==-10.0
assert pl('B',1.02,True) is None
assert abs(step(10.0,-1)-9.8)<1e-9 and abs(step(2.0,1)-2.02)<1e-9
_l=tline([1.,3.,-1.,5.],[1,1,2,2],[1,1,2,3]); assert _l['n']==4 and _l['races']==3 and _l['h1']==2.0 and _l['h2']==2.0 and not _l['PASS']
_ts=np.array([0.,100.,200.]); assert last_in(_ts,50,150)==1 and last_in(_ts,210,300) is None
assert datetime.datetime.strptime(' 28-02-2025 14:13'.strip(),'%d-%m-%Y %H:%M')==datetime.datetime(2025,2,28,14,13)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT event_dt,selection_name,bsp::float8,win_lose FROM racing_bsp WHERE market='win' AND event_dt>='2024-08-30' AND bsp>1")
BS=defaultdict(list)
for dt,nm,b,w in cur.fetchall(): BS[(dt.date().isoformat(),fold(nm))].append((dt,b,w))
print(f"racing_bsp win runner-days {len(BS)}; same name twice in a day {sum(len(v)>1 for v in BS.values())}, not used | {time.time()-T0:.0f}s",flush=True)
rc=psycopg2.connect(creds.pg_railway_remote(),connect_timeout=30); rcur=rc.cursor(); rcur.execute("SET statement_timeout='1500s'")
rcur.execute("SELECT event_dt,selection_name,bsp::float8,win_lose FROM bfsp_history WHERE market_type='win' AND race_date>='2024-08-30' AND bsp>1")
BS2=defaultdict(list); _bad=0
for dt,nm,b,w in rcur.fetchall():
    try: dt=datetime.datetime.strptime(dt.strip(),'%d-%m-%Y %H:%M')
    except Exception: _bad+=1; continue
    BS2[(dt.date().isoformat(),fold(nm))].append((dt,b,w))
rc.close()
print(f"bfsp_history win runner-days {len(BS2)}; unparsed event_dt {_bad}; same name twice in a day {sum(len(v)>1 for v in BS2.values())}, not used | {time.time()-T0:.0f}s",flush=True)
AGREE=Counter()
def match(BSx,dk,s,day):
    rec=BSx.get((dk,fold(s)))
    if not rec: return None,'none'
    if len(rec)>1: return None,'twice'
    dt,b,w=rec[0]
    if abs((dt-day.tz_localize(None).to_pydatetime()).total_seconds())>2*3600+60: return None,'far'
    if w is None: return None,'null'
    return (float(b),bool(int(w))),'ok'
cur.execute("SELECT DISTINCT market_id,market_time FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE')")
MK=sorted(cur.fetchall(),key=lambda r:r[1]); print(f"GB and IE WIN markets {len(MK)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); R=[]; DONE=0
for c_ in range(0,len(MK),500):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; break
    ids=[m[0] for m in MK[c_:c_+500]]; DONE+=len(ids)
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Horse Racing' AND market_id=ANY(%s) AND market_type='WIN' AND NOT inplay AND ts>=market_time-interval '5 minutes' AND ts<=market_time-interval '1 minute' AND ltp>=1.01 AND ltp<=1000""",(ids,))
    d=pd.DataFrame(cur.fetchall(),columns='m T sel ts p'.split())
    if d.empty: continue
    d=d.drop_duplicates(['m','sel','ts']).sort_values(['m','sel','ts'],kind='stable')
    for (mk,s),x in d.groupby(['m','sel'],sort=False):
        T=float(x['T'].iloc[0]); ts=x.ts.values; i=last_in(ts,T-5*M,T-1*M)
        if i is None: SK['no print T-5..T-1']+=1; continue
        p=float(x.p.values[i]); bd=band(p)
        if bd is None: SK['print over 50']+=1; continue
        day=pd.Timestamp(T,unit='s',tz='UTC'); dk=day.date().isoformat()
        r2,why2=match(BS2,dk,s,day)
        if BS.get((dk,fold(s))):           # a racing_bsp row exists: item 468's sample, SEEN, not scored here
            SK['SEEN (racing_bsp row), not scored']+=1
            r1,why1=match(BS,dk,s,day)
            if r1 and r2: AGREE['both priced']+=1; AGREE['BSP within 1%']+=abs(r1[0]/r2[0]-1)<=0.01; AGREE['win_lose same']+=r1[1]==r2[1]
            continue
        if r2 is None: SK[f'UNSEEN, bfsp_history {why2} (not priced)']+=1; continue
        SK['UNSEEN runners priced']+=1; R.append((mk,T,s,p,bd,r2[0],r2[1]))
    if (c_//500)%10==0: print(f"  {DONE}/{len(MK)} markets, runners {len(R)} | {time.time()-T0:.0f}s",flush=True)
con.close()
print(f"markets read {DONE} of {len(MK)}; counts {dict(sorted(SK.items()))}\nracing_bsp v bfsp_history on runners in both: {dict(AGREE)}",flush=True)
D=pd.DataFrame(R,columns='m T sel p bd bsp won'.split())
if D.empty: print("ERROR: no runners, no verdict"); sys.exit(1)
print(f"runners {len(D)} in {D.m.nunique()} races, {pd.Timestamp(D['T'].min(),unit='s').date()} to {pd.Timestamp(D['T'].max(),unit='s').date()}; mean log(BSP/p) {np.log(D.bsp/D.p).mean():.4f}; share BSP>p {(D.bsp>D.p).mean():.3f}, BSP<p {(D.bsp<D.p).mean():.3f}",flush=True)
md=np.median(D['T'].values); D['h']=np.where(D['T'].values<md,1,2)
rows=[]; CAL=[]
for side in 'BL':
    for k in (0,)+KS:
        F=D[[fills(side,k,p,b) for p,b in zip(D.p.values,D.bsp.values)]]
        for bd in BANDS+('ALL',):
            x=F if bd=='ALL' else F[F.bd==bd]
            v=[pl(side,b,w) for b,w in zip(x.bsp.values,x.won.values)]; ok=[vv is not None for vv in v]
            x=x[ok]; v=np.array([vv for vv in v if vv is not None],float)
            if len(v)<3: continue
            l=tline(v,x.h.values,x.m.values); s24=x['T'].values<pd.Timestamp('2025-09-01',tz='UTC').timestamp()
            rows.append(dict(side=side,k=k,bd=bd)|l|dict(won=x.won.mean(),impl=(1/x.bsp).mean(),s24=v[s24].mean() if s24.any() else np.nan,s25=v[~s24].mean() if (~s24).any() else np.nan))
T_=pd.DataFrame(rows)
if 'PASS' in T_: T_.loc[T_.k==0,'PASS']=False
print("\n== CONTROL k=0, every runner at BSP (not gated)\n",T_[T_.k==0].round(3).to_string(index=False))
G=T_[T_.k>0].sort_values('t',ascending=False)
print(f"\n== GATED {len(G)} lines, per £10, by t; won = win rate, impl = mean 1/BSP\n",G.round(3).to_string(index=False),flush=True)
PR=G[(G.side=='L')&(G.k==1.25)&(G.bd=='ALL')]
print("\n== PRIMARY (fixed before prices): LAY k=1.25 ALL on UNSEEN runners\n",PR.round(3).to_string(index=False))
SV=PR[PR.PASS]
print(f"\n== SURVIVORS (primary line only is gated): {len(SV)} of 1\n",SV.round(3).to_string(index=False) if len(SV) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
