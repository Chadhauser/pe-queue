#!/bin/bash
set -o pipefail
# 492 (Finder 2026-11-04, queue item 34): PASSIVE LAY ON PRE-MATCH DRIFTERS. stream_ticks football MO_PRE, pre-off, OPEN, whole table (rolling, range printed). Trigger as job 469.
# SIGNAL: back_px >= 3% longer than the standing book 15 min earlier (at most 300 s older). DRIFT3 = that; DRIFT3v = and the runner's volume in the last 15 min exceeds the 15 min before. CTRL = |move| < 3%, same fill rule. First signal per runner per time-to-KO band (5-30, 30-60, 60-105 min).
# ORDER: offer the lay at the current back_px, X, resting until the last pre-off tick. Unfilled = £0, reported.
# FILL, read literally: a resting lay at X joins the offers backers take at X. Backers take the highest offer first, so a print ABOVE X is someone else's better offer and does not fill it. Only a print strictly BELOW X proves everything at X has gone. So THROUGH = first later tick with ltp < X and the runner's volume up (a stale ltp is not a print). This fills only when the price shortens against the order. TOUCH = ltp <= X, assumes first in the queue, diagnostic only.
# COST: per10 takes one tick adverse at entry and exit (house rule), at_level enters at exactly X, diagnostic. Exit: last pre-off tick's back touch. £10 liability, 2% commission. Fill on the last tick itself exits on that book.
# Halves: median signal time. t per filled trade, tc clustered by game. ONE = first per market. per_sig = per10 x fill rate, unfilled at £0. mv_f / mv_u = log mid move from signal to KO, filled v unfilled, > 0 = shortened.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def dn(p): return float(LAD[max(int(np.searchsorted(LAD,round(p,2)-1e-9))-1,0)])
def up(p): return float(LAD[min(int(np.searchsorted(LAD,round(p,2)-1e-9))+1,len(LAD)-1)])
def comm(x): return x*0.98 if x>0 else x
def lay_trade(lp0,bp1):
    a=up(lp0); c=max(1.01,dn(bp1)); return comm(10/(a-1)*(1-a/c))
def lay_level(x0,bp1):
    c=max(1.01,dn(bp1)); return comm(10/(x0-1)*(1-x0/c))
def fill_at(ltp,tv,i,x0,mode):
    """First j > i with a fresh print (volume up on the previous tick) strictly below x0 (THROUGH) or at or below it (TOUCH). None if never."""
    for j in range(i+1,len(ltp)):
        if not tv[j]>tv[j-1] or not np.isfinite(ltp[j]): continue
        if ltp[j]<x0-1e-9 or (mode=='TOUCH' and ltp[j]<=x0+1e-9): return j
    return None
def pband(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(3.0)==3.05 and dn(6.0)==5.9
assert abs(lay_trade(5.0,6.0)-0.324101)<1e-6                                     # as job 469: lay 5.0 fills 5.1, out at 5.9: 10/4.1*(1-5.1/5.9)*0.98
assert abs(lay_level(5.0,6.0)-10/4*(1-5/5.9)*0.98)<1e-9                          # exact level: lay 5.0, out at 5.9
assert abs(lay_level(5.0,4.0)-10/4*(1-5/3.95))<1e-9                              # back out 4.0 fills 3.95 (step below 4 is 0.05): a loss, so no commission
L0=np.array([3.0,3.05,3.1,2.98]); V0=np.array([10.,20,30,40])
assert fill_at(L0,V0,0,3.0,'THROUGH')==3 and fill_at(L0,V0,0,3.0,'TOUCH')==3     # 3.05 and 3.10 are above X, no fill; 2.98 is through
assert fill_at(np.array([3.0,3.0,2.98]),np.array([10.,20,30]),0,3.0,'TOUCH')==1 and fill_at(np.array([3.0,3.0,2.98]),np.array([10.,20,30]),0,3.0,'THROUGH')==2
assert fill_at(np.array([3.0,2.98,2.98]),np.array([10.,10,10]),0,3.0,'THROUGH') is None   # price below X but volume flat: a stale ltp, not a print
assert fill_at(np.array([3.0,3.1]),np.array([10.,20]),0,3.0,'THROUGH') is None
assert pband(1.99)=='<2' and pband(2.0)=='2-3' and pband(10.0)=='10+' and abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); r0=cur.fetchone(); print("stream_ticks range:",r0[0],"..",r0[1],flush=True)
t0=time.time(); parts=[]
for a in pd.date_range(pd.Timestamp(r0[0]).floor('6h'),pd.Timestamp(r0[1]),freq='6h'):
    cur.execute("""SELECT market_id,sel_id,extract(epoch from ts_recv)::float8,secs_to_off,back_px::float8,lay_px::float8,ltp::float8,tv::float8 FROM stream_ticks
      WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND mkt='MO_PRE' AND inplay=false AND status='OPEN'""",(a,a+pd.Timedelta(hours=6)))
    parts.append(pd.DataFrame(cur.fetchall(),columns=['mid','sid','ts','sto','bp','lp','ltp','tv']))
    print(f"  chunk {a}: {len(parts[-1])} ticks ({int(time.time()-t0)}s)",flush=True)
