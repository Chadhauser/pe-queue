#!/bin/bash
set -o pipefail
# 499_calib_fresh_unseen (Finder 2026-11-09, about 08:00 UTC, same run as item 486, queue item 487, Finder's own, data-led: fair-price map residuals).
# Rule pushed in the queue (commit c123e7a) before this job read a price. Next door of item 486, which found the map's "close" is the last pre-off
# print however old (Over 4.5 tail: 64.5% of closes over an hour old, stale ones won 0.109 v 0.067 implied, fresh ones fair).
# Map rebuilt as /root/pe-sports/team/fairprice_v0.py with ONE change: a market counts only if EVERY runner's last pre-off print is within 10 min
# of market_time ("fresh close"). FIT set = Soccer markets whose BASIC file was loaded on or before the 486 map's built_at (8 Nov 21:10 UTC);
# IS/OOS = date median of the fit set; cells passed by job 538's Verifier rule (n_is>=300, n_oos>=100, same sign, |e_is|>=0.01, |e_oos|>=0.005).
# SCORED on item 486's unseen markets (finder_unseen_mk_1109), fresh closes only. Markets loaded after 486's cut are dropped from both.
# Back £10 / lay liability £10, one tick adverse, 2% on profit, official result; t by market; halves by unseen date median; random-side control.
# Also printed for the map owner: share of complete-book markets per type whose close is stale. Writes no tables (temp only).
# CUT (same run, before any result): the first run spent over 10 min on MATCH_ODDS alone (full 38 GB type scan, DISTINCT ON spilling at the
# brief's 64 MB work_mem) and was stopped; to fit the 90-minute run the FIT is now market_time 1 May 2024 to 30 Sep 2026 (index range, the
# LISTFAIL months Nov 2024-Apr 2026 are absent anyway) and only the four types holding most of item 486's passed-cell trades; unseen markets
# are pulled by id as in job 486. The IS/OOS split is the fit window's own date median.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys, math, time, gc, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time(); COMM=0.02; rng=np.random.default_rng(13); FRESH_MIN=10
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
assert list(tick_up([2.0,3.0,1.01]))==[2.02,3.05,1.02] and list(tick_down([2.0,3.0,1.01]))==[1.99,2.98,1.01]
t=pnl(np.array([True,False,False]),np.array([1,0,1]),np.array([1.99,0,0]),np.array([0,2.02,2.02]))
assert np.allclose(t,[9.702,10/1.02*0.98,-10.0]), t
print("unit checks PASS",flush=True)
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT max(built_at) FROM finder_calib_snap_1109"); B=cur.fetchone()[0]
cur.execute("SELECT max(loaded_at) FROM finder_unseen_mk_1109"); CUT=cur.fetchone()[0]
cur.execute("""CREATE TEMP TABLE late_ids AS SELECT DISTINCT substring(path from '([0-9]+\\.[0-9]+)\\.bz2$') AS market_id
               FROM bf_hist_other_files WHERE loaded_at > %s""",(B,))
