#!/bin/bash
set -o pipefail
# 499_calib_fresh_ou45 (Finder 2026-11-09, about 10:15 UTC, queue item 487 re-run, Finder's own, data-led: fair-price map residuals).
# Same rule as jobs/499_calib_fresh_unseen.sh (pushed in the queue, commit c123e7a, before any price was read), cut to ONE type a night as the
# item's NO RESULT note asks: OVER_UNDER_45, the type holding both of item 486's money cells. Map = /root/pe-sports/team/fairprice_v0.py with
# one change: a market counts only if EVERY runner's last pre-off print is within 10 min of market_time ("fresh close").
# FIT = OU4.5 Soccer markets whose file was loaded on or before the 486 map's built_at (finder_calib_snap_1109), all seasons on the box;
# IS/OOS = fit set's own date median; cells passed by job 538's Verifier rule (n_is>=300, n_oos>=100, same sign, |e_is|>=0.01, |e_oos|>=0.005).
# SCORED on item 486's unseen markets (finder_unseen_mk_1109), fresh closes only. Markets loaded after the build but not in that table are dropped.
# Back £10 / lay liability £10, one tick adverse, 2% on profit, official result (bf_hist_result); t by market; halves by unseen date median.
# Run-time fix from the note: the closes are pulled ONCE, by half-year market_time chunks on the (sport, market_type, market_time) index,
# progress printed per chunk, into a local table this job creates (finder_ou45_close_1109); no id-list pulls, no full multi-type scan.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys, math, time, gc, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time(); COMM=0.02; rng=np.random.default_rng(13); FRESH_MIN=10; MT='OVER_UNDER_45'
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
# known answers: ladder steps at 2, 3 and the 1.01 floor; back win 1.99 -> 0.99*10*0.98 = 9.702; lay win at 2.02 -> 10/1.02*0.98; lay loss -10
assert list(tick_up([2.0,3.0,1.01,1.05]))==[2.02,3.05,1.02,1.06] and list(tick_down([2.0,3.0,1.01,1.06]))==[1.99,2.98,1.01,1.05]
t=pnl(np.array([True,False,False,True]),np.array([1,0,1,0]),np.array([1.99,0,0,20.0]),np.array([0,2.02,2.02,0]))
assert np.allclose(t,[9.702,10/1.02*0.98,-10.0,-10.0]), t
# lay at 1.06 that wins pays 10/0.06*0.98 = 163.33 (the Under-4.5 tail the 486 report warned about)
assert abs(pnl(np.array([False]),np.array([0]),np.array([0]),np.array([1.06]))[0]-163.3333)<1e-3
print("unit checks PASS",flush=True)
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT max(built_at) FROM finder_calib_snap_1109"); B=cur.fetchone()[0]
cur.execute("""CREATE TEMP TABLE late_ids AS SELECT DISTINCT substring(path from '([0-9]+\\.[0-9]+)\\.bz2$') AS market_id
               FROM bf_hist_other_files WHERE loaded_at > %s""",(B,))
cur.execute("CREATE TEMP TABLE uns AS SELECT DISTINCT market_id FROM finder_unseen_mk_1109 WHERE market_id IS NOT NULL")
cur.execute("ANALYZE late_ids; ANALYZE uns"); con.commit()
cur.execute("SELECT (SELECT count(*) FROM late_ids),(SELECT count(*) FROM uns),(SELECT count(*) FROM uns u WHERE NOT EXISTS (SELECT 1 FROM late_ids l WHERE l.market_id=u.market_id))")
nl,nu,nbad=cur.fetchone(); print(f"map built {B} | ids loaded after build {nl} | unseen ids {nu} | unseen ids NOT loaded after build {nbad} (must be 0)",flush=True)
assert nbad==0
cur.execute("SELECT min(market_time), max(market_time) FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s",(MT,)); lo,hi=cur.fetchone()
print(f"{MT} market_time {lo} .. {hi}  ({time.time()-T0:.0f}s)",flush=True)
cur.execute("""DROP TABLE IF EXISTS finder_ou45_close_1109""")   # this job's own table
cur.execute("""CREATE TABLE finder_ou45_close_1109 (market_id text, sel text, market_time timestamptz, close_ts timestamptz, close_ltp float8)"""); con.commit()
starts=pd.date_range(pd.Timestamp(lo).tz_convert('UTC').normalize()-pd.offsets.MonthBegin(1), pd.Timestamp(hi).tz_convert('UTC')+pd.offsets.MonthBegin(1), freq='6MS')
for a,b in zip(starts[:-1],starts[1:]):
    t1=time.time()
    cur.execute("""INSERT INTO finder_ou45_close_1109
       SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, ts, ltp::float8
       FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND market_time >= %s AND market_time < %s
         AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC""",(MT,a.to_pydatetime(),b.to_pydatetime()))
    print(f"  chunk {a:%Y-%m}..{b:%Y-%m}: {cur.rowcount} runner closes  ({time.time()-t1:.0f}s, total {time.time()-T0:.0f}s)",flush=True); con.commit()
