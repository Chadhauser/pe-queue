#!/bin/bash
set -o pipefail
# 499_place_terms (Finder 2026-11-04, queue item 56): IS THE PLACE MARKET PRICED FOR THE NUMBER OF PLACES PAID? racing_bsp UK/IE PLACE. The number 499 is reused with a new slug: 450-499 are all taken.
# PLACES PAID: the number of runners with win_lose >= 1. Market names on this table are checked first; if they do not carry the terms, this count comes from the result, so a dead heat can inflate it: races with win_lose = 2 are dropped and counted, and the paid x field table shows the odd cells. Real terms were known before the off, but this column is not, so a pass would need the terms from a pre-off source.
# FIELD: runners with a BSP. A late non-runner can leave field 7 paying 3, the boundary the item asks about.
# BOOK = sum of 1/BSP over the race, against places paid.
# ONE ENTRY PER RACE PER STATE: BOOK line = mean P&L of £10 on every runner, one number per race, so runners in a race do not inflate t. FAV line = the shortest BSP in the race only. Back stake £10, lay liability £10, 2% on profit, settled at the result. House = one tick adverse off BSP; exact = at BSP, a diagnostic only.
# CHOOSE before 1 Jul 2025 (top 8 cells per side by t, n >= 100), SCORE from 1 Jul 2025, halves at the hold-out median date. PASS reads the hold-out, house cost.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40); pd.set_option('display.max_colwidth',60)
T0=time.time()
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ti(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p,k=1): return float(LADA[max(ti(p)-k,0)])
def up(p,k=1): return float(LADA[min(ti(p)+k,len(LADA)-1)])
def net(x): return x*0.98 if x>0 else x
def back(p,won,adv=True):
    a=dn(p) if adv else p
    if a<=(1.01 if adv else 1.0): return None   # one tick off 1.02 is 1.01: nothing left to back
    return net(10*(a-1)) if won else -10.0
def lay(p,won,adv=True):
    a=up(p) if adv else p
    return -10.0 if won else net(10/(a-1))
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
def book_stats(bsps,wins):
    """Book sum, places paid, field, from one race's runners."""
    return float(sum(1/x for x in bsps)),int(sum(1 for w in wins if w>=1)),len(bsps)
