#!/bin/bash
set -o pipefail
# 499_inplay_map_maker (Finder 2026-11-09, about 08:35 UTC run, queue item 489, next door of item 488, maker side; rule pushed in the queue first).
# Same unseen markets (finder_ipunseen_mk_1109) and the same frozen in-play map (finder_ipcal_snap_1109) as job 499_inplay_map_unseen, read, not rebuilt.
# At band end T = market_time + 16/31/46/61/76/91 min: each runner's last print P in [T-5, T) (whole book fresh and complete, raw book 0.90-1.30, one
# official winner); cell = type@band x 18 probability bands; side toward the IS rate. A RESTING order at P: BACK filled only if a print in [T, T+3)
# is strictly ABOVE P, LAY filled only if one is strictly BELOW P (trade-through; the queue at P may not reach us). Fill at P, no tick.
# Back £10 stake, lay £10 liability, 2% on profit, held to the official result. Unfilled = no trade (count, won-rate printed).
# Bar: n>=300 (>=150 a half), mean>=+0.15, both halves (market_time median) positive, t>=3.5 on per-GAME sums. Random-side control, same fill rule.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys, math, time, gc, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time(); CAP=40*60
COMM=0.02; rng=np.random.default_rng(17)
def pnl(side_back, won, px):
    b=np.where(won==1,(px-1)*10*(1-COMM),-10.0)
    l=np.where(won==1,-10.0,10.0/(px-1)*(1-COMM))
    return np.where(side_back,b,l)
def filled(side_back, P, emax, emin):
    return np.where(side_back, emax>P, emin<P)
def tstat(a):
    a=np.asarray(a,float)
    return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
# ---- unit checks with known answers ----
t=pnl(np.array([True,True,False,False]),np.array([1,0,0,1]),np.array([2.0,2.0,2.0,2.0]))
assert np.allclose(t,[9.8,-10.0,9.8,-10.0]), t
f=filled(np.array([True,True,False,False]),np.array([2.0,2.0,2.0,2.0]),np.array([2.02,2.0,2.0,2.0]),np.array([2.0,2.0,1.98,2.0]))
assert f.tolist()==[True,False,True,False], f
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
print("unit checks: maker P&L at 2.0 (back win +9.80, lay lose-runner +9.80, liability -10), trade-through fill (at-price print does not fill) PASS",flush=True)
con=psycopg2.connect(creds.pg_local()); cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cal=pd.read_sql("SELECT market_type mtb, band, band_lo::float8 lo, band_hi::float8 hi, n_is, rate_is::float8 rate_is, p_mean_is::float8 p_is, n_oos, rate_oos::float8 rate_oos, p_mean_oos::float8 p_oos, built_at FROM finder_ipcal_snap_1109",con)
print(f"frozen in-play map: {len(cal)} cells, built .. {cal.built_at.max()}",flush=True)
cal['e_is']=cal.rate_is-cal.p_is; cal['e_oos']=cal.rate_oos-cal.p_oos; cal['side_back']=cal.e_is>0
cal['passed']=(cal.n_is>=300)&(cal.n_oos>=100)&cal.rate_oos.notna()&((cal.e_is>0)==(cal.e_oos>0))&(cal.e_is.abs()>=0.01)&(cal.e_oos.abs()>=0.005)
cal=cal[cal.n_is>=300].reset_index(drop=True)
types=sorted(set(m.split('@m')[0] for m in cal.mtb))
calk=cal.assign(key=cal.mtb+'#'+cal.band.astype(str))[['key','lo','hi','n_is','e_is','side_back','passed']].reset_index(drop=True)
calk['kid']=np.arange(len(calk),dtype=np.int32); KEY=calk.set_index('kid')
print(f"cells n_is>=300: {len(cal)}; passed {int(cal.passed.sum())}",flush=True)
cur.execute("""SELECT u.market_id FROM finder_ipunseen_mk_1109 u
   WHERE u.market_id IS NOT NULL AND EXISTS (SELECT 1 FROM bf_hist_other b WHERE b.sport='Soccer' AND b.market_id=u.market_id AND b.market_type = ANY(%s))""",(types,))