cur.execute("CREATE INDEX ON finder_ou45_close_1109 (market_id); ANALYZE finder_ou45_close_1109"); con.commit()
cur.execute("""
  WITH res AS (SELECT r.market_id, r.sel, (r.status='WINNER')::int AS won, count(*) OVER (PARTITION BY r.market_id) AS n_res
               FROM bf_hist_result r WHERE r.market_id IN (SELECT market_id FROM finder_ou45_close_1109) AND r.status IN ('WINNER','LOSER')),
       j AS (SELECT c.market_id, c.market_time, c.close_ts, c.close_ltp, res.won, res.n_res, count(*) OVER (PARTITION BY c.market_id) AS n_pre,
                    sum(1/c.close_ltp) OVER (PARTITION BY c.market_id) AS book,
                    min(c.close_ts) OVER (PARTITION BY c.market_id) >= c.market_time - interval '%s minutes' AS fresh
             FROM finder_ou45_close_1109 c JOIN res USING (market_id, sel))
  SELECT j.market_id, j.market_time, j.close_ltp, j.won, j.fresh, (u.market_id IS NOT NULL) AS unseen, (l.market_id IS NOT NULL) AS late
  FROM j LEFT JOIN uns u ON u.market_id=j.market_id LEFT JOIN late_ids l ON l.market_id=j.market_id
  WHERE n_pre=n_res AND n_res>=2 AND book BETWEEN 0.95 AND 1.25""",(FRESH_MIN,))
df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','close_ltp','won','fresh','unseen','late']); con.commit()
print(f"complete-book runner-rows {len(df)} on {df.market_id.nunique()} markets  ({time.time()-T0:.0f}s)",flush=True)
df=df[df.unseen | ~df.late]                       # drop markets loaded after the build that are not in 486's unseen set
nw=df.groupby('market_id',sort=False).won.transform('sum'); df=df[nw==1].copy()
df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')
df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int)
fit=df[~df.unseen]; mk=fit.drop_duplicates('market_id'); mku=df[df.unseen].drop_duplicates('market_id')
assert not set(fit.market_id) & set(df[df.unseen].market_id)
mtu=pd.to_datetime(mku.market_time,utc=True)
print(f"stale closes (any runner's last pre-off print >{FRESH_MIN} min before market_time): fit {1-mk.fresh.mean():.1%} of {len(mk)} mkts; unseen {1-mku.fresh.mean():.1%} of {len(mku)} mkts ({mtu.min():%Y-%m-%d}..{mtu.max():%Y-%m-%d})",flush=True)
fit=fit[fit.fresh].copy()
mtime=pd.to_datetime(fit.market_time,utc=True); SPLIT=mtime.quantile(0.5); fit['oos']=(mtime>=SPLIT).values
print(f"fresh fit: {fit.market_id.nunique()} mkts {mtime.min():%Y-%m-%d}..{mtime.max():%Y-%m-%d}, IS/OOS split {SPLIT:%Y-%m-%d}",flush=True)
cal=fit.groupby(['band','oos']).agg(n=('won','size'),rate=('won','mean'),pm=('p','mean')).reset_index()
IS=cal[~cal.oos].set_index('band'); OO=cal[cal.oos].set_index('band'); CELLS=[]
for b,r in IS.iterrows():
    if b not in OO.index: continue
    o=OO.loc[b]; eis=r.rate-r.pm; eoo=o.rate-o.pm
    ok=(r.n>=300) and (o.n>=100) and ((eis>0)==(eoo>0)) and abs(eis)>=0.01 and abs(eoo)>=0.005
    CELLS.append(dict(band=int(b),n_is=int(r.n),e_is=float(eis),n_oos=int(o.n),e_oos=float(eoo),passed=ok,side_back=bool(eis>0)))
C=pd.DataFrame(CELLS); print(f"\nfresh-close {MT} map: {len(C)} cells, passed {int(C.passed.sum())}",flush=True)
for r in C.itertuples():
    print(f"   {'PASSED' if r.passed else 'cell  '} p{edges[r.band]:.2f}-{edges[r.band+1]:.2f} {'BACK' if r.side_back else 'LAY '} n_is {r.n_is:>6} e_is {r.e_is:+.4f} n_oos {r.n_oos:>6} e_oos {r.e_oos:+.4f}",flush=True)
