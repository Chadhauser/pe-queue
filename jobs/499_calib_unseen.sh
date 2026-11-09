#!/bin/bash
set -o pipefail
# 499_calib_unseen (Finder 2026-11-09, about 08:00 UTC run, lane default/top, queue item 486, Finder's own, data-led: fair-price map residuals,
# per the COO decision of 9 Nov). Rule pushed in the queue (commit dadf56c) before this job read an unseen price.
# The pre-off fair-price map (fair_price_calib, H1, built 8 Nov 21:03-21:10 UTC by /root/pe-sports/team/fairprice_v0.py) and the cells bookie v2
# (job 538) will quote on, scored on Soccer markets the map NEVER saw: their BASIC file was loaded (bf_hist_other_files.loaded_at) after the map's
# built_at. File names carry the market id, so "unseen" is exact, not a date guess.
# Passed cells: job 538's Verifier rule applied to the snapshot (fair_price_passed does not exist yet, 538 has not run): n_is>=300, n_oos>=100,
# same sign of (rate - implied) in IS and OOS, |e_is|>=0.01, |e_oos|>=0.005; side BACK if e_is>0 else LAY.
# Engine as fairprice_v0: last pre-off LTP per runner, 1<ltp<1000, complete books (every resulted runner priced, >=2 runners, raw book 0.95-1.25),
# exactly one official WINNER (bf_hist_result), p = normalised 1/ltp, the map's 18 bands. Entry one tick ADVERSE at that print.
# Stakes per the Finder brief (not the map's): back stake £10; lay LIABILITY £10 (stake 10/(price-1)); 2% on profit; held to the official result.
# PRIMARY: PASSED pooled. Bar: n>=300 (>=150 a half), mean>=+0.15, both halves (unseen market_time median) positive, t>=3.5 on the per-MARKET
# sums (several runners of one market can share a cell, so the per-trade t is inflated; both printed). Random-side control. Reading only: at
# the print with no tick (bookie v2 is a maker). Writes only its own snapshot tables finder_calib_snap_1109 and finder_unseen_mk_1109.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys, math, time, gc, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time()
COMM=0.02; rng=np.random.default_rng(11)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def vtick(p):
    inc=np.full(len(p),10.0)
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): p=np.asarray(p,float); return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): p=np.asarray(p,float); return np.round(np.minimum(1000,p+vtick(p)),2)
def pnl(side_back, won, back_px, lay_px):
    # back: stake 10; lay: liability 10, stake 10/(lay_px-1)
    b=np.where(won==1,(back_px-1)*10*(1-COMM),-10.0)
    l=np.where(won==1,-10.0,10.0/(lay_px-1)*(1-COMM))
    return np.where(side_back,b,l)
def tstat(a):
    a=np.asarray(a,float)
    return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
# ---- unit checks with known answers (fail loudly) ----
assert list(tick_up([2.0,3.0,1.01,5.9]))==[2.02,3.05,1.02,6.0], tick_up([2.0,3.0,1.01,5.9])
assert list(tick_down([2.0,3.0,1.01,6.0]))==[1.99,2.98,1.01,5.9], tick_down([2.0,3.0,1.01,6.0])
t=pnl(np.array([True,True,False,False]),np.array([1,0,0,1]),np.array([1.99,1.99,0,0]),np.array([0,0,2.02,2.02]))
assert np.allclose(t,[9.702,-10.0,10/1.02*0.98,-10.0]), t
print("unit checks: tick ladder and P&L PASS (back 1.99 win +9.702, lay 2.02 lose +9.608, liability -10)",flush=True)
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# ---- 1. snapshot the map before any rebuild can swallow the unseen months ----
cur.execute("DROP TABLE IF EXISTS finder_calib_snap_1109; CREATE TABLE finder_calib_snap_1109 AS SELECT * FROM fair_price_calib"); con.commit()
cal=pd.read_sql("SELECT market_type, band, band_lo::float8 lo, band_hi::float8 hi, n_is, rate_is::float8 rate_is, p_mean_is::float8 p_is, n_oos, rate_oos::float8 rate_oos, p_mean_oos::float8 p_oos, built_at FROM finder_calib_snap_1109",con)
B=cal.built_at.max(); print(f"map snapshot: {len(cal)} cells, {cal.market_type.nunique()} types, built {cal.built_at.min()} .. {B}",flush=True)
cal['e_is']=cal.rate_is-cal.p_is; cal['e_oos']=cal.rate_oos-cal.p_oos
cal['side_back']=cal.e_is>0
cal['passed']=(cal.n_is>=300)&(cal.n_oos>=100)&cal.rate_oos.notna()&((cal.e_is>0)==(cal.e_oos>0))&(cal.e_is.abs()>=0.01)&(cal.e_oos.abs()>=0.005)
print(f"passed cells by job 538's rule: {int(cal.passed.sum())}",flush=True)
for r in cal[cal.passed].sort_values(['market_type','band']).itertuples():
    print(f"   PASSED {r.market_type} p{r.lo:.2f}-{r.hi:.2f} {'BACK' if r.side_back else 'LAY'} n_is {r.n_is} e_is {r.e_is:+.4f} n_oos {r.n_oos} e_oos {r.e_oos:+.4f}",flush=True)