ids=sorted(r[0] for r in cur.fetchall()); con.commit()
ids=list(np.array(ids)[np.random.default_rng(5).permutation(len(ids))])
print(f"unseen Soccer market ids: {len(ids)}  ({time.time()-T0:.0f}s)",flush=True)
Q="""
WITH x AS (SELECT market_id, event_id, market_type, market_time, sel, ts, ltp::float8 ltp, EXTRACT(EPOCH FROM (ts-market_time))/60.0 AS mn
           FROM bf_hist_other WHERE sport='Soccer' AND market_id = ANY(%s) AND market_type = ANY(%s) AND inplay AND ltp>1 AND ltp<1000
             AND ts>market_time AND ts<market_time+interval '94 minutes'),
     c AS (SELECT DISTINCT ON (market_id, sel, mb) market_id, event_id, market_type, market_time, sel, mb, ltp c_ltp, mn c_mn
           FROM (SELECT x.*, width_bucket(mn, ARRAY[1,16,31,46,61,76,91]::float8[]) mb FROM x) y WHERE mb BETWEEN 1 AND 6
           ORDER BY market_id, sel, mb, ts DESC),
     e AS (SELECT market_id, sel, eb, max(ltp) e_max, min(ltp) e_min, min(mn) e_mn0, max(mn) e_mn1
           FROM (SELECT x.*, CASE WHEN mn>=16 AND (mn-16-15*floor((mn-16)/15))<3 THEN floor((mn-16)/15)::int+1 END eb FROM x) y
           WHERE eb BETWEEN 1 AND 6 GROUP BY 1,2,3)
SELECT c.market_id, c.event_id, c.market_type, c.market_time, c.sel, c.mb, c.c_ltp, c.c_mn, e.e_max, e.e_min, e.e_mn0, e.e_mn1
FROM c LEFT JOIN e ON e.market_id=c.market_id AND e.sel=c.sel AND e.eb=c.mb"""
out=[]; st=dict(read=0,cand=0,unf=0,unf_won=0); stopped=False; CH=3000
for i in range(0,len(ids),CH):
    if time.time()-T0>CAP: stopped=True; break
    chunk=[str(x) for x in ids[i:i+CH]]
    cur.execute(Q,(chunk,types)); rows=cur.fetchall()
    cur.execute("SELECT market_id, sel, (status='WINNER')::int, count(*) OVER (PARTITION BY market_id) FROM bf_hist_result WHERE market_id = ANY(%s) AND status IN ('WINNER','LOSER')",(chunk,))
    res=pd.DataFrame(cur.fetchall(),columns=['market_id','sel','won','n_res']); con.commit()
    st['read']+=len(chunk)
    if not rows or res.empty: continue
    d=pd.DataFrame(rows,columns=['market_id','event_id','market_type','market_time','sel','mb','c_ltp','c_mn','e_max','e_min','e_mn0','e_mn1'])
    d['sel']=d.sel.astype(res.sel.dtype)
    nw=res.groupby('market_id').won.transform('sum'); res=res[nw==1]
    d=d.merge(res,on=['market_id','sel'],how='inner')
    d['T']=d.mb*15+1.0
    assert (d.c_mn<d['T']).all() and (d.c_mn>=d['T']-15).all()
    e=d.e_mn0.notna(); assert ((d.e_mn0[e]>=d['T'][e])&(d.e_mn1[e]<d['T'][e]+3)).all()
    d['fresh']=d.c_mn>=d['T']-5; d['inv']=1/d.c_ltp
    g=d.groupby(['market_id','mb'])
    d['n_pre']=g.sel.transform('size'); d['n_fr']=g.fresh.transform('sum'); d['book']=g.inv.transform('sum')
    d=d[(d.n_pre==d.n_res)&(d.n_res>=2)&d.book.between(0.90,1.30)&(d.n_fr==d.n_res)].copy()
    d['p']=d.inv/d.book
    d['pb']=pd.cut(d.p,edges,right=False,labels=False).astype(int)
    d['key']=d.market_type+'@m'+d.mb.astype(str)+'#'+d.pb.astype(str)
    d=d.merge(calk,on='key',how='inner').drop(columns=['key'])
    d['market_id']=(pd.factorize(d.market_id)[0]+i*10).astype(np.int64); d['event_id']=pd.to_numeric(d.event_id).astype(np.int64)
    sb=d.side_back.values; P=d.c_ltp.values; emax=d.e_max.fillna(-1).values; emin=d.e_min.fillna(1e9).values
    d['fill']=filled(sb,P,emax,emin)
    rs=rng.random(len(d))<0.5; d['rs']=rs; d['cfill']=filled(rs,P,emax,emin)
    st['cand']+=len(d); st['unf']+=int((~d.fill).sum()); st['unf_won']+=int(d.won[~d.fill].sum())
    out.append(d[['market_id','event_id','market_time','kid','mb','passed','side_back','won','p','c_ltp','fill','rs','cfill']].copy())
    del d,rows,res; gc.collect()
    if (i//CH)%10==0: print(f"  chunk {i//CH+1}/{(len(ids)+CH-1)//CH}: candidates {st['cand']}  ({time.time()-T0:.0f}s)",flush=True)
print(f"read {st['read']} of {len(ids)} ids ({100*st['read']/max(1,len(ids)):.1f}%){' -- STOPPED BY THE 40-MIN CAP, a random sample' if stopped else ''}",flush=True)
A=pd.concat(out,ignore_index=True); del out; gc.collect()
print(f"candidate resting orders {len(A)}; filled {int(A.fill.sum())} ({A.fill.mean():.3f}); unfilled {st['unf']}, of which won {st['unf_won']} ({st['unf_won']/max(1,st['unf']):.3f})",flush=True)
for s,g in A[A.passed].groupby('side_back'):
    print(f"   PASSED {'BACK' if s else 'LAY'}: candidates {len(g)}, fill rate {g.fill.mean():.3f}; won-rate filled {g.won[g.fill].mean():.4f} v unfilled {g.won[~g.fill].mean():.4f}; implied filled {g.p[g.fill].mean():.4f}",flush=True)
A['ctrl_pnl']=pnl(A.rs.values,A.won.values,A.c_ltp.values)
C=A[A.cfill].copy()
F=A[A.fill].copy(); F['pnl']=pnl(F.side_back.values,F.won.values,F.c_ltp.values)
mt=pd.to_datetime(F.market_time,utc=True); F['h2']=(mt>=mt.quantile(0.5)).values
print(f"filled trades {len(F)} on {F.market_id.nunique()} markets, {F.event_id.nunique()} games; {mt.min():%Y-%m-%d}..{mt.max():%Y-%m-%d}; halves at {mt.quantile(0.5):%Y-%m-%d %H:%M}",flush=True)
F['lo']=KEY.lo.reindex(F.kid).values; F['hi']=KEY.hi.reindex(F.kid).values
def line(g,name):
    n=len(g)
    if n==0: return None
    h1=g[~g.h2].pnl; h2=g[g.h2].pnl
    return dict(name=name,n=n,mk=g.market_id.nunique(),gm=g.event_id.nunique(),mean=g.pnl.mean(),t=tstat(g.pnl),tg=tstat(g.groupby('event_id').pnl.sum()),
                h1=h1.mean() if len(h1) else float('nan'),h2=h2.mean() if len(h2) else float('nan'),n1=len(h1),n2=len(h2),won=g.won.mean(),imp=g.p.mean())
def show(L):
    print(f"{L['name']:<48} n {L['n']:>7} mk {L['mk']:>6} gm {L['gm']:>5} per10 {L['mean']:+.3f} t {L['t']:+.2f} t_game {L['tg']:+.2f} h1 {L['h1']:+.3f} ({L['n1']}) h2 {L['h2']:+.3f} ({L['n2']}) | won {L['won']:.4f} v imp {L['imp']:.4f}",flush=True)
def nm(g): k=KEY.key.loc[g.kid.iloc[0]]; return f"{k.split('#')[0]} p{g.lo.iloc[0]:.2f}-{g.hi.iloc[0]:.2f} {'BACK' if g.side_back.iloc[0] else 'LAY'}{' *P' if g.passed.iloc[0] else ''}"
print("\n== PRIMARY: MAKER, PASSED cells pooled (trade-through fills at P) ==",flush=True)
Pl=line(F[F.passed],"MAKER PASSED ALL"); show(Pl)
for s,g in F[F.passed].groupby('side_back'): show(line(g,f"MAKER PASSED {'BACK' if s else 'LAY'}"))
for b,g in F[F.passed].groupby('mb'): show(line(g,f"MAKER PASSED band {b}"))
show(line(F,"MAKER ALL cells n_is>=300"))
cp=C[C.passed]; print(f"random-side control on the same fill rule, passed cells: n {len(cp)} per10 {cp.ctrl_pnl.mean():+.3f} t {tstat(cp.ctrl_pnl):+.2f}; all cells n {len(C)} per10 {C.ctrl_pnl.mean():+.3f}",flush=True)
print("\n== MAKER every cell n_is>=300 with n>=300, top 15 by t_game ==",flush=True)
al=[line(g,nm(g)) for k,g in F.groupby('kid') if len(g)>=300]; al.sort(key=lambda L:-L['tg'])
for L in al[:15]: show(L)
print(f"cells with n>=300: {len(al)}; positive {sum(L['mean']>0 for L in al)}; passed among them {sum('*P' in L['name'] for L in al)}",flush=True)
print("\n== SURVIVORS (n>=300, n per half>=150, per10>=+0.15, h1>0, h2>0, t_game>=3.5) ==",flush=True)
seen=set(); ns=0
for L in [Pl]+al:
    if L is None or L['name'] in seen: continue
    seen.add(L['name'])
    if L['n']>=300 and L['n1']>=150 and L['n2']>=150 and L['mean']>=0.15 and L['h1']>0 and L['h2']>0 and L['tg']>=3.5: show(L); ns+=1
print(f"survivors: {ns}  ({time.time()-T0:.0f}s)",flush=True)
PY