def score(U):
    S=U.merge(C,on='band',how='inner')
    mt_=pd.to_datetime(S.market_time,utc=True); S['h2']=(mt_>=mt_.quantile(0.5)).values
    sb=S.side_back.values; w=S.won.values; cl=S.close_ltp.values
    S['pnl']=pnl(sb,w,tick_down(cl),tick_up(cl)); S['pnl0']=pnl(sb,w,cl,cl); S['ctrl']=pnl(rng.random(len(S))<0.5,w,tick_down(cl),tick_up(cl))
    return S
S=score(df[df.unseen & df.fresh].copy()); assert S.groupby('market_id').won.sum().le(1).all()
assert set(S.market_id) <= set(df[df.unseen & df.fresh].market_id)
SA=score(df[df.unseen].copy())     # reading only: same fresh-built cells, scored on ALL unseen closes, stale included
mt_=pd.to_datetime(S.market_time,utc=True)
print(f"unseen fresh-close runner-rows in map cells: {len(S)} on {S.market_id.nunique()} markets, {mt_.min():%Y-%m-%d}..{mt_.max():%Y-%m-%d}, halves at {mt_.quantile(0.5):%Y-%m-%d}",flush=True)
def line(g,name):
    h1=g[~g.h2].pnl; h2=g[g.h2].pnl; pm=g.groupby('market_id').pnl.sum()
    return dict(name=name,n=len(g),mk=g.market_id.nunique(),mean=g.pnl.mean(),t=tstat(g.pnl),tm=tstat(pm),h1=h1.mean() if len(h1) else float('nan'),
                h2=h2.mean() if len(h2) else float('nan'),n1=len(h1),n2=len(h2),at0=g.pnl0.mean(),ctrl=g.ctrl.mean(),won=g.won.mean(),imp=g.p.mean(),e_is=g.e_is.mean())
def show(L):
    print(f"{L['name']:<44} n {L['n']:>6} mk {L['mk']:>6} per10 {L['mean']:+.3f} t {L['t']:+.2f} t_mkt {L['tm']:+.2f} h1 {L['h1']:+.3f} ({L['n1']}) h2 {L['h2']:+.3f} ({L['n2']}) | won {L['won']:.4f} v imp {L['imp']:.4f} (e_is {L['e_is']:+.4f}) | at print {L['at0']:+.3f} ctrl {L['ctrl']:+.3f}",flush=True)
print("\n== PRIMARY: fresh-close PASSED cells pooled, unseen fresh closes ==",flush=True)
P=line(S[S.passed],"FRESH PASSED ALL") if S.passed.any() else None
show(P) if P else print("no unseen trades in passed cells (or no passed cells)")
lines=[]
if P:
    for s,g in S[S.passed].groupby('side_back'): L=line(g,f"FRESH PASSED {'BACK' if s else 'LAY'}"); show(L); lines.append(L)
print("\n== control: every fresh-close cell n_is>=300 ==",flush=True); A=line(S[S.n_is>=300],"FRESH MAP ALL n_is>=300"); show(A)
print("\n== every cell, unseen fresh closes, by t_mkt ==",flush=True); allc=[]
for b,g in S.groupby('band'):
    allc.append(line(g,f"{MT} p{edges[b]:.2f}-{edges[b+1]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}{' *P' if g.passed.iloc[0] else ''}"))
allc.sort(key=lambda L:-L['tm'])
for L in allc[:15]: show(L)
print("\n== reading only: the same cells scored on ALL unseen closes, stale included ==",flush=True)
if SA.passed.any(): show(line(SA[SA.passed],"ALL-CLOSE PASSED ALL"))
show(line(SA,"ALL-CLOSE MAP ALL"))
for b,g in SA.groupby('band'):
    if g.passed.iloc[0]: show(line(g,f"ALL-CLOSE p{edges[b]:.2f}-{edges[b+1]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'} *P"))
print("\n== SURVIVORS (n>=300, n per half>=150, per10>=+0.15, h1>0, h2>0, t_mkt>=3.5) ==",flush=True)
nsurv=0; seen=set()
for L in ([P] if P else [])+lines+allc:
    if L['name'] in seen: continue
    seen.add(L['name'])
    if L['n']>=300 and L['n1']>=150 and L['n2']>=150 and L['mean']>=0.15 and L['h1']>0 and L['h2']>0 and L['tm']>=3.5: show(L); nsurv+=1
print(f"survivors: {nsurv}  ({time.time()-T0:.0f}s)",flush=True)
PY