# ---- 2. unseen markets: file loaded after the map was built, before this job started ----
cur.execute("SELECT now()"); CUT=cur.fetchone()[0]
cur.execute("""DROP TABLE IF EXISTS finder_unseen_mk_1109;
CREATE TABLE finder_unseen_mk_1109 AS
  SELECT substring(path from '([0-9]+\\.[0-9]+)\\.bz2$') AS market_id, min(loaded_at) loaded_at FROM bf_hist_other_files
  WHERE loaded_at > %s AND loaded_at <= %s GROUP BY 1""",(B,CUT)); con.commit()
cur.execute("SELECT count(*), count(market_id) FROM finder_unseen_mk_1109"); print("unseen files->ids:",cur.fetchone(),"cut",CUT,flush=True)
# re-loads: an id whose file was ALSO loaded before the build is not unseen
cur.execute("""CREATE TEMP TABLE seen_ids AS SELECT DISTINCT substring(path from '([0-9]+\\.[0-9]+)\\.bz2$') AS market_id
   FROM bf_hist_other_files WHERE loaded_at <= %s""",(B,))
cur.execute("SELECT count(*) FROM finder_unseen_mk_1109 u JOIN seen_ids s USING (market_id)")
dup=cur.fetchone()[0]; print("unseen ids also loaded before the build (removed):",dup,flush=True)
if dup:
    cur.execute("DELETE FROM finder_unseen_mk_1109 u USING seen_ids s WHERE u.market_id=s.market_id")
