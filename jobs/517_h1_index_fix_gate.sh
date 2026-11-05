#!/bin/bash
# 517: (1) H1 crashed at the cell loop with IndexError: pandas merge(right_index=True) keeps the LEFT index, so row labels from before the
# clean-collapse filter outran the arrays built after it — reset_index after the merge (re-tested offline, 24 cells on synthetic data).
# (2) Gate: the one remaining FAIL is "process keepalive_preoff_scalp.sh down" — that bot was STOPPED on purpose (358); the suite now
# skips process checks for bots with a STOPPED marker and adds the team daemon and the archive cron to the watched processes.
# (3) Daemon restarted (idle) so the corrected five-line for the fade shows. H1 re-queued.
set -o pipefail
cd /root/pe-sports/team && cp fairprice_v0.py fairprice_v0.py.bak_517
cat > fairprice_v0.py <<'PYFILE'
# H1 FAIR PRICE v0 (pre-registered 5 Nov 2026). THE ONE JOB, step 1: the data tells us the price.
# Data: local bf_hist_other (Betfair BASIC, 1 row per runner per minute, Soccer 2019-2026, 33 market types, 18 countries).
# For every market: the last pre-off LTP per runner (the closing price) and the last in-play LTP (settlement: the winner collapses
# to <=1.10 while every other runner is >=3.0; markets without a clean collapse are dropped and counted).
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
for mt,nmk in types:
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         fin AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, ltp AS last_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND inplay AND ltp>1 ORDER BY market_id, sel, ts DESC)
    SELECT pre.market_id, pre.market_time, pre.close_ltp::float8, fin.last_ltp::float8 FROM pre JOIN fin USING (market_id, sel)""",(mt,mt))
    df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','close_ltp','last_ltp']); con.commit()
    if len(df)<1000: print(f"  {mt}: {len(df)} rows — skipped",flush=True); continue
    df['market_id']=df.market_id.astype('category').cat.codes
    g=df.groupby('market_id',sort=False); df['iswin']=(df.last_ltp<=1.10).astype(np.int8); df['mid']=((df.last_ltp>1.10)&(df.last_ltp<3.0)).astype(np.int8)
    n_le=g.iswin.transform('sum'); n_mid=g.mid.transform('sum'); clean=(n_le==1)&(n_mid==0)
    dropped=int(df.loc[~clean,'market_id'].nunique()); df=df[clean].copy(); tot_dropped+=dropped
    df['won']=df.iswin.astype(np.int8); df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')
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
        print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_per10=round(float(gdf.pnl.mean()),3),t=round(tstat(gdf.pnl.values),2),is_mean=round(float(isx.mean()),3),is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3),oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),n_oos=int(gdf.oos.sum()))),flush=True); cells+=1; out+=1
    tot_rows+=len(df)
    print(f"  {mt}: {len(df)} runner-rows, {df.market_id.nunique()} clean markets, dropped {dropped}, cells {cells}, {(datetime.datetime.now(datetime.UTC)-T0).seconds}s",flush=True)
    del df,g,cal; gc.collect()
print(f"cells reported {out} | runner-rows {tot_rows} | markets dropped (no clean collapse) {tot_dropped}")
print("NEXT DOOR (pre-registered): same map at in-play minute bands 0-15/15-30/30-45/HT/45-60/60-75/75+ (H1b), then by country (H1c).")
PYFILE
python3 -m py_compile fairprice_v0.py || { cp fairprice_v0.py.bak_517 fairprice_v0.py; echo "compile failed, restored"; exit 1; }
python3 - <<'PY'
p='/root/pe-data/integrity_suite.py'; s=open(p).read()
old="for proc in ('pe-hist/loader.py','liq_recorder.py','stream_client.py','ip_recorder.py','keepalive_preoff_scalp.sh'):\n    r=subprocess.run(['pgrep','-f',proc],capture_output=True); chk(f\"process {proc}\", r.returncode==0, 'up' if r.returncode==0 else 'down')"
new="""import os
for proc,stopmark in (('pe-hist/loader.py',None),('liq_recorder.py',None),('stream_client.py',None),('ip_recorder.py',None),('keepalive_preoff_scalp.sh','/root/pe-race/STOPPED'),('sports_team.py',None),('xx_recorder',None)):
    if stopmark and os.path.exists(stopmark): chk(f"process {proc}", True, 'stopped (on purpose, 358)'); continue
    r=subprocess.run(['pgrep','-f',proc],capture_output=True); chk(f"process {proc}", r.returncode==0, 'up' if r.returncode==0 else 'down')"""
if old in s: s=s.replace(old,new); open(p,'w').write(s); print("suite patched")
else: print("SUITE ANCHOR NOT FOUND — unchanged")
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H1 fair price v0') and h['status']!='running': h['status']='proposed'; h.pop('not_before',None); h['note']='re-queued 517 (index fix)'
json.dump(r,open(p,'w'),indent=1); print([(h['id'][:24],h['status']) for h in r['hypotheses']])
PY
python3 -m py_compile /root/pe-data/integrity_suite.py || exit 1
ls /root/pe-race/STOPPED /root/pe-xg/STOPPED 2>&1 | head -2
if ! grep -q '"status": "running"' /root/pe-sports/team/hypotheses.json; then pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh & disown; sleep 2; echo "daemon restarted $(pgrep -f sports_team.py | head -1)"; else echo "a build is running; daemon not restarted (keepalive picks up the file later)"; fi
python3 /root/pe-data/integrity_suite.py 2>&1 | grep -E "INTEGRITY|FAIL|process" | head -12
