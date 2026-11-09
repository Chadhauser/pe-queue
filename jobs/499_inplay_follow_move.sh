#!/bin/bash
set -o pipefail
# 499_inplay_follow_move (Finder 2026-11-09, about 08:50 UTC run, queue item 490, Finder's own, source a, born from item 489's fill asymmetry; rule
# pushed in the queue before this job read a price). Market list fixed: finder_ipunseen_mk_1109 (Soccer, loaded 8 Nov 09:26 UTC to 9 Nov 08:24 UTC).
# 15 types (the in-play map's). T_k = market_time + 15k+1 min, k=1..6. P = runner's last print in [T-5,T); L = last print in [T,T+3);
# SHORTENED L<=0.95P, DRIFTED L>=1.05P. FOLLOW = back a shortener / lay a drifter at the runner's FIRST print in [T+3,T+6), one tick adverse;
# FADE = the other side at the same print (control). Back £10 stake, lay £10 liability, 2% on profit, official result, exactly one winner.
# Bar: n>=300 (>=150 a half), mean>=+0.15, both halves (market_time median) positive, t>=3.5 on per-GAME sums. Reading only: 10% threshold.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys, math, time, gc, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time(); CAP=40*60; COMM=0.02
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def vtick(p):
    inc=np.full(len(p),10.0)
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): p=np.asarray(p,float); return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): p=np.asarray(p,float); return np.round(np.minimum(1000,p+vtick(p)),2)
def pnl(side_back, won, back_px, lay_px):
    b=np.where(won==1,(back_px-1)*10*(1-COMM),-10.0)
    l=np.where(won==1,-10.0,10.0/(lay_px-1)*(1-COMM))
    return np.where(side_back,b,l)
def tstat(a):
    a=np.asarray(a,float)
    return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
assert list(tick_up([2.0,3.0,1.01,5.9]))==[2.02,3.05,1.02,6.0]
assert list(tick_down([2.0,3.0,1.01,6.0]))==[1.99,2.98,1.01,5.9]
t=pnl(np.array([True,True,False,False]),np.array([1,0,0,1]),np.array([1.99,1.99,0,0]),np.array([0,0,2.02,2.02]))
assert np.allclose(t,[9.702,-10.0,10/1.02*0.98,-10.0]), t
print("unit checks: tick ladder and P&L PASS",flush=True)
TYPES=['BOTH_TEAMS_TO_SCORE','CORRECT_SCORE','DRAW_NO_BET','FIRST_HALF_GOALS_05','FIRST_HALF_GOALS_15','FIRST_HALF_GOALS_25','HALF_TIME','HALF_TIME_FULL_TIME',
       'HALF_TIME_SCORE','MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','OVER_UNDER_45']
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT u.market_id FROM finder_ipunseen_mk_1109 u
   WHERE u.market_id IS NOT NULL AND EXISTS (SELECT 1 FROM bf_hist_other b WHERE b.sport='Soccer' AND b.market_id=u.market_id AND b.market_type = ANY(%s))""",(TYPES,))
ids=sorted(r[0] for r in cur.fetchall()); con.commit()
ids=list(np.array(ids)[np.random.default_rng(5).permutation(len(ids))])
print(f"Soccer market ids: {len(ids)}  ({time.time()-T0:.0f}s)",flush=True)
Q="""
WITH x AS (SELECT market_id, event_id, market_type, market_time, sel, ts, ltp::float8 ltp, EXTRACT(EPOCH FROM (ts-market_time))/60.0 AS mn
           FROM bf_hist_other WHERE sport='Soccer' AND market_id = ANY(%s) AND market_type = ANY(%s) AND inplay AND ltp>1 AND ltp<1000
             AND ts>market_time+interval '11 minutes' AND ts<market_time+interval '98 minutes'),
     y AS (SELECT x.*, k, CASE WHEN mn<15*k+1 THEN 0 WHEN mn<15*k+4 THEN 1 ELSE 2 END w
           FROM x JOIN generate_series(1,6) k ON x.mn>=15*k-4 AND x.mn<15*k+7)