cur.execute("DROP TABLE seen_ids"); con.commit()
cur.execute("CREATE INDEX ON finder_unseen_mk_1109 (market_id)"); con.commit()
cur.execute("SELECT market_id FROM finder_unseen_mk_1109 WHERE market_id IS NOT NULL ORDER BY 1"); ids=[r[0] for r in cur.fetchall()]
print(f"unseen market ids: {len(ids)}  ({time.time()-T0:.0f}s)",flush=True)
# ---- 3. closing prices + official results, in chunks of market ids ----
types=sorted(cal.market_type.unique()); parts=[]
CH=4000
for i in range(0,len(ids),CH):
    chunk=ids[i:i+CH]
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_type, market_time, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_id = ANY(%s) AND market_type = ANY(%s) AND NOT inplay AND ltp>1 AND ltp<1000
                 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res
                 FROM bf_hist_result WHERE market_id = ANY(%s) AND status IN ('WINNER','LOSER')),
         j AS (SELECT pre.market_id, pre.market_type, pre.market_time, pre.close_ltp::float8 AS close_ltp, res.won, res.n_res,
                      count(*) OVER (PARTITION BY pre.market_id) AS n_pre, sum(1/pre.close_ltp::float8) OVER (PARTITION BY pre.market_id) AS book
               FROM pre JOIN res USING (market_id, sel))
    SELECT market_id, market_type, market_time, close_ltp, won FROM j WHERE n_pre=n_res AND n_res>=2 AND book BETWEEN 0.95 AND 1.25""",(chunk,types,chunk))
    rows=cur.fetchall(); con.commit()
    if rows: parts.append(pd.DataFrame(rows,columns=['market_id','market_type','market_time','close_ltp','won']))
    if (i//CH)%5==0: print(f"  chunk {i//CH+1}/{(len(ids)+CH-1)//CH}: rows so far {sum(len(p) for p in parts)}  ({time.time()-T0:.0f}s)",flush=True)
df=pd.concat(parts,ignore_index=True); del parts; gc.collect()
nw=df.groupby('market_id').won.transform('sum'); drop1=df.loc[nw!=1,'market_id'].nunique(); df=df[nw==1].copy()
df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id').p_raw.transform('sum')
df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int)
mt=pd.to_datetime(df.market_time,utc=True)
print(f"unseen complete-book Soccer markets: {df.market_id.nunique()} ({len(df)} runner-rows), dropped no-single-winner {drop1}; market_time {mt.min():%Y-%m-%d}..{mt.max():%Y-%m-%d}",flush=True)
print("by month:",mt.dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),flush=True)
MED=mt.quantile(0.5); df['h2']=(mt>=MED).values; print(f"halves split at {MED:%Y-%m-%d %H:%M}",flush=True)
df=df.merge(cal[['market_type','band','lo','hi','n_is','rate_is','p_is','e_is','side_back','passed']],on=['market_type','band'],how='inner')
sb=df.side_back.values; w=df.won.values; cl=df.close_ltp.values
df['pnl']=pnl(sb,w,tick_down(cl),tick_up(cl))
df['pnl0']=pnl(sb,w,cl,cl)                                  # reading only: at the print, no tick
rs=rng.random(len(df))<0.5; df['ctrl']=pnl(rs,w,tick_down(cl),tick_up(cl))
def line(g,name):
    n=len(g)
    if n==0: return None
    h1=g[~g.h2].pnl; h2=g[g.h2].pnl; pm=g.groupby('market_id').pnl.sum()
    return dict(name=name,n=n,mk=g.market_id.nunique(),mean=g.pnl.mean(),t=tstat(g.pnl),tm=tstat(pm),h1=h1.mean() if len(h1) else float('nan'),
                h2=h2.mean() if len(h2) else float('nan'),n1=len(h1),n2=len(h2),at0=g.pnl0.mean(),ctrl=g.ctrl.mean(),
                won=g.won.mean(),imp=g.p.mean(),e_is=g.e_is.mean())
def show(L):
    print(f"{L['name']:<52} n {L['n']:>6} mk {L['mk']:>6} per10 {L['mean']:+.3f} t {L['t']:+.2f} t_mkt {L['tm']:+.2f} h1 {L['h1']:+.3f} ({L['n1']}) h2 {L['h2']:+.3f} ({L['n2']}) | won {L['won']:.4f} v imp {L['imp']:.4f} (edge {L['won']-L['imp']:+.4f} v e_is {L['e_is']:+.4f}) | at print {L['at0']:+.3f} ctrl {L['ctrl']:+.3f}",flush=True)
print("\n== PRIMARY: PASSED cells pooled ==",flush=True)
P=line(df[df.passed],"PASSED ALL"); show(P) if P else print("no trades in passed cells")
for s,g in df[df.passed].groupby('side_back'):
    show(line(g,f"PASSED {'BACK' if s else 'LAY'}"))
print("\n== ALL map cells n_is>=300, pooled ==",flush=True)
A=line(df[df.n_is>=300],"MAP ALL n_is>=300"); show(A)
print("\n== per PASSED cell ==",flush=True)
lines=[]
for (m,b),g in df[df.passed].groupby(['market_type','band']):
    L=line(g,f"P {m} p{g.lo.iloc[0]:.2f}-{g.hi.iloc[0]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}"); show(L); lines.append(L)
print("\n== every map cell n_is>=300 with unseen n>=300, top 15 by t_mkt ==",flush=True)
allc=[]
for (m,b),g in df[df.n_is>=300].groupby(['market_type','band']):
    if len(g)>=300: allc.append(line(g,f"{m} p{g.lo.iloc[0]:.2f}-{g.hi.iloc[0]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}{' *P' if g.passed.iloc[0] else ''}"))
allc.sort(key=lambda L:-L['tm'])
for L in allc[:15]: show(L)
print(f"cells with unseen n>=300: {len(allc)}; positive {sum(L['mean']>0 for L in allc)}; edge sign agrees with e_is on {sum((L['won']-L['imp'])*L['e_is']>0 for L in allc)}",flush=True)
print("\n== SURVIVORS (n>=300, n per half>=150, per10>=+0.15, h1>0, h2>0, t_mkt>=3.5) ==",flush=True)
cand=([P] if P else [])+lines+allc; seen=set(); nsurv=0
for L in cand:
    if L['name'] in seen: continue
    seen.add(L['name'])
    if L['n']>=300 and L['n1']>=150 and L['n2']>=150 and L['mean']>=0.15 and L['h1']>0 and L['h2']>0 and L['tm']>=3.5:
        show(L); nsurv+=1
print(f"survivors: {nsurv}  ({time.time()-T0:.0f}s)",flush=True)
PY
