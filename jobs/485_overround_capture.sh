#!/bin/bash
set -o pipefail
# 485 (Finder 2026-11-04, queue item 31): OVERROUND CAPTURE. stream_ticks football MO_PRE, pre-off, whole rolling table (range printed).
# ENTRY ANCHOR: the item says T-120, but the feed starts at about T-2h, so few markets have a book that early. Anchor = last tick at or before T-115 min, no older than 300 s, per runner. No reading -> market not traded, counted.
# SIGNAL: overround = sum of 1/back_px over the three runners at the anchor >= 103% (102 and 105 reported alongside). Runner = widest back-lay gap in ladder ticks, gap >= 2 (a 1-tick book has nothing to close: counted, not traded). Ties: shorter price.
# BACK (the item): back at back_px -1 tick, £10 stake. Exit: first later tick with gap == 1 tick, lay out at lay_px +1 tick; else last tick at or before T-5 min, same; else own entry book. Reason logged.
# LAY (mirror, not in the item, for reading): lay at lay_px +1 tick, £10 liability; back out at back_px -1 tick under the same exit rule.
# CTRL: same trade, markets with overround < signal at the same anchor. Pre-off positions do not settle, nothing to settle at result. 2% commission on profit.
# One trade per market, so t is not inflated by repeat entries; each market is one game. Halves by kick-off date median. League from af_fixtures by runner names and start time; unmatched = 'unmatched', not dropped.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def ix(p): return int(np.searchsorted(LAD,round(float(p),2)-1e-9))
def dn(p): return float(LAD[max(ix(p)-1,0)])
def up(p): return float(LAD[min(ix(p)+1,len(LAD)-1)])
def gap(b,l): return ix(l)-ix(b)
def comm(x): return x*0.98 if x>0 else x
def back_trade(bp0,lp1):
    if bp0<=1.01: return None
    return comm(10*(dn(bp0)/up(lp1)-1))
def lay_trade(lp0,bp1):
    a=up(lp0); c=max(1.01,dn(bp1)); return comm(10/(a-1)*(1-a/c))
def anchor(sto,x,maxage=300):
    idx=np.where(sto>=x)[0]
    if len(idx)==0: return None
    i=idx[-1]
    return int(i) if sto[i]-x<=maxage else None
def overround(backs): return 100*sum(1/b for b in backs)
def exit_index(sto,bp,lp,i,tlast=300):
    """first later tick with a 1-tick book at or before T-5 min, else last tick at or before T-5 min, else the entry itself"""
    last=None
    for j in range(i+1,len(sto)):
        if sto[j]<tlast: break
        last=j
        if gap(bp[j],lp[j])==1: return j,'closed'
    return (last,'T-5') if last is not None else (i,'no_later')
def tstat(v):
    v=np.asarray(v,dtype=float)
    return float(v.mean()/(v.std(ddof=1)/np.sqrt(len(v)))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
# known answers, worked by hand
assert gap(2.0,2.02)==1 and gap(1.99,2.02)==2 and gap(2.9,3.05)==6 and gap(3.0,3.05)==1
assert abs(overround([2.0,4.0,4.0])-100.0)<1e-9 and abs(overround([1.9,3.8,3.8])-105.263158)<1e-5
assert abs(back_trade(5.0,4.0)-1.912195)<1e-6
assert abs(back_trade(2.0,2.02)+0.245098)<1e-6
assert abs(lay_trade(5.0,6.0)-0.324101)<1e-6
_st=np.array([6900.,6000.,5000.,400.,200.]); _b=np.array([2.0,2.0,2.0,2.0,2.0]); _l=np.array([2.1,2.06,2.02,2.04,2.02])
assert exit_index(_st,_b,_l,0)==(2,'closed')                                 # gap 5, 3, then 1 at the third tick
_l2=np.array([2.1,2.06,2.06,2.04,2.02])
assert exit_index(_st,_b,_l2,0)==(3,'T-5')                                   # the 1-tick book at T-3m20 is past the exit time
assert exit_index(np.array([6900.,200.]),np.array([2.0,2.0]),np.array([2.1,2.02]),0)==(0,'no_later')
assert anchor(np.array([7100.,6950.,6800.]),6900)==1 and anchor(np.array([7300.]),6900) is None
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0")   # first run died on DiskFull (Postgres shared memory) while running beside job 484
t0=time.time()
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); r=cur.fetchone(); print("stream_ticks range:",r[0],"..",r[1],flush=True)
parts=[]
for a in pd.date_range(pd.Timestamp(r[0]).floor('6h'),pd.Timestamp(r[1]),freq='6h'):
    cur.execute("""SELECT market_id,sel,extract(epoch from ts_recv)::float8,secs_to_off::float4,back_px::float4,lay_px::float4
      FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND mkt='MO_PRE' AND inplay=false AND status='OPEN' AND secs_to_off>=0""",(a,a+pd.Timedelta(hours=6)))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','sel','ts','sto','bp','lp']); parts.append(d)
    print(f"  chunk {a}: {len(d)} ticks ({int(time.time()-t0)}s)",flush=True)
