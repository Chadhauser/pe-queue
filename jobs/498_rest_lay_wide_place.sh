#!/bin/bash
set -o pipefail
# 498 (Finder 2026-11-04, queue item 43): REST A LAY INSIDE WIDE IN-PLAY PLACE BOOKS on ip_tape. PILOT: the tape rolls at about 6 days, so expect under n 300.
# SIGNAL: clean frames only (487's rule: frame total_matched below the running max of earlier frames = replay, dropped), status OPEN, secs_since_start > 0. Offer the lay at the runner's current back_px, order alive 60 s. One order per runner per race per group.
# GROUPS: WIDE = lay/back > 1.25 at the market's first frame (the item). TIGHT = lay/back <= 1.25 at that frame (the item's control). WIDEANY = the runner's first frame at any time with lay/back > 1.25. A runner with no lay_px has no ratio: counted, no order.
# FILL, CORRECTING THE ITEM'S WORDING: the item says fill on a print "at or above the level". jobs/492 established the opposite. Backers take the highest offer first, so a print above X is someone else's better offer and does not fill a resting lay at X. Only a print strictly BELOW X proves X has gone.
#   THROUGH = first fresh print within 60 s strictly below X: the only kind that can pass. TOUCH = at or below X, assumes first in the queue, diagnostic. ASWRITTEN = at or above X, the item's literal rule, shown to record the difference, diagnostic.
#   FRESH = runner ltp changed on the previous clean open frame AND market total_matched rose: a stale ltp is not a print. ip_tape has no per-runner volume, so a repeat print at the same price is missed. Never the order's own frame.
# ENTRY: fills at one tick above X (one tick adverse); "exact" column = at X, diagnostic. Held to result: the place market settles, never dropped. Lay liability £10, 2% commission on profits.
# RESULT: 487's label. placed = ltp <= 1.05 on the runner's last clean frame, any status. Known only if the placed count fits the field (<=7: 2, 8-15: 3, 16+: 3 or 4) and the WIN winner from racing_results, where present, is among the placed. Unknown = -£10. "known" column drops those, diagnostic.
# Lays below 1.10 win many times the liability, so a pass also needs x110 (mean without X under 1.10) >= +£0.15. Halves: median race date. t per trade, t_c clustered by race; many runners per race are correlated.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
BUDGET=2200
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def up(p): return float(LADA[min(int(np.searchsorted(LADA,round(float(p),2)-1e-9))+1,len(LADA)-1)])
def lay_pnl(a,placed):
    """Lay filled at a, £10 liability. placed None = unknown = -£10."""
    if placed is None or placed: return -10.0
    return 10/(a-1)*0.98
def clean_mask(tm):
    tm=np.asarray(tm,dtype=float); keep=np.ones(len(tm),bool); mx=-np.inf
    for i,v in enumerate(tm):
        if np.isnan(v): keep[i]=False; continue
        if v<mx: keep[i]=False
        else: mx=v
    return keep
def allowed(field): return {2} if field<=7 else {3} if field<=15 else {3,4}
def label(placed,field,winner):
    if len(placed) not in allowed(field): return None
    if winner is not None and winner not in placed: return None
    return placed
def fill_at(T,L,TM,i,X,kind,win=60):
    """First j>i within win seconds with a fresh print on the right side of X. None if never."""
    for j in range(i+1,len(T)):
        if T[j]-T[i]>win: return None
        if not (L[j]!=L[j-1] and TM[j]>TM[j-1]): continue
        if (kind=='THROUGH' and L[j]<X) or (kind=='TOUCH' and L[j]<=X) or (kind=='ASWRITTEN' and L[j]>=X): return j
    return None
def at_first(ts,first):
    """Is this runner's earliest frame the market's first? Compare as Timestamps: .values drops the timezone and never equals an aware Timestamp (the bug in this job's first run)."""
    return ts.iloc[0]==first
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    return float(v.mean()/(v.std(ddof=1)/np.sqrt(len(v)))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
def passes(n,n1,n2,t,h1,h2,m,x110):
    return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15 and x110>=0.15)
