#!/bin/bash
set -o pipefail
# 499_inplay_map_unseen (Finder 2026-11-09, about 08:30 UTC run, lane default/top, queue item 488, Finder's own, data-led: fair-price map residuals,
# the in-play calibration table, per the COO decision of 9 Nov). Rule pushed in the queue before this job read an unseen price.
# The in-play fair-price map (fair_price_calib_inplay, H1b, built 8 Nov 09:21-09:26 UTC by jobs/525's fairprice_inplay.py) scored on Soccer markets
# it NEVER saw: their BASIC file was loaded (bf_hist_other_files.loaded_at) after the map's max(built_at) and before this job, and not loaded earlier.
# Map cell = market_type@band (band b = minutes [1,16),[16,31),...,[76,91) after market_time) x 18 probability bands; side toward the IS rate.
# Passed cells: job 538's Verifier rule on the snapshot: n_is>=300, n_oos>=100, same sign of (rate-implied) IS and OOS, |e_is|>=0.01, |e_oos|>=0.005.
# Engines, decision at T = band end (16/31/46/61/76/91 min after market_time):
#   FRESH (PRIMARY): each runner's last print in [T-5, T) must exist; complete book on those prints; ENTRY at the runner's FIRST print in [T, T+3)
#                    one tick adverse (cell read strictly before T, entry strictly at/after T, asserted). No entry print = no trade (counted).
#   MAP (reading only): the map's own engine, last print anywhere in the band, entered AT that print one tick adverse, however old.
# Book: every runner with an official WINNER/LOSER (bf_hist_result) priced, >=2 runners, raw book 0.90-1.30, exactly one winner; p = normalised 1/ltp.
# Stakes per the Finder brief: back stake £10; lay LIABILITY £10; 2% on profit; held to the official result (nothing dropped at settlement).
# Bar: n>=300 (>=150 a half), mean>=+0.15, both halves (market_time median) positive, t>=3.5 on per-GAME sums (event_id; one game feeds many
# markets, bands and runners, so per-trade t is inflated; per-trade and per-market t also printed). Random-side control.
# Sample: market ids shuffled (seed 5), pulled in chunks until a 40-min wall-clock cap; if the cap stops it, the share read is printed.
# Writes only its own tables finder_ipcal_snap_1109 and finder_ipunseen_mk_1109.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys, math, time, gc, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time(); CAP=40*60
COMM=0.02; rng=np.random.default_rng(13)
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
# ---- unit checks with known answers (fail loudly) ----
assert list(tick_up([2.0,3.0,1.01,5.9]))==[2.02,3.05,1.02,6.0], tick_up([2.0,3.0,1.01,5.9])
assert list(tick_down([2.0,3.0,1.01,6.0]))==[1.99,2.98,1.01,5.9], tick_down([2.0,3.0,1.01,6.0])
t=pnl(np.array([True,True,False,False]),np.array([1,0,0,1]),np.array([1.99,1.99,0,0]),np.array([0,0,2.02,2.02]))
assert np.allclose(t,[9.702,-10.0,10/1.02*0.98,-10.0]), t
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
assert pd.cut(pd.Series([0.0,0.0299,0.03,0.5,0.95,1.0]),edges,right=False,labels=False).tolist()==[0,0,1,11,17,17]
print("unit checks: tick ladder, P&L (back 1.99 win +9.702, lay 2.02 lose +9.608, liability -10), probability bands PASS",flush=True)
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# ---- 1. snapshot the in-play map ----
cur.execute("DROP TABLE IF EXISTS finder_ipcal_snap_1109; CREATE TABLE finder_ipcal_snap_1109 AS SELECT * FROM fair_price_calib_inplay"); con.commit()
cal=pd.read_sql("SELECT market_type mtb, band, band_lo::float8 lo, band_hi::float8 hi, n_is, rate_is::float8 rate_is, p_mean_is::float8 p_is, n_oos, rate_oos::float8 rate_oos, p_mean_oos::float8 p_oos, built_at FROM finder_ipcal_snap_1109",con)
B=cal.built_at.max(); print(f"in-play map snapshot: {len(cal)} cells, built {cal.built_at.min()} .. {B}",flush=True)
cal['e_is']=cal.rate_is-cal.p_is; cal['e_oos']=cal.rate_oos-cal.p_oos; cal['side_back']=cal.e_is>0
cal['passed']=(cal.n_is>=300)&(cal.n_oos>=100)&cal.rate_oos.notna()&((cal.e_is>0)==(cal.e_oos>0))&(cal.e_is.abs()>=0.01)&(cal.e_oos.abs()>=0.005)
cal=cal[cal.n_is>=300].copy()
types=sorted(set(m.split('@m')[0] for m in cal.mtb))
print(f"cells n_is>=300: {len(cal)}; passed by job 538's rule: {int(cal.passed.sum())} (BACK {int((cal.passed&cal.side_back).sum())}, LAY {int((cal.passed&~cal.side_back).sum())}); base types {len(types)}: {types}",flush=True)
# ---- 2. unseen Soccer market ids ----
cur.execute("SELECT now()"); CUT=cur.fetchone()[0]
cur.execute("""DROP TABLE IF EXISTS finder_ipunseen_mk_1109;
CREATE TABLE finder_ipunseen_mk_1109 AS
  SELECT substring(path from '([0-9]+\\.[0-9]+)\\.bz2$') AS market_id, min(loaded_at) loaded_at FROM bf_hist_other_files
  WHERE loaded_at > %s AND loaded_at <= %s GROUP BY 1""",(B,CUT)); con.commit()