cur.execute("CREATE TEMP TABLE uns AS SELECT market_id FROM finder_unseen_mk_1109 WHERE market_id IS NOT NULL")
cur.execute("ANALYZE late_ids; ANALYZE uns"); con.commit()
cur.execute("SELECT (SELECT count(*) FROM late_ids),(SELECT count(*) FROM uns)"); print("map built",B,"| ids loaded after build",cur.fetchone(),"(late minus unseen are dropped)",flush=True)
types=['OVER_UNDER_45','MATCH_ODDS','OVER_UNDER_35','FIRST_HALF_GOALS_15']
cur.execute("SELECT market_id FROM uns"); ids=[r[0] for r in cur.fetchall()]
UP=[]
for i in range(0,len(ids),4000):
    ch=ids[i:i+4000]
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, market_type, sel, market_time, ts, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_id = ANY(%s) AND market_type = ANY(%s) AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res FROM bf_hist_result WHERE market_id = ANY(%s) AND status IN ('WINNER','LOSER')),
         j AS (SELECT pre.market_id, pre.market_type, pre.market_time, pre.close_ltp::float8 AS close_ltp, res.won, res.n_res, count(*) OVER (PARTITION BY pre.market_id) AS n_pre,
                      sum(1/pre.close_ltp::float8) OVER (PARTITION BY pre.market_id) AS book,
                      min(pre.ts) OVER (PARTITION BY pre.market_id) >= pre.market_time - interval '%s minutes' AS fresh
               FROM pre JOIN res USING (market_id, sel))
    SELECT market_id, market_type, market_time, close_ltp, won, fresh FROM j WHERE n_pre=n_res AND n_res>=2 AND book BETWEEN 0.95 AND 1.25""",(ch,types,ch,FRESH_MIN))
    r=cur.fetchall(); con.commit()
    if r: UP.append(pd.DataFrame(r,columns=['market_id','market_type','market_time','close_ltp','won','fresh']))
UN=pd.concat(UP,ignore_index=True); del UP
print(f"unseen complete-book rows {len(UN)} on {UN.market_id.nunique()} markets  ({time.time()-T0:.0f}s)",flush=True)
SC=[]; CELLS=[]
for mt in types:
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, ts, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND market_time >= '2024-05-01' AND market_time < '2026-10-01'
                 AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res FROM bf_hist_result WHERE market_type=%s AND status IN ('WINNER','LOSER')),
         j AS (SELECT pre.market_id, pre.market_time, pre.close_ltp::float8 AS close_ltp, res.won, res.n_res, count(*) OVER (PARTITION BY pre.market_id) AS n_pre,
                      sum(1/pre.close_ltp::float8) OVER (PARTITION BY pre.market_id) AS book,
                      min(pre.ts) OVER (PARTITION BY pre.market_id) >= pre.market_time - interval '%s minutes' AS fresh
               FROM pre JOIN res USING (market_id, sel))
    SELECT j.market_id, j.market_time, j.close_ltp, j.won, j.fresh, (u.market_id IS NOT NULL) AS unseen, (l.market_id IS NOT NULL) AS late
    FROM j LEFT JOIN uns u ON u.market_id=j.market_id LEFT JOIN late_ids l ON l.market_id=j.market_id
    WHERE n_pre=n_res AND n_res>=2 AND book BETWEEN 0.95 AND 1.25""",(mt,mt,FRESH_MIN))
    df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','close_ltp','won','fresh','unseen','late']); con.commit()
    df=df[~df.unseen]                                  # fit window holds no unseen 2022 market; guard anyway
    um=UN[UN.market_type==mt].drop(columns='market_type').assign(unseen=True,late=False)
    df=pd.concat([df,um],ignore_index=True)
    df=df[df.unseen | ~df.late]                     # drop markets loaded after 486's cut
    nw=df.groupby('market_id',sort=False).won.transform('sum'); df=df[nw==1].copy()
    df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')
    df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int)
    fit=df[~df.unseen]; mk=fit.drop_duplicates('market_id')
    stale_fit=1-mk.fresh.mean(); mku=df[df.unseen].drop_duplicates('market_id'); stale_u=1-mku.fresh.mean() if len(mku) else float('nan')
    fit=fit[fit.fresh].copy()
    if len(fit)<1000: print(f"  {mt}: fresh fit rows {len(fit)}, skipped",flush=True); continue
    mtime=pd.to_datetime(fit.market_time,utc=True); SPLIT=mtime.quantile(0.5); fit['oos']=(mtime>=SPLIT).values
    cal=fit.groupby(['band','oos']).agg(n=('won','size'),rate=('won','mean'),pm=('p','mean')).reset_index()
    IS=cal[~cal.oos].set_index('band'); OO=cal[cal.oos].set_index('band')
    npass=0
    for b,r in IS.iterrows():
        if b not in OO.index: continue
        o=OO.loc[b]; eis=r.rate-r.pm; eoo=o.rate-o.pm
        ok=(r.n>=300) and (o.n>=100) and ((eis>0)==(eoo>0)) and abs(eis)>=0.01 and abs(eoo)>=0.005
        CELLS.append(dict(market_type=mt,band=int(b),n_is=int(r.n),e_is=float(eis),n_oos=int(o.n),e_oos=float(eoo),passed=ok,side_back=bool(eis>0)))
        npass+=ok
    u=df[df.unseen & df.fresh].copy(); u['market_type']=mt; SC.append(u[['market_id','market_type','market_time','close_ltp','won','p','band']])
    print(f"  {mt}: fit {mk.market_id.nunique()} mkts ({mtime.min():%Y-%m-%d}..{mtime.max():%Y-%m-%d}, split {SPLIT:%Y-%m-%d}), stale closes fit {stale_fit:.1%} unseen {stale_u:.1%}; fresh fit rows {len(fit)}; passed cells {npass}; unseen fresh rows {len(u)}  ({time.time()-T0:.0f}s)",flush=True)
    del df,fit,mk; gc.collect()