# known answers, worked by hand
assert up(2.0)==2.02 and up(1.99)==2.0 and up(3.0)==3.05 and up(1.5)==1.51
assert abs(lay_pnl(3.05,False)-10/2.05*0.98)<1e-9 and lay_pnl(3.05,True)==-10.0 and lay_pnl(3.05,None)==-10.0 and abs(lay_pnl(1.51,False)-19.2157)<1e-3   # 9.8/0.51
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False] and clean_mask([10,float('nan'),11]).tolist()==[True,False,True]
assert label({'a','b'},7,'a')=={'a','b'} and label({'a','b'},8,'a') is None and label({'a','b','c'},9,'z') is None and label({'a','b','c'},16,None)=={'a','b','c'}
T_=[0,10,20,30,100]; L_=[3.0,3.0,3.1,2.9,2.8]; V_=[1,2,3,4,5]
assert fill_at(T_,L_,V_,0,3.0,'THROUGH')==3                                   # 3.0 unchanged not fresh, 3.1 is above X, 2.9 through
assert fill_at(T_,L_,V_,0,3.0,'ASWRITTEN')==2 and fill_at(T_,L_,V_,0,3.0,'TOUCH')==3
assert fill_at(T_,L_,V_,0,2.85,'THROUGH') is None                             # 2.8 comes at 100 s, past the 60 s life
assert fill_at([0,10,20],[3.0,2.9,2.8],[1,1,2],0,3.0,'THROUGH')==2            # 2.9 had no volume, so a stale ltp; 2.8 had
assert fill_at([0,10],[2.9,2.9],[1,2],0,3.0,'THROUGH') is None                # the ltp already below X at signal is old: not a fill
_ts=pd.Series(pd.to_datetime(['2026-11-01 12:00:00','2026-11-01 12:00:05'],utc=True))
assert at_first(_ts,_ts.min()) and not at_first(_ts.iloc[1:],_ts.min())
assert band(1.49)=='<1.5' and band(2.0)=='2-3' and band(10.0)=='10+' and abs(tstat([1,3])-2.0)<1e-9
assert passes(300,150,150,3.5,.1,.1,.15,.15) and not passes(299,150,149,9,1,1,1,1) and not passes(400,200,200,4,-.1,1,1,1) and not passes(400,200,200,4,1,1,1,.1)
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
t0=time.time(); frames=[]; wins=[]; SK=Counter()
end=pd.Timestamp.now(tz='UTC').normalize()+pd.Timedelta(days=1)
for k in range(1,11):   # newest first, so a budget stop still leaves the recent days
    if time.time()-t0>BUDGET: SK['days not pulled, budget']+=1; continue
    a=end-pd.Timedelta(days=k); b=a+pd.Timedelta(days=1)
    d=pd.read_sql("""SELECT ts,market_id,event_name,market_start,status,secs_since_start ss,sel_id,ltp::float ltp,back_px::float bp,lay_px::float lp,total_matched::float tm FROM ip_tape
       WHERE sport='horse_racing' AND market_type='PLACE' AND ts>=%s AND ts<%s""",con,params=(a,b))
    w=pd.read_sql("""SELECT DISTINCT market_id,event_name,market_start FROM ip_tape WHERE sport='horse_racing' AND market_type='WIN' AND ts>=%s AND ts<%s""",con,params=(a,b))
    if len(d): frames.append(d)
    if len(w): wins.append(w)
    print(f"  {a.date()} place rows {len(d)} win markets {len(w)} | {int(time.time()-t0)}s",flush=True)
if not frames: print("ERROR: no racing rows pulled, so no verdict"); sys.exit(1)
A=pd.concat(frames,ignore_index=True); W=pd.concat(wins,ignore_index=True).drop_duplicates('market_id') if wins else pd.DataFrame(columns=['market_id','event_name','market_start'])
print(f"place rows {len(A)} | place markets {A.market_id.nunique()} | {A.ts.min()} .. {A.ts.max()}",flush=True)
Pm=A.drop_duplicates('market_id')[['market_id','event_name','market_start']]
pair=Pm.merge(W,on=['event_name','market_start'],suffixes=('','_w')).drop_duplicates('market_id')
pw=dict(zip(pair.market_id,pair.market_id_w))
rr=pd.read_sql("SELECT market_id,selection_id,won FROM racing_results WHERE market_id=ANY(%s) AND won IS TRUE",con,params=(pair.market_id_w.tolist(),))
WIN=rr.groupby('market_id').selection_id.agg(list).to_dict()
print(f"paired with WIN {len(pair)} | racing_results winners for {len(WIN)}",flush=True)
EP=pd.Timestamp('1970-01-01',tz='UTC'); recs=[]
for mid,g in A.groupby('market_id',sort=False):
    f=g.groupby('ts',sort=True).tm.max(); keep=clean_mask(f.values); ok=f.index[keep]; SK['frames']+=len(f); SK['frames stale']+=int((~keep).sum())
    g=g[g.ts.isin(ok)].sort_values('ts')
    if g.empty: SK['market: no clean frame']+=1; continue
    last=g.groupby('sel_id').tail(1); field=last.sel_id.nunique(); placed=set(last[last.ltp<=1.05].sel_id)
    wl=WIN.get(pw.get(mid)); winner=wl[0] if wl and len(wl)==1 else None
    res=label(placed,field,winner); known=res is not None
    o=g[(g.status=='OPEN')&(g.ss>0)]; tss=np.sort(o.ts.unique())
    if len(tss)<2: SK['market: under 2 open frames']+=1; continue
    SK['market']+=1; SK['market: result known']+=int(known)
    day=pd.Timestamp(g.market_start.iloc[0]).date(); first=o.ts.min()
    for sid,x in o.groupby('sel_id',sort=False):
        x=x.drop_duplicates('ts'); T=((x.ts-EP)/pd.Timedelta('1s')).values; L=x.ltp.values; B=x.bp.values; Y=x.lp.values; TM=x.ts.map(f).values
        R=np.where((B>1)&(Y>1),Y/B,np.nan); w=None if not known else (sid in res)
        sig=[]
        if at_first(x.ts,first):
            if not (B[0]>1): SK['first frame: no back price']+=1
            elif np.isnan(R[0]): SK['first frame: no lay price, no ratio']+=1
            else: sig.append(('WIDE' if R[0]>1.25 else 'TIGHT',0))
        wide=np.where(R>1.25)[0]
        if len(wide): sig.append(('WIDEANY',int(wide[0])))
        for grp,i in sig:
            X=float(B[i]); rec=dict(group=grp,market=mid,sid=sid,day=day,X=X,band=band(X),known=known,placed=w,implied=1/X,ratio=R[i])
            for kind in ('THROUGH','TOUCH','ASWRITTEN'):
                rec[kind]=fill_at(T,L,TM,i,X,kind) is not None
            recs.append(rec)