T=pd.concat(parts,ignore_index=True); n_all=len(T)
T=T.dropna(subset=['bp','lp','sto']); T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)].sort_values(['mid','sel','ts'],kind='stable')
print(f"ticks {n_all}, usable touch {len(T)}, markets {T.mid.nunique()}, sto max {T.sto.max()}",flush=True)
F=pd.read_sql("SELECT league,kickoff,home,away FROM af_fixtures WHERE kickoff>=%s AND kickoff<=%s",con,params=(pd.Timestamp(r[0])-pd.Timedelta(days=1),pd.Timestamp(r[1])+pd.Timedelta(days=1)))
F['ko']=F.kickoff.map(lambda x:x.timestamp())
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b):
    A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
SK=Counter(); rows=[]; ANCH=115*60
for mid_,g in T.groupby('mid',sort=False):
    sels=list(g.sel.unique())
    if len(sels)!=3: SK['market not 3-way']+=1; continue
    st=float(np.median(g.ts+g.sto)); R={}
    for name,s in g.groupby('sel'):
        s=s.sort_values('ts'); R[name]=(s.sto.values.astype(float),s.bp.values.astype(float),s.lp.values.astype(float))
    A={n:anchor(v[0],ANCH) for n,v in R.items()}
    if any(i is None for i in A.values()): SK['no T-115 book on all three']+=1; continue
    ov=overround([R[n][1][A[n]] for n in R])
    w=sorted(R,key=lambda n:(-gap(R[n][1][A[n]],R[n][2][A[n]]),R[n][1][A[n]]))[0]
    sto,bp,lp=R[w]; i=A[w]; g0=gap(bp[i],lp[i])
    if g0<2: SK['widest gap is 1 tick, nothing to close']+=1; rows.append(dict(mid=mid_,ov=ov,gap0=g0,traded=False,day=None)); continue
    j,why=exit_index(sto,bp,lp,i)
    tb=[t for t in sels if t.lower()!='the draw']; lg='unmatched'
    if len(tb)==2:
        c=F[(F.ko-st).abs()<=900]; b=[]
        for f in c.itertuples(): b.append((max(sim(tb[0],f.home)+sim(tb[1],f.away),sim(tb[1],f.home)+sim(tb[0],f.away)),f.league))
        b.sort(key=lambda z:-z[0])
        if b and b[0][0]>=1.0: lg=b[0][1]
    x=back_trade(bp[i],lp[j]); y=lay_trade(lp[i],bp[j])
    rows.append(dict(mid=mid_,ov=ov,gap0=g0,traded=True,day=pd.Timestamp(st,unit='s',tz='UTC').date(),league=lg,px=float(bp[i]),band=('<2' if bp[i]<2 else '2-3' if bp[i]<3 else '3-5' if bp[i]<5 else '5-10' if bp[i]<10 else '10+'),why=why,back=np.nan if x is None else x,lay=y,hold=(sto[i]-sto[j])/60))
print("counts (not hidden):",dict(SK),flush=True)
A_=pd.DataFrame(rows)
if A_.empty: print("ERROR: no markets, so no verdict"); sys.exit(1)
print("overround at T-115, quantiles:",A_.ov.quantile([.1,.25,.5,.75,.9]).round(2).to_dict(),"| share >=103%:",round((A_.ov>=103).mean(),3),flush=True)
D=A_[A_.traded==True].copy()
if D.empty: print("ERROR: no trades, so no verdict"); sys.exit(1)
days=sorted(D.day.unique()); md=days[len(days)//2]
print(f"traded markets {len(D)} | days {days[0]}..{days[-1]} | halves split at {md} | exit reasons {D.why.value_counts().to_dict()} | median hold {D.hold.median():.1f} min",flush=True)
def line(d,col,**k):
    d=d[d[col].notna()]; a=d[d.day<md][col]; c=d[d.day>=md][col]; v=d[col]
    if not len(v): return dict(**k,n=0,per10=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,closed=np.nan,PASS=False)
    return dict(**k,n=len(v),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,closed=(d.why=='closed').mean(),PASS=len(v)>=300 and len(a)>=150 and len(c)>=150 and tstat(v)>=3.5 and a.mean()>0 and c.mean()>0 and v.mean()>=0.15)
res=[]
for side in ('back','lay'):
    for lab,m in (('OR>=102',D.ov>=102),('OR>=103',D.ov>=103),('OR>=105',D.ov>=105),('CTRL OR<103',D.ov<103),('all',D.ov>0)):
        res.append(line(D[m],side,side=side,set=lab,cut='all'))
    for b_,dd in D[D.ov>=103].groupby('band'): res.append(line(dd,side,side=side,set='OR>=103',cut='px '+b_))
    for g_,dd in D[D.ov>=103].groupby(pd.cut(D[D.ov>=103].gap0,[1,3,6,10,1000],labels=['gap2-3','gap4-6','gap7-10','gap11+']),observed=True): res.append(line(dd,side,side=side,set='OR>=103',cut=str(g_)))
    for l_,dd in D[D.ov>=103].groupby('league'):
        if len(dd)>=10: res.append(line(dd,side,side=side,set='OR>=103',cut='lg '+l_))
R_=pd.DataFrame(res).sort_values('t',ascending=False)
print("\n== RESULTS per £10\n",R_.round(3).to_string(index=False))
W=R_[R_.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(R_)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