cur.execute("SELECT count(*), count(market_id) FROM finder_ipunseen_mk_1109"); print("unseen files->ids:",cur.fetchone(),"cut",CUT,flush=True)
cur.execute("""DELETE FROM finder_ipunseen_mk_1109 u USING bf_hist_other_files f
   WHERE f.loaded_at <= %s AND substring(f.path from '([0-9]+\\.[0-9]+)\\.bz2$') = u.market_id""",(B,))
print("unseen ids also loaded before the build (removed):",cur.rowcount,flush=True); con.commit()
cur.execute("""SELECT u.market_id FROM finder_ipunseen_mk_1109 u
   WHERE u.market_id IS NOT NULL AND EXISTS (SELECT 1 FROM bf_hist_other b WHERE b.sport='Soccer' AND b.market_id=u.market_id AND b.market_type = ANY(%s))""",(types,))
ids=sorted(r[0] for r in cur.fetchall()); con.commit()
rng_ids=np.random.default_rng(5); ids=list(np.array(ids)[rng_ids.permutation(len(ids))]) if ids else []
print(f"unseen Soccer market ids in map types: {len(ids)}  ({time.time()-T0:.0f}s)",flush=True)
# ---- 3. per chunk: band-last print (cell) and first print in [T,T+3) (entry), official results ----
Q="""
WITH x AS (SELECT market_id, event_id, market_type, market_time, sel, ts, ltp::float8 ltp, EXTRACT(EPOCH FROM (ts-market_time))/60.0 AS mn
           FROM bf_hist_other WHERE sport='Soccer' AND market_id = ANY(%s) AND market_type = ANY(%s) AND inplay AND ltp>1 AND ltp<1000
             AND ts>market_time AND ts<market_time+interval '94 minutes'),
     c AS (SELECT DISTINCT ON (market_id, sel, mb) market_id, event_id, market_type, market_time, sel, mb, ltp c_ltp, mn c_mn
           FROM (SELECT x.*, width_bucket(mn, ARRAY[1,16,31,46,61,76,91]::float8[]) mb FROM x) y WHERE mb BETWEEN 1 AND 6
           ORDER BY market_id, sel, mb, ts DESC),
     e AS (SELECT DISTINCT ON (market_id, sel, eb) market_id, sel, eb, ltp e_ltp, mn e_mn
           FROM (SELECT x.*, CASE WHEN mn>=16 AND (mn-16-15*floor((mn-16)/15))<3 THEN floor((mn-16)/15)::int+1 END eb FROM x) y
           WHERE eb BETWEEN 1 AND 6 ORDER BY market_id, sel, eb, ts ASC)
SELECT c.market_id, c.event_id, c.market_type, c.market_time, c.sel, c.mb, c.c_ltp, c.c_mn, e.e_ltp, e.e_mn
FROM c LEFT JOIN e ON e.market_id=c.market_id AND e.sel=c.sel AND e.eb=c.mb"""
calk=cal.assign(key=cal.mtb+'#'+cal.band.astype(str))[['key','lo','hi','n_is','e_is','side_back','passed']].reset_index(drop=True)
calk['kid']=np.arange(len(calk),dtype=np.int32)
outF=[]; outM=[]; stat=dict(read=0,mk=0,mkF=0,noentry=0,noentry_won=0,noentry_back=0); CH=3000; stopped=False
for i in range(0,len(ids),CH):
    if time.time()-T0>CAP: stopped=True; break
    chunk=[str(x) for x in ids[i:i+CH]]
    cur.execute(Q,(chunk,types)); rows=cur.fetchall()
    cur.execute("SELECT market_id, sel, (status='WINNER')::int, count(*) OVER (PARTITION BY market_id) FROM bf_hist_result WHERE market_id = ANY(%s) AND status IN ('WINNER','LOSER')",(chunk,))
    res=pd.DataFrame(cur.fetchall(),columns=['market_id','sel','won','n_res']); con.commit()
    stat['read']+=len(chunk)
    if not rows or res.empty: continue
    d=pd.DataFrame(rows,columns=['market_id','event_id','market_type','market_time','sel','mb','c_ltp','c_mn','e_ltp','e_mn'])
    d['sel']=d.sel.astype(res.sel.dtype)
    nw=res.groupby('market_id').won.transform('sum'); res=res[nw==1]
    d=d.merge(res,on=['market_id','sel'],how='inner')
    d['T']=d.mb*15+1.0
    assert (d.c_mn<d['T']).all() and (d.c_mn>=d['T']-15).all()
    assert d.e_mn.isna().all() or ((d.e_mn.dropna()>=d.loc[d.e_mn.notna(),'T'])&(d.e_mn.dropna()<d.loc[d.e_mn.notna(),'T']+3)).all()
    d['fresh']=d.c_mn>=d['T']-5
    g=d.groupby(['market_id','mb'])
    d['inv']=1/d.c_ltp; d['n_pre']=g.sel.transform('size'); d['n_fr']=g.fresh.transform('sum'); d['book']=g.inv.transform('sum')
    ok=(d.n_pre==d.n_res)&(d.n_res>=2)&d.book.between(0.90,1.30)
    d=d[ok].copy()
    d['p']=(1/d.c_ltp)/d.book
    d['pb']=pd.cut(d.p,edges,right=False,labels=False).astype(int)
    d['key']=d.market_type+'@m'+d.mb.astype(str)+'#'+d.pb.astype(str)
    d=d.merge(calk,on='key',how='inner').drop(columns=['key'])
    d['market_id']=(pd.factorize(d.market_id)[0]+i*10).astype(np.int64); d['event_id']=pd.to_numeric(d.event_id).astype(np.int64)
    stat['mk']+=d.market_id.nunique()
    # MAP engine (reading): enter at the cell print, however old
    m=d[['market_id','event_id','market_time','kid','mb','passed','side_back','n_is','e_is','won','p','c_ltp','fresh']].copy()
    outM.append(m)
    # FRESH engine (primary): whole book fresh, entry at next print
    f=d[d.n_fr==d.n_res].copy(); stat['mkF']+=f.market_id.nunique()
    ne=f.e_ltp.isna(); stat['noentry']+=int(ne.sum()); stat['noentry_won']+=int(f.won[ne].sum()); stat['noentry_back']+=int(f.side_back[ne].sum())
    f=f[~ne]
    outF.append(f[['market_id','event_id','market_time','kid','mb','passed','side_back','n_is','e_is','won','p','e_ltp','c_ltp']].copy())
    del d,m,f,rows,res; gc.collect()
    if (i//CH)%5==0: print(f"  chunk {i//CH+1}/{(len(ids)+CH-1)//CH}: FRESH trades {sum(len(x) for x in outF)} MAP {sum(len(x) for x in outM)}  ({time.time()-T0:.0f}s)",flush=True)
print(f"read {stat['read']} of {len(ids)} unseen ids ({100*stat['read']/max(1,len(ids)):.1f}%){' -- STOPPED BY THE 40-MIN CAP, a random sample' if stopped else ''}; markets with a complete in-map book {stat['mk']}, fully fresh {stat['mkF']}",flush=True)
print(f"FRESH no entry print in [T,T+3): {stat['noentry']} runner-bands, won {stat['noentry_won']}, side BACK {stat['noentry_back']} (not traded)",flush=True)
F=pd.concat(outF,ignore_index=True); M=pd.concat(outM,ignore_index=True); del outF,outM; gc.collect()
print(f"MAP engine rows {len(M)}; share of cell prints over 5 min old: {1-M.fresh.mean():.3f}",flush=True)
def prep(X,px):
    sb=X.side_back.values; w=X.won.values; c=X[px].values
    X['pnl']=pnl(sb,w,tick_down(c),tick_up(c)); X['pnl0']=pnl(sb,w,c,c)
    X['ctrl']=pnl(rng.random(len(X))<0.5,w,tick_down(c),tick_up(c))
    mt=pd.to_datetime(X.market_time,utc=True); X['h2']=(mt>=mt.quantile(0.5)).values
    return mt
mtF=prep(F,'e_ltp'); mtM=prep(M,'c_ltp')
print(f"FRESH trades {len(F)} on {F.market_id.nunique()} markets, {F.event_id.nunique()} games; market_time {mtF.min():%Y-%m-%d}..{mtF.max():%Y-%m-%d}; halves at {mtF.quantile(0.5):%Y-%m-%d %H:%M}",flush=True)
print("FRESH by month:",mtF.dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),flush=True)
def line(g,name):
    n=len(g)
    if n==0: return None
    h1=g[~g.h2].pnl; h2=g[g.h2].pnl
    return dict(name=name,n=n,mk=g.market_id.nunique(),gm=g.event_id.nunique(),mean=g.pnl.mean(),t=tstat(g.pnl),tm=tstat(g.groupby('market_id').pnl.sum()),
                tg=tstat(g.groupby('event_id').pnl.sum()),h1=h1.mean() if len(h1) else float('nan'),h2=h2.mean() if len(h2) else float('nan'),n1=len(h1),n2=len(h2),
                at0=g.pnl0.mean(),ctrl=g.ctrl.mean(),won=g.won.mean(),imp=g.p.mean(),e_is=g.e_is.mean())