print("counts (not hidden):",dict(SK),"| stale frames",round(SK['frames stale']/max(SK['frames'],1),3),flush=True)
D=pd.DataFrame(recs)
if D.empty: print("\n== SURVIVORS: 0\nnone"); sys.exit()
D['pnl']=[lay_pnl(up(a),p) for a,p in zip(D.X,D.placed)]; D['exact']=[lay_pnl(a,p) for a,p in zip(D.X,D.placed)]
days=sorted(D.day.unique()); md=sorted(D.drop_duplicates('market').day)[D.market.nunique()//2]
print(f"orders {len(D)} | races {D.market.nunique()} | {days[0]}..{days[-1]} | second half from {md}",flush=True)
if not {'WIDE','TIGHT'}<=set(D.group): print("ERROR: WIDE or TIGHT has no orders, so no verdict:",D.group.value_counts().to_dict()); sys.exit(1)
print("orders by group:",D.group.value_counts().to_dict(),"| median lay/back:",D.groupby('group').ratio.median().round(3).to_dict(),flush=True)
out=[]
def line(s,**k):
    fl=s[s[k['kind']]]; r=dict(**k,signals=len(s),n=len(fl),fill=len(fl)/len(s) if len(s) else np.nan)
    if not len(fl): return r
    a=fl[fl.day<md].pnl; b=fl[fl.day>=md].pnl; e=fl[fl.X>=1.10].pnl; kn=fl[fl.known].pnl
    r.update(races=fl.market.nunique(),px=fl.X.median(),per10=fl.pnl.mean(),t=tstat(fl.pnl),t_c=tstat(fl.groupby('market').pnl.sum()),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,exact=fl.exact.mean(),known=kn.mean() if len(kn) else np.nan,per_signal=fl.pnl.sum()/len(s),x110=e.mean() if len(e) else np.nan)
    r['PASS']=k['kind']=='THROUGH' and passes(r['n'],r['n1'],r['n2'],r['t'],r['h1'],r['h2'],r['per10'],r['x110'])
    return r
for kind in ('THROUGH','TOUCH','ASWRITTEN'):
    for grp,s in D.groupby('group'):
        out.append(line(s,kind=kind,group=grp,cut='all'))
        for bd,y in s.groupby('band'): out.append(line(y,kind=kind,group=grp,cut=bd))
S=pd.DataFrame(out); S['PASS']=S.PASS.fillna(False).astype(bool)
print("\n== HEADLINE, per FILLED order, all prices\n",S[S.cut=='all'].sort_values(['kind','group']).drop(columns=['PASS','cut']).round(3).to_string(index=False))
print("\n== THROUGH by band (the kind that can pass)\n",S[S.kind=='THROUGH'].sort_values(['group','cut']).drop(columns=['kind','PASS']).round(3).to_string(index=False))
K=D[D.known].copy(); K['pl']=K.placed.astype(float)
print("\n== ADVERSE SELECTION, known results, placed rate v the rate implied by X: THROUGH-filled v unfilled")
print(K.groupby(['group','THROUGH']).agg(n=('pl','size'),implied=('implied','mean'),placed=('pl','mean')).round(3).to_string())
print("\n== same, WIDE by band")
print(K[K.group=='WIDE'].groupby(['band','THROUGH']).agg(n=('pl','size'),implied=('implied','mean'),placed=('pl','mean')).round(3).to_string())
E=S[(S.n>=30)&(S.kind=='THROUGH')].sort_values('t',ascending=False)
print("\n== TOP 15 BY t, THROUGH, n>=30\n",E.head(15).drop(columns=['kind','PASS']).round(3).to_string(index=False))
Z=S[S.PASS]; print(f"\n== SURVIVORS: {len(Z)} of {int((S.kind=='THROUGH').sum())} THROUGH lines"); print(Z.round(3).to_string(index=False) if len(Z) else "none")
PY
