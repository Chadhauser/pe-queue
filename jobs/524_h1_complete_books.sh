#!/bin/bash
# 524: H1 on COMPLETE BOOKS only. The 07:04 direct run (213 cells) still had impossible rows: "p0.90-1.00 BACK, win rate 100%, +£10.9/£10"
# = markets where only the eventual winner had a closing price, so it was normalised to p=1 (survivorship through missing loser prices), and
# Asian-handicap cells where several lines win per market. Now: keep a market only if every runner with an official result has a closing
# price, >=2 runners, raw overround 0.95-1.25; multi-line types deferred to H1d. Direct run again with the top cells printed; re-queued.
set -o pipefail
cd /root/pe-sports/team && cp fairprice_v0.py fairprice_v0.py.bak_524
cat > fairprice_v0.py <<'PYFILE'
# H1 FAIR PRICE v0 (pre-registered 5 Nov 2026). THE ONE JOB, step 1: the data tells us the price.
# Data: local bf_hist_other (Betfair BASIC, 1 row per runner per minute, Soccer 2019-2026, 33 market types, 18 countries).
# Only COMPLETE books: every runner with a result also has a closing price, >=2 runners, raw overround 0.95-1.25 (the first official-result run
# showed single-runner 'markets' with p=1 and 100% win rate — survivorship through missing loser prices). Multi-line types (AH, goal line) deferred.
# For every market: the last pre-off LTP per runner (the closing price) and the OFFICIAL result from the file's final market definition
# (bf_hist_result: runner status WINNER/LOSER, written by the loader from job 520). Settlement by price collapse was dropped after
# audit 519 showed the in-play tape often ends early, which kept goal-collapsed markets and dropped the rest (99% "win rates").
# Calibration by (market_type, implied-probability band): IS = older half of the loaded markets by date, OOS = newer half (the loader fills newest-first, so the split moves back as months land; the date range is printed). Fair price per cell =
# 1 / IS win rate (written to fair_price_calib for the bookie bot). Residual test per cell, direction pre-registered as "trade toward
# the IS fair price": back if IS rate > implied (underpriced), lay if IS rate < implied; P&L per £10 at the closing price one tick
# ADVERSE, 2% commission on wins; t over all rows, IS/OOS halves, control = side chosen at random instead of by the fair price.
# One market type at a time end-to-end (memory-safe). Prints RESULT lines for cells with n>=300.
import sys, math, json, datetime, gc, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(7)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def vtick(p):
    inc=np.full(len(p),10.0);
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): return np.round(np.minimum(1000,p+vtick(p)),2)
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='512MB'")
cur.execute("SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"); types=cur.fetchall(); print("types:",types,flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_calib; CREATE TABLE fair_price_calib (market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate_oos NUMERIC, p_mean_oos NUMERIC, fair_factor NUMERIC, built_at TIMESTAMPTZ DEFAULT now())"); con.commit()
T0=datetime.datetime.now(datetime.UTC); out=0; tot_rows=0; tot_dropped=0
MULTI_LINE={'ASIAN_HANDICAP','GOAL_LINE','ASIAN_HANDICAP_HT','HANDICAP','CORNER_HANDICAP','ALT_TOTAL_GOALS','ALT_CORNERS','ALT_BOOKINGS','CORRECT_SCORE2'}  # several winners per market; need line-aware settlement (H1d)
for mt,nmk in types:
    if mt in MULTI_LINE: print(f'  {mt}: multi-line market, deferred to H1d',flush=True); continue
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res FROM bf_hist_result WHERE market_type=%s AND status IN ('WINNER','LOSER')),
         j AS (SELECT pre.market_id, pre.market_time, pre.close_ltp::float8 AS close_ltp, res.won, res.n_res, count(*) OVER (PARTITION BY pre.market_id) AS n_pre,
                      sum(1/pre.close_ltp::float8) OVER (PARTITION BY pre.market_id) AS book FROM pre JOIN res USING (market_id, sel))
    SELECT market_id, market_time, close_ltp, won FROM j WHERE n_pre=n_res AND n_res>=2 AND book BETWEEN 0.95 AND 1.25""",(mt,mt))
    df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','close_ltp','won']); con.commit()
    if len(df)<1000: print(f"  {mt}: {len(df)} rows with official results on complete books — skipped",flush=True); continue
    df['market_id']=df.market_id.astype('category').cat.codes
    nw=df.groupby('market_id',sort=False).won.transform('sum'); clean=(nw==1)   # exactly one official winner per market (no dead heats / voids)
    dropped=int(df.loc[~clean,'market_id'].nunique()); df=df[clean].copy(); tot_dropped+=dropped
    df['won']=df.won.astype(np.int8); df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')
    mtime=pd.to_datetime(df.market_time,utc=True); SPLIT=mtime.quantile(0.5); df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int); df['oos']=mtime>=SPLIT
    print(f"  {mt}: dates {mtime.min():%Y-%m-%d}..{mtime.max():%Y-%m-%d}, IS/OOS split {SPLIT:%Y-%m-%d}",flush=True)
    cal=df.groupby(['band','oos']).agg(n=('won','size'),rate=('won','mean'),p_mean=('p','mean')).reset_index()
    IS=cal[~cal.oos].set_index('band'); OOS=cal[cal.oos].set_index('band')
    rows=[]
    for b,r in IS.iterrows():
        o=OOS.loc[b] if b in OOS.index else None
        rows.append((mt,int(b),edges[b],edges[b+1],int(r.n),float(r.rate),float(r.p_mean),int(o.n) if o is not None else 0,float(o.rate) if o is not None else None,float(o.p_mean) if o is not None else None,float(r.rate/r.p_mean) if r.p_mean>0 else None))
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_calib (market_type,band,band_lo,band_hi,n_is,rate_is,p_mean_is,n_oos,rate_oos,p_mean_oos,fair_factor) VALUES %s",rows); con.commit()
    df=df.merge(IS[['rate','p_mean']].rename(columns={'rate':'fair_rate','p_mean':'p_is'}),left_on='band',right_index=True,how='inner').reset_index(drop=True)
    back=(df.fair_rate>df.p_is).values; cl=df.close_ltp.values; won=df.won.values
    bk=tick_down(cl); ly=tick_up(cl)
    def pnl_of(w): return np.where(back,np.where(w==1,(bk-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly-1)*10,10.0*(1-COMM)))
    df['pnl']=pnl_of(won); df['side']=np.where(back,'BACK','LAY'); oos=df.oos.values
    cells=0
    for b,gdf in df.groupby('band'):
        n=len(gdf)
        if n<300 or gdf.oos.sum()<50 or (~gdf.oos).sum()<50: continue
        idx=gdf.index.values; w=won[idx]; rside=rng.random(len(idx))<0.5   # control: side chosen at random, not by the fair price
        ctrl=np.where(rside,np.where(w==1,(bk[idx]-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly[idx]-1)*10,10.0*(1-COMM)))
        isx=gdf.loc[~gdf.oos,'pnl'].values; oox=gdf.loc[gdf.oos,'pnl'].values
        name=f"H1 {mt} p{edges[b]:.2f}-{edges[b+1]:.2f} {gdf.side.iloc[0]} at close (IS rate {gdf.fair_rate.iloc[0]:.3f} vs implied {gdf.p_is.iloc[0]:.3f})"
        print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_per10=round(float(gdf.pnl.mean()),3),t=round(tstat(gdf.pnl.values),2),is_mean=round(float(isx.mean()),3),is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3),oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),n_oos=int(gdf.oos.sum()),is_rate=round(float(gdf.fair_rate.iloc[0]),4),implied=round(float(gdf.p_is.iloc[0]),4))),flush=True); cells+=1; out+=1
    tot_rows+=len(df)
    print(f"  {mt}: {len(df)} runner-rows, {df.market_id.nunique()} clean markets, dropped {dropped}, cells {cells}, {(datetime.datetime.now(datetime.UTC)-T0).seconds}s",flush=True)
    del df,cal; gc.collect()
print(f"cells reported {out} | runner-rows {tot_rows} | markets dropped (no single official winner) {tot_dropped}")
print("NEXT DOOR (pre-registered): same map at in-play minute bands 0-15/15-30/30-45/HT/45-60/60-75/75+ (H1b), then by country (H1c).")
PYFILE
python3 -m py_compile fairprice_v0.py || { cp fairprice_v0.py.bak_524 fairprice_v0.py; echo "compile failed"; exit 1; }
echo "== direct H1 run"; timeout 3000 python3 -I fairprice_v0.py 2>&1 | grep -v Warning > /root/pe-sports/team/h1_direct.log; grep -c RESULT /root/pe-sports/team/h1_direct.log; grep -v RESULT /root/pe-sports/team/h1_direct.log | grep -v "skipped\|deferred" | tail -22 | cut -c1-200
echo "== top cells by t"; grep RESULT /root/pe-sports/team/h1_direct.log | python3 -c "
import sys,json
rs=[json.loads(l[7:]) for l in sys.stdin]; rs.sort(key=lambda r:-r['t'])
print('n mean t is_t oos_t ctrl is_rate implied name')
for r in rs[:15]: print(r['n'],r['mean_per10'],r['t'],r['is_t'],r['oos_t'],r['control_t'],r.get('is_rate'),r.get('implied'),r['name'][:72])
print('cells passing the gate (t>=3.5, both halves>0, n>=300, mean>=0.15, |ctrl|<=2, sane gap):',sum(1 for r in rs if r['t']>=3.5 and r['is_mean']>0 and r['oos_mean']>0 and r['n']>=300 and r['mean_per10']>=0.15 and abs(r['control_t'])<=2 and abs(r['is_rate']-r['implied'])<=0.15 and r['t']<=15 and r['mean_per10']<=3))"
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H1 fair price v0'): h['status']='proposed'; h.pop('not_before',None); h['note']='complete books (524)'
json.dump(r,open(p,'w'),indent=1); print("H1 re-queued")
PY