def show(L):
    print(f"{L['name']:<50} n {L['n']:>7} mk {L['mk']:>6} gm {L['gm']:>5} per10 {L['mean']:+.3f} t {L['t']:+.2f} t_mkt {L['tm']:+.2f} t_game {L['tg']:+.2f} h1 {L['h1']:+.3f} ({L['n1']}) h2 {L['h2']:+.3f} ({L['n2']}) | won {L['won']:.4f} v imp {L['imp']:.4f} (edge {L['won']-L['imp']:+.4f} v e_is {L['e_is']:+.4f}) | no tick {L['at0']:+.3f} ctrl {L['ctrl']:+.3f}",flush=True)
def nm(g): k=g.key.iloc[0]; return f"{k.split('#')[0]} p{g.lo.iloc[0]:.2f}-{g.hi.iloc[0]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}{' *P' if g.passed.iloc[0] else ''}"
KEY=calk.set_index('kid')
for X in (F,M):
    X['lo']=KEY.lo.reindex(X.kid).values; X['hi']=KEY.hi.reindex(X.kid).values
def nm(g): k=KEY.key.loc[g.kid.iloc[0]]; return f"{k.split('#')[0]} p{g.lo.iloc[0]:.2f}-{g.hi.iloc[0]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}{' *P' if g.passed.iloc[0] else ''}"
print("\n== PRIMARY: FRESH engine, PASSED cells pooled ==",flush=True)
P=line(F[F.passed],"FRESH PASSED ALL"); show(P) if P else print("no trades in passed cells")
for s,g in F[F.passed].groupby('side_back'): show(line(g,f"FRESH PASSED {'BACK' if s else 'LAY'}"))
for b,g in F[F.passed].groupby('mb'): show(line(g,f"FRESH PASSED band {b}"))
show(line(F,"FRESH ALL cells n_is>=300"))
print("\n== READING: MAP engine (map's own: last print in band, entered at it) ==",flush=True)
show(line(M[M.passed],"MAP PASSED ALL")); show(line(M[M.passed&M.fresh],"MAP PASSED cell print <=5 min old")); show(line(M[M.passed&~M.fresh],"MAP PASSED cell print >5 min old")); show(line(M,"MAP ALL cells n_is>=300"))
print("\n== FRESH per PASSED cell with n>=300, top 15 by t_game ==",flush=True)
pl=[line(g,nm(g)) for k,g in F[F.passed].groupby('kid') if len(g)>=300]; pl.sort(key=lambda L:-L['tg'])
for L in pl[:15]: show(L)
print(f"passed cells with FRESH n>=300: {len(pl)}; positive {sum(L['mean']>0 for L in pl)}",flush=True)
print("\n== FRESH every cell n_is>=300 with n>=300, top 15 by t_game ==",flush=True)
al=[line(g,nm(g)) for k,g in F.groupby('kid') if len(g)>=300]; al.sort(key=lambda L:-L['tg'])
for L in al[:15]: show(L)
print(f"cells with FRESH n>=300: {len(al)}; positive {sum(L['mean']>0 for L in al)}; edge sign agrees with e_is on {sum((L['won']-L['imp'])*L['e_is']>0 for L in al)}",flush=True)
print("\n== SURVIVORS (FRESH; n>=300, n per half>=150, per10>=+0.15, h1>0, h2>0, t_game>=3.5) ==",flush=True)
seen=set(); ns=0
for L in ([P] if P else [])+pl+al:
    if L['name'] in seen: continue
    seen.add(L['name'])
    if L['n']>=300 and L['n1']>=150 and L['n2']>=150 and L['mean']>=0.15 and L['h1']>0 and L['h2']>0 and L['tg']>=3.5: show(L); ns+=1
print(f"survivors: {ns}  ({time.time()-T0:.0f}s)",flush=True)
PY