T=pd.concat(parts,ignore_index=True); n_all=len(T)
T=T.dropna(subset=['bp','lp','sto']); T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)].sort_values(['mid','sid','ts'],kind='stable')
print(f"ticks {n_all}, usable {len(T)}, markets {T.mid.nunique()}, runners {T.groupby(['mid','sid']).ngroups}, ltp null {T.ltp.isna().mean():.1%}",flush=True)
BANDS=((300,1800,'05-30'),(1800,3600,'30-60'),(3600,6300,'60-105'))
rows=[]
for (mid,sid),g in T.groupby(['mid','sid'],sort=False):
    if len(g)<3: continue
    ts=g.ts.values; sto=g.sto.values.astype(float); bp=g.bp.values; lp=g.lp.values; ltp=g.ltp.values
    tv=pd.Series(g.tv.values).where(lambda s:s>0).ffill().values
    j=np.searchsorted(ts,ts-900,side='right')-1; k=np.searchsorted(ts,ts-1800,side='right')-1
    okj=(j>=0)&((ts-900-ts[np.maximum(j,0)])<=300); okk=(k>=0)&((ts-1800-ts[np.maximum(k,0)])<=300)
    mv=np.where(okj,bp/bp[np.maximum(j,0)]-1,np.nan)
    vr=np.where(okj&okk,(tv-tv[np.maximum(j,0)])>(tv[np.maximum(j,0)]-tv[np.maximum(k,0)]),False)&(tv-tv[np.maximum(j,0)]>0)
    last=len(ts)-1
    for lo,hi,tb in BANDS:
        inb=(sto>=lo)&(sto<hi)&okj
        for sig,mask in (('DRIFT3',mv>=0.03),('DRIFT3v',(mv>=0.03)&vr),('CTRL',np.abs(mv)<0.03)):
            c=np.where(inb&mask)[0]
            if not len(c): continue
            i=int(c[0]); X=bp[i]
            if X<=1.01: continue
            mv_ko=np.log(((bp[i]+lp[i])/2)/((bp[last]+lp[last])/2))
            for mode in ('THROUGH','TOUCH'):
                f=fill_at(ltp,tv,i,X,mode)
                rows.append(dict(mid=mid,sid=sid,ts=ts[i],sig=sig,mode=mode,ttk=tb,band=pband(X),filled=f is not None,mv=mv_ko,
                    pnl=lay_trade(X,bp[last]) if f is not None else np.nan,at_level=lay_level(X,bp[last]) if f is not None else np.nan,wait=(ts[f]-ts[i])/60 if f is not None else np.nan))
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone (no signals)"); sys.exit()
med=R.ts.median(); R['h2']=R.ts>=med; print(f"signals {len(R)//2} | markets {R.mid.nunique()} | half split at {pd.Timestamp(med,unit='s',tz='UTC')}",flush=True)
def cell(name,x):
    f=x[x.filled]; a=f[~f.h2].pnl; b=f[f.h2].pnl; u=x[~x.filled]
    return dict(cell=name,signals=len(x),fill=x.filled.mean(),n=len(f),games=f.mid.nunique(),per10=f.pnl.mean(),t=tstat(f.pnl),tc=tstat(f.groupby('mid').pnl.mean()),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
        per_sig=f.pnl.sum()/max(len(x),1),at_level=f.at_level.mean(),mv_f=f.mv.mean(),mv_u=u.mv.mean(),wait=f.wait.median())
out=[]
for (sig,mode),x in R.groupby(['sig','mode']):
    out.append(dict(mode=mode,**cell(sig,x)))
    out.append(dict(mode=mode,**cell(sig+' ONE',x.sort_values('ts').drop_duplicates('mid'))))
    for dim in ('band','ttk'):
        for v,d in x.groupby(dim): out.append(dict(mode=mode,**cell(f"{sig} {dim} {v}",d)))
S=pd.DataFrame(out)
S['PASS']=(S['mode']=='THROUGH')&(~S.cell.str.startswith('CTRL'))&(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== THROUGH: the eligible fill\n",S[S['mode']=='THROUGH'].drop(columns=['mode','PASS']).round(3).to_string(index=False))
print("\n== TOUCH: first in the queue, diagnostic, headline cells\n",S[(S['mode']=='TOUCH')&(S.cell.isin(['DRIFT3','DRIFT3v','CTRL','DRIFT3 ONE','DRIFT3v ONE']))].drop(columns=['mode','PASS']).round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {int(((S['mode']=='THROUGH')&(~S.cell.str.startswith('CTRL'))).sum())} eligible lines"); print(W.drop(columns=['mode','PASS']).round(3).to_string(index=False) if len(W) else "none")
PY