C=pd.DataFrame(CELLS); print(f"\nfresh-close map: {len(C)} cells, passed {int(C.passed.sum())}",flush=True)
for r in C[C.passed].itertuples():
    print(f"   PASSED {r.market_type} p{edges[r.band]:.2f}-{edges[r.band+1]:.2f} {'BACK' if r.side_back else 'LAY'} n_is {r.n_is} e_is {r.e_is:+.4f} n_oos {r.n_oos} e_oos {r.e_oos:+.4f}",flush=True)
S=pd.concat(SC,ignore_index=True).merge(C,on=['market_type','band'],how='inner')
mt_=pd.to_datetime(S.market_time,utc=True); MED=mt_.quantile(0.5); S['h2']=(mt_>=MED).values
print(f"unseen fresh-close runner-rows in map cells: {len(S)} on {S.market_id.nunique()} markets, {mt_.min():%Y-%m-%d}..{mt_.max():%Y-%m-%d}, halves at {MED:%Y-%m-%d}",flush=True)
sb=S.side_back.values; w=S.won.values; cl=S.close_ltp.values
S['pnl']=pnl(sb,w,tick_down(cl),tick_up(cl)); S['pnl0']=pnl(sb,w,cl,cl); S['ctrl']=pnl(rng.random(len(S))<0.5,w,tick_down(cl),tick_up(cl))
def line(g,name):
    h1=g[~g.h2].pnl; h2=g[g.h2].pnl; pm=g.groupby('market_id').pnl.sum()
    return dict(name=name,n=len(g),mk=g.market_id.nunique(),mean=g.pnl.mean(),t=tstat(g.pnl),tm=tstat(pm),h1=h1.mean() if len(h1) else float('nan'),
                h2=h2.mean() if len(h2) else float('nan'),n1=len(h1),n2=len(h2),at0=g.pnl0.mean(),ctrl=g.ctrl.mean(),won=g.won.mean(),imp=g.p.mean(),e_is=g.e_is.mean())
def show(L):
    print(f"{L['name']:<50} n {L['n']:>6} mk {L['mk']:>6} per10 {L['mean']:+.3f} t {L['t']:+.2f} t_mkt {L['tm']:+.2f} h1 {L['h1']:+.3f} ({L['n1']}) h2 {L['h2']:+.3f} ({L['n2']}) | won {L['won']:.4f} v imp {L['imp']:.4f} (edge {L['won']-L['imp']:+.4f} v e_is {L['e_is']:+.4f}) | at print {L['at0']:+.3f} ctrl {L['ctrl']:+.3f}",flush=True)
print("\n== PRIMARY: fresh-close PASSED cells pooled ==",flush=True)
P=line(S[S.passed],"FRESH PASSED ALL") if S.passed.any() else None
show(P) if P else print("no unseen trades in passed cells")
if P:
    for s,g in S[S.passed].groupby('side_back'): show(line(g,f"FRESH PASSED {'BACK' if s else 'LAY'}"))
print("\n== control: every fresh-close cell n_is>=300 ==",flush=True); A=line(S[S.n_is>=300],"FRESH MAP ALL n_is>=300"); show(A)
print("\n== per passed cell ==",flush=True); lines=[]
for (m,b),g in S[S.passed].groupby(['market_type','band']):
    L=line(g,f"P {m} p{edges[b]:.2f}-{edges[b+1]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}"); show(L); lines.append(L)
print("\n== every cell n_is>=300 with unseen n>=300, top 15 by t_mkt ==",flush=True); allc=[]
for (m,b),g in S[S.n_is>=300].groupby(['market_type','band']):
    if len(g)>=300: allc.append(line(g,f"{m} p{edges[b]:.2f}-{edges[b+1]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}{' *P' if g.passed.iloc[0] else ''}"))
allc.sort(key=lambda L:-L['tm'])
for L in allc[:15]: show(L)
print(f"cells with unseen n>=300: {len(allc)}; positive {sum(L['mean']>0 for L in allc)}; edge sign agrees with e_is on {sum((L['won']-L['imp'])*L['e_is']>0 for L in allc)}",flush=True)
print("\n== SURVIVORS (n>=300, n per half>=150, per10>=+0.15, h1>0, h2>0, t_mkt>=3.5) ==",flush=True)
nsurv=0; seen=set()
for L in ([P] if P else [])+lines+allc:
    if L['name'] in seen: continue
    seen.add(L['name'])
    if L['n']>=300 and L['n1']>=150 and L['n2']>=150 and L['mean']>=0.15 and L['h1']>0 and L['h2']>0 and L['tm']>=3.5: show(L); nsurv+=1
print(f"survivors: {nsurv}  ({time.time()-T0:.0f}s)",flush=True)
PY