SELECT DISTINCT ON (market_id, sel, k, w) market_id, event_id, market_type, market_time, sel, k, w, ltp, mn
FROM y ORDER BY market_id, sel, k, w, CASE WHEN w=2 THEN mn ELSE -mn END"""
out=[]; st=dict(read=0,moves=0,noentry=0); stopped=False; CH=3000
for i in range(0,len(ids),CH):
    if time.time()-T0>CAP: stopped=True; break
    chunk=[str(x) for x in ids[i:i+CH]]
    cur.execute(Q,(chunk,TYPES)); rows=cur.fetchall()
    cur.execute("SELECT market_id, sel, (status='WINNER')::int FROM bf_hist_result WHERE market_id = ANY(%s) AND status IN ('WINNER','LOSER')",(chunk,))
    res=pd.DataFrame(cur.fetchall(),columns=['market_id','sel','won']); con.commit()
    st['read']+=len(chunk)
    if not rows or res.empty: continue
    res=res[res.groupby('market_id').won.transform('sum')==1]
    d=pd.DataFrame(rows,columns=['market_id','event_id','market_type','market_time','sel','k','w','ltp','mn'])
    d['T']=15*d.k+1.0
    lo=d['T']+np.select([d.w==0,d.w==1],[-5,0],3); assert ((d.mn>=lo)&(d.mn<lo+np.where(d.w==0,5,3))).all()
    wide=d.pivot_table(index=['market_id','sel','k'],columns='w',values='ltp',aggfunc='first')
    wide.columns=[{0:'P',1:'L',2:'E'}[c] for c in wide.columns]
    for c in 'PLE':
        if c not in wide: wide[c]=np.nan
    wide=wide.dropna(subset=['P','L']).reset_index()
    meta=d.drop_duplicates(['market_id','sel'])[['market_id','sel','event_id','market_type','market_time']]
    wide=wide.merge(meta,on=['market_id','sel'])
    wide['sel']=wide.sel.astype(res.sel.dtype); wide=wide.merge(res,on=['market_id','sel'],how='inner')
    r=wide.L/wide.P; wide=wide[(r<=0.95)|(r>=1.05)].copy(); wide['short']=(wide.L/wide.P)<=0.95; wide['big']=((wide.L/wide.P)<=0.90)|((wide.L/wide.P)>=1.10)
    st['moves']+=len(wide); ne=wide.E.isna(); st['noentry']+=int(ne.sum()); wide=wide[~ne]
    wide['market_id']=(pd.factorize(wide.market_id)[0]+i*10).astype(np.int64); wide['event_id']=pd.to_numeric(wide.event_id).astype(np.int64)
    out.append(wide[['market_id','event_id','market_type','market_time','k','P','L','E','won','short','big']])
    del d,wide,rows,res; gc.collect()
    if (i//CH)%10==0: print(f"  chunk {i//CH+1}/{(len(ids)+CH-1)//CH}: entries {sum(len(o) for o in out)}  ({time.time()-T0:.0f}s)",flush=True)
print(f"read {st['read']} of {len(ids)} ids{' -- STOPPED BY THE 40-MIN CAP, a random sample' if stopped else ''}; 5% moves {st['moves']}, no entry print in [T+3,T+6) {st['noentry']}",flush=True)
A=pd.concat(out,ignore_index=True); del out; gc.collect()
E=A.E.values; w=A.won.values; sh=A.short.values
A['pnl']=pnl(sh,w,tick_down(E),tick_up(E))          # FOLLOW: back a shortener, lay a drifter
A['fade']=pnl(~sh,w,tick_down(E),tick_up(E))
A['imp']=1/E
mt=pd.to_datetime(A.market_time,utc=True); A['h2']=(mt>=mt.quantile(0.5)).values
print(f"entries {len(A)} on {A.market_id.nunique()} markets, {A.event_id.nunique()} games; {mt.min():%Y-%m-%d}..{mt.max():%Y-%m-%d}; halves at {mt.quantile(0.5):%Y-%m-%d %H:%M}",flush=True)
def line(g,name,col='pnl'):
    n=len(g)
    if n==0: return None
    h1=g[~g.h2][col]; h2=g[g.h2][col]
    return dict(name=name,n=n,gm=g.event_id.nunique(),mean=g[col].mean(),t=tstat(g[col]),tg=tstat(g.groupby('event_id')[col].sum()),
                h1=h1.mean() if len(h1) else float('nan'),h2=h2.mean() if len(h2) else float('nan'),n1=len(h1),n2=len(h2),won=g.won.mean(),imp=g.imp.mean(),fade=g.fade.mean())
def show(L):
    print(f"{L['name']:<46} n {L['n']:>7} gm {L['gm']:>5} per10 {L['mean']:+.3f} t {L['t']:+.2f} t_game {L['tg']:+.2f} h1 {L['h1']:+.3f} ({L['n1']}) h2 {L['h2']:+.3f} ({L['n2']}) | won {L['won']:.4f} v imp@entry {L['imp']:.4f} | fade {L['fade']:+.3f}",flush=True)
print("\n== PRIMARY: FOLLOW pooled ==",flush=True)
P0=line(A,"FOLLOW ALL 5%"); show(P0)
show(line(A[A.short],"FOLLOW back shorteners")); show(line(A[~A.short],"FOLLOW lay drifters"))
for k,g in A.groupby('k'): show(line(g,f"FOLLOW band T={15*k+1}"))
show(line(A,"FADE ALL 5% (control)",'fade'))
print("\n== READING: 10% threshold ==",flush=True)
show(line(A[A.big],"FOLLOW 10%")); show(line(A[A.big&A.short],"FOLLOW 10% back")); show(line(A[A.big&~A.short],"FOLLOW 10% lay"))
print("\n== per market type x direction, n>=300, top 15 by t_game (FOLLOW, and FADE marked F) ==",flush=True)
al=[]
for (m,s),g in A.groupby(['market_type','short']):
    if len(g)>=300:
        al.append(line(g,f"{m} {'back short' if s else 'lay drift'}")); al.append(line(g,f"F {m} {'lay short' if s else 'back drift'}",'fade'))
al.sort(key=lambda L:-L['tg'])
for L in al[:15]: show(L)
print(f"lines n>=300: {len(al)}; positive {sum(L['mean']>0 for L in al)}",flush=True)
print("\n== SURVIVORS (n>=300, n per half>=150, per10>=+0.15, h1>0, h2>0, t_game>=3.5) ==",flush=True)
ns=0
for L in [P0]+al:
    if L['n']>=300 and L['n1']>=150 and L['n2']>=150 and L['mean']>=0.15 and L['h1']>0 and L['h2']>0 and L['tg']>=3.5: show(L); ns+=1
print(f"survivors: {ns}  ({time.time()-T0:.0f}s)",flush=True)
PY