# known answers, worked by hand
assert dn(3.0)==2.98 and up(3.0)==3.05 and dn(3.7)==3.65 and up(1.5)==1.51
assert abs(back(3.0,True)-10*1.98*.98)<1e-9 and back(3.0,False)==-10.0 and abs(back(3.0,True,False)-19.6)<1e-9 and back(1.01,True) is None
assert lay(3.0,True)==-10.0 and abs(lay(3.0,False)-10/2.05*.98)<1e-9 and abs(lay(3.0,False,False)-4.9)<1e-9
assert book_stats([2.0,4.0,4.0],[1,0,0])==(1.0,1,3) and book_stats([2.0,2.0],[1,2])[1]==2
# a fair place book: 3 paid from 6 at 2.0 each sums to 3.0 = paid
assert abs(book_stats([2.0]*6,[1,1,1,0,0,0])[0]-3.0)<1e-9 and abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("SELECT event_id,event_dt,event_name,menu_hint,selection_id,win_lose,bsp::float bsp FROM racing_bsp WHERE lower(market)='place' AND lower(country) IN ('uk','ire')",con); con.close()
print(f"rows {len(D)}, {D.event_dt.min()} to {D.event_dt.max()}; market names:",D.event_name.value_counts().head(8).to_dict(),flush=True)
print("names carrying a digit:",int(D.event_name.fillna('').str.contains(r'\d').sum()),flush=True)
nb=D.bsp.isna()|(D.bsp<=1)|(D.bsp>=1000); wnull=D.win_lose.isna(); print(f"dropped rows: no usable BSP {int(nb.sum())}, no result {int((wnull&~nb).sum())}",flush=True); D=D[~nb&~wnull].copy()
D['rid']=D.event_id.astype(str)+'_'+D.event_dt.astype(str); D['won']=D.win_lose>=1
dh=D[D.win_lose==2].rid.unique(); print("races with win_lose=2, dropped:",len(dh),flush=True); D=D[~D.rid.isin(dh)]
g=D.groupby('rid'); R=pd.DataFrame(dict(dt=g.event_dt.first(),book=g.bsp.apply(lambda s:(1/s).sum()),paid=g.won.sum(),field=g.bsp.size())); bad=R.paid==0; print("races with nobody placed, dropped:",int(bad.sum()),flush=True); R=R[~bad]; D=D[D.rid.isin(R.index)]
D['bh']=[back(p,w) for p,w in zip(D.bsp,D.won)]; D['lh']=[lay(p,w) for p,w in zip(D.bsp,D.won)]; D['bx']=[back(p,w,False) for p,w in zip(D.bsp,D.won)]; D['lx']=[lay(p,w,False) for p,w in zip(D.bsp,D.won)]
n0=len(D); D=D.dropna(subset=['bh']); print("too short to back at one tick, dropped rows:",n0-len(D),flush=True)
B=D.groupby('rid')[['bh','lh','bx','lx']].mean(); F=D.sort_values('bsp').drop_duplicates('rid').set_index('rid')[['bh','lh','bx','lx','bsp','won']].add_prefix('f_')
R=R.join(B).join(F); R['over']=R.book-R.paid; R['hold']=R.dt>=pd.Timestamp('2025-07-01'); print(f"races {len(R)}, fit {int((~R.hold).sum())}, hold-out {int(R.hold.sum())}",flush=True)
T=R.groupby(['paid','field']).agg(n=('book','size'),book=('book','mean'),over=('over','mean'),back=('bx','mean'),lay=('lx','mean'),fav_won=('f_won','mean'),fav_imp=('f_bsp',lambda s:(1/s).mean())).reset_index(); print("\n== BOOK v PLACES PAID, every race; back and lay at exact BSP, mean per runner per race\n",T[T.n>=20].round(3).to_string(index=False))
print("\nodd cells, n < 20:",T[T.n<20][['paid','field','n']].values.tolist()[:40],flush=True)
R['fb']=pd.cut(R.field,[0,5,6,7,8,9,10,12,15,17,50],labels=['<=5','6','7','8','9','10','11-12','13-15','16-17','18+']).astype(str)
R['cell']=R.paid.astype(int).astype(str)+'paid|'+R.fb
FIT=R[~R.hold]; HO=R[R.hold]; med=HO.dt.sort_values().iloc[len(HO)//2]; print("hold-out median date",med,flush=True)
def score(name,d,c,x):
    a=d[d.dt<med][c].dropna(); b=d[d.dt>=med][c].dropna(); v=d[c].dropna()
    r=dict(line=name,n=len(v),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,exact=d[x].mean())
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
SIDES=(('BOOK back','bh','bx'),('BOOK lay','lh','lx'),('FAV back','f_bh','f_bx'),('FAV lay','f_lh','f_lx'))
O=[]; ALLC=[]
for nm,c,x in SIDES:
    O.append(dict(score(f"{nm} ALL races",HO,c,x),fit=FIT[c].mean(),nfit=len(FIT)))
    L=FIT.groupby('cell')[c].agg(['size','mean',tstat]); L=L[L['size']>=100].sort_values('tstat',ascending=False)
    for cell,row in L.head(8).iterrows():
        d=HO[HO.cell==cell]
        if len(d): O.append(dict(score(f"{nm} {cell}",d,c,x),fit=row['mean'],nfit=int(row['size'])))
    for cell,d in HO.groupby('cell'):
        if len(d)>=100: ALLC.append(score(f"{nm} {cell}",d,c,x))
S=pd.DataFrame(O).sort_values('t',ascending=False); print("\n== CHOSEN ON THE FIT PERIOD, scored on the hold-out, by t\n",S.drop(columns=['PASS']).round(3).to_string(index=False))
A=pd.DataFrame(ALLC).sort_values('t',ascending=False); print("\n== every hold-out cell n >= 100, top 10 by t, NOT chosen in advance, for reading only\n",A.head(10).drop(columns=['PASS']).round(3).to_string(index=False)); print("cells",len(A),"positive",int((A.per10>0).sum()),"numeric pass",int(A.PASS.sum()))
Y=R.assign(y=R.dt.dt.year).groupby('y').agg(n=('book','size'),over=('over','mean'),book=('book','mean'),paid=('paid','mean'),back=('bx','mean'),lay=('lx','mean')); print("\n== by year\n",Y.round(3).to_string())
W=S[S.PASS&~S.line.str.contains('ALL')]; print(f"\n== SURVIVORS: {len(W)} of {len(S[~S.line.str.contains('ALL')])} chosen lines (BSP fills, terms inferred from the result)"); print(W.round(3).to_string(index=False) if len(W) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
