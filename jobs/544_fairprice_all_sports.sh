#!/bin/bash
# 544 (Mon 9 Nov 2026). THE FAIR-PRICE ENGINE — all sports, all markets the tape covers (Peter, 08:11).
# fairprice_v0.py was Soccer-only and single-winner-only. Now: every sport in bf_hist_other (Soccer, Horse Racing, Greyhounds, Tennis,
# Cricket, Golf, Other Sports — whatever the BASIC files hold) x every market type with official results, including books with several
# winners (racing PLACE, each-way style markets): the implied probability is normalised to the number of winners, so a PLACE runner's
# probability is read against the 3 (or k) places paid. Same rules as before: complete books only (every runner with a result has a closing
# price), overround per winner 0.95-1.25, IS = older half by date, OOS = newer half, one tick adverse, 2% commission, random-side control,
# cells n>=300 with >=50 each half. Calibration table gains a `sport` column; the Verifier's passed-cells table and the bot carry it, and the
# bot's universe is every Betfair event type a passed cell names. One honest exclusion, stated not hidden: Asian-handicap / goal-line /
# handicap markets cannot be settled from what the loader stored (runner name only, the handicap value `hc` is not captured) — they stay
# out until the loader captures `hc` (that is a loader change plus a re-read, logged as the next door, not done today).
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team && cp fairprice_v0.py fairprice_v0.py.bak_544
cat > fairprice_v0.py <<'PYFILE'
# H1 FAIR PRICE v1 (544, 9 Nov 2026): the data tells us the price — every sport, every single-line market the tape covers.
# Data: local bf_hist_other (Betfair BASIC, 1 row per runner per minute) + bf_hist_result (official runner status from the final market
# definition). Per (sport, market_type): the last pre-off LTP per runner (closing price), official WINNER/LOSER, complete books only, k =
# winners per market (1 for match odds, 3 for most PLACE), p = (1/close) / sum(1/close) * k, overround per winner 0.95-1.25.
# Calibration by (sport, market_type, probability band): IS = older half by date, OOS = newer half; fair factor = IS rate / IS implied.
# Residual test per cell: trade toward the IS fair price at the closing price one tick ADVERSE, 2% commission on wins; control = side at
# random. RESULT lines for cells n>=300 and >=50 each half. One (sport, type) at a time, memory-safe.
import sys, math, json, datetime, gc, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(7)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def vtick(p):
    inc=np.full(len(p),10.0)
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): return np.round(np.minimum(1000,p+vtick(p)),2)
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
MULTI_LINE={'ASIAN_HANDICAP','GOAL_LINE','ASIAN_HANDICAP_HT','HANDICAP','CORNER_HANDICAP','ALT_TOTAL_GOALS','ALT_CORNERS','ALT_BOOKINGS','CORRECT_SCORE2','SET_HANDICAP','GAME_HANDICAP','RUN_LINE','TOTAL_POINTS','POINT_SPREAD'}
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='512MB'")
cur.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 HAVING count(DISTINCT market_id)>=200 ORDER BY 1, 3 DESC"); types=cur.fetchall()
print("sport x type combinations:",len(types),"| sports:",sorted({s for s,_,_ in types}),flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_calib; CREATE TABLE fair_price_calib (sport TEXT, market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate_oos NUMERIC, p_mean_oos NUMERIC, fair_factor NUMERIC, winners_mean NUMERIC, built_at TIMESTAMPTZ DEFAULT now())"); con.commit()
T0=datetime.datetime.now(datetime.UTC); out=0; tot_rows=0; skipped_ml=[]
for sport,mt,nmk in types:
    if mt in MULTI_LINE: skipped_ml.append(f"{sport}/{mt}"); continue
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport=%s AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res,
                        sum((status='WINNER')::int) OVER (PARTITION BY market_id) AS k FROM bf_hist_result WHERE sport=%s AND market_type=%s AND status IN ('WINNER','LOSER')),
         j AS (SELECT pre.market_id, pre.market_time, pre.close_ltp::float8 AS close_ltp, res.won, res.n_res, res.k, count(*) OVER (PARTITION BY pre.market_id) AS n_pre,
                      sum(1/pre.close_ltp::float8) OVER (PARTITION BY pre.market_id) AS book FROM pre JOIN res USING (market_id, sel))
    SELECT market_id, market_time, close_ltp, won, k FROM j WHERE n_pre=n_res AND n_res>=2 AND k>=1 AND k<n_res AND book/k BETWEEN 0.95 AND 1.25""",(sport,mt,sport,mt))
    df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','close_ltp','won','k']); con.commit()
    if len(df)<1000: print(f"  {sport}/{mt}: {len(df)} runner-rows on complete books — skipped",flush=True); continue
    df['market_id']=df.market_id.astype('category').cat.codes
    df['won']=df.won.astype(np.int8); df['k']=df.k.astype(np.int16); df['p_raw']=1/df.close_ltp
    df['p']=np.minimum(0.9999,df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')*df.k)
    mtime=pd.to_datetime(df.market_time,utc=True); SPLIT=mtime.quantile(0.5); df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int); df['oos']=(mtime>=SPLIT).values
    print(f"  {sport}/{mt}: dates {mtime.min():%Y-%m-%d}..{mtime.max():%Y-%m-%d}, split {SPLIT:%Y-%m-%d}, winners/market mean {df.groupby('market_id').k.first().mean():.2f}",flush=True)
    cal=df.groupby(['band','oos']).agg(n=('won','size'),rate=('won','mean'),p_mean=('p','mean')).reset_index()
    IS=cal[~cal.oos].set_index('band'); OOS=cal[cal.oos].set_index('band'); rows=[]
    for b,r in IS.iterrows():
        o=OOS.loc[b] if b in OOS.index else None
        rows.append((sport,mt,int(b),edges[b],edges[b+1],int(r.n),float(r.rate),float(r.p_mean),int(o.n) if o is not None else 0,float(o.rate) if o is not None else None,float(o.p_mean) if o is not None else None,float(r.rate/r.p_mean) if r.p_mean>0 else None,float(df.k.mean())))
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_calib (sport,market_type,band,band_lo,band_hi,n_is,rate_is,p_mean_is,n_oos,rate_oos,p_mean_oos,fair_factor,winners_mean) VALUES %s",rows); con.commit()
    df=df.merge(IS[['rate','p_mean']].rename(columns={'rate':'fair_rate','p_mean':'p_is'}),left_on='band',right_index=True,how='inner').reset_index(drop=True)
    back=(df.fair_rate>df.p_is).values; cl=df.close_ltp.values; won=df.won.values; bk=tick_down(cl); ly=tick_up(cl)
    df['pnl']=np.where(back,np.where(won==1,(bk-1)*10*(1-COMM),-10.0),np.where(won==1,-(ly-1)*10,10.0*(1-COMM))); df['side']=np.where(back,'BACK','LAY')
    cells=0
    for b,gdf in df.groupby('band'):
        n=len(gdf)
        if n<300 or gdf.oos.sum()<50 or (~gdf.oos).sum()<50: continue
        idx=gdf.index.values; w=won[idx]; rside=rng.random(len(idx))<0.5
        ctrl=np.where(rside,np.where(w==1,(bk[idx]-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly[idx]-1)*10,10.0*(1-COMM)))
        isx=gdf.loc[~gdf.oos,'pnl'].values; oox=gdf.loc[gdf.oos,'pnl'].values
        name=f"H1 {sport} {mt} p{edges[b]:.2f}-{edges[b+1]:.2f} {gdf.side.iloc[0]} at close (IS rate {gdf.fair_rate.iloc[0]:.3f} vs implied {gdf.p_is.iloc[0]:.3f})"
        print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_per10=round(float(gdf.pnl.mean()),3),t=round(tstat(gdf.pnl.values),2),is_mean=round(float(isx.mean()),3),is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3),oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),n_oos=int(gdf.oos.sum()),is_rate=round(float(gdf.fair_rate.iloc[0]),4),implied=round(float(gdf.p_is.iloc[0]),4))),flush=True); cells+=1; out+=1
    tot_rows+=len(df); print(f"  {sport}/{mt}: {len(df)} runner-rows, {df.market_id.nunique()} books, cells {cells}, {(datetime.datetime.now(datetime.UTC)-T0).seconds}s",flush=True)
    del df,cal; gc.collect()
print(f"cells reported {out} | runner-rows {tot_rows} | multi-line types left out (loader has no handicap value): {skipped_ml}")
print("NEXT DOOR (pre-registered): loader captures the runner handicap `hc` so AH/goal-line/handicap books settle (H1d); in-play bands for every sport (H1b extended).")
PYFILE
python3 -m py_compile fairprice_v0.py && echo "fairprice v1 compiles"
echo "== Verifier passed-cells: carry sport =="
python3 - <<'PY'
p='/root/pe-sports/team/verifier_cells.py'; s=open(p).read()
s=s.replace('''c.execute("""CREATE TABLE IF NOT EXISTS fair_price_passed (market_type TEXT, band_lo NUMERIC, band_hi NUMERIC, side TEXT, fair_factor NUMERIC,
  n_is INT, n_oos INT, edge_is NUMERIC, edge_oos NUMERIC, source TEXT, passed_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (market_type, band_lo, source))""")''',
'''c.execute("SELECT 1 FROM information_schema.columns WHERE table_name='fair_price_passed' AND column_name='sport'")
if not c.fetchone(): c.execute("DROP TABLE IF EXISTS fair_price_passed")   # 544: keyed by sport now (one-time rebuild)
c.execute("""CREATE TABLE IF NOT EXISTS fair_price_passed (sport TEXT, market_type TEXT, band_lo NUMERIC, band_hi NUMERIC, side TEXT, fair_factor NUMERIC,
  n_is INT, n_oos INT, edge_is NUMERIC, edge_oos NUMERIC, source TEXT, passed_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (sport, market_type, band_lo, source))""")''')
s=s.replace('''c.execute("""SELECT market_type, band_lo, band_hi, fair_factor, n_is, n_oos, rate_is-p_mean_is AS e_is, rate_oos-p_mean_oos AS e_oos FROM fair_price_calib''',
'''c.execute("""SELECT coalesce(sport,'Soccer'), market_type, band_lo, band_hi, fair_factor, n_is, n_oos, rate_is-p_mean_is AS e_is, rate_oos-p_mean_oos AS e_oos FROM fair_price_calib''')
s=s.replace("for mt,lo,hi,f,nis,noos,eis,eoos in rows:","for sp,mt,lo,hi,f,nis,noos,eis,eoos in rows:")
s=s.replace('''c.execute("INSERT INTO fair_price_passed (market_type,band_lo,band_hi,side,fair_factor,n_is,n_oos,edge_is,edge_oos,source) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,'H1')",(mt,lo,hi,side,f,nis,noos,round(float(eis),4),round(float(eoos),4))); n+=1''',
'''c.execute("INSERT INTO fair_price_passed (sport,market_type,band_lo,band_hi,side,fair_factor,n_is,n_oos,edge_is,edge_oos,source) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'H1')",(sp,mt,lo,hi,side,f,nis,noos,round(float(eis),4),round(float(eoos),4))); n+=1''')
s=s.replace('c.execute("SELECT market_type, band_lo, band_hi, side, n_is, edge_is, edge_oos FROM fair_price_passed ORDER BY 1,2")','c.execute("SELECT sport, market_type, band_lo, band_hi, side, n_is, edge_is, edge_oos FROM fair_price_passed ORDER BY 1,2,3")')
assert s.count('sport')>=6, "verifier patch incomplete"; open(p,'w').write(s); print("verifier_cells carries sport")
PY
python3 -m py_compile verifier_cells.py && echo "verifier compiles"
echo "== bot: universe = every event type a passed cell names; k winners from the catalogue =="
cd /root/pe-sports/bookie && cp bookie_v2.py bookie_v2.py.bak_544 && python3 - <<'PY'
p='/root/pe-sports/bookie/bookie_v2.py'; s=open(p).read()
s=s.replace("def cells():\n    lc.execute(\"SELECT market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed\"); C={}\n    for mt,lo,hi,side,f in lc.fetchall(): C.setdefault(mt,[]).append((float(lo),float(hi),side,float(f)))\n    return C",
'''EVT={'Soccer':'1','Tennis':'2','Golf':'3','Cricket':'4','Rugby Union':'5','Boxing':'6','Horse Racing':'7','Motor Sport':'8','Cycling':'11','Rugby League':'1477','Darts':'3503','Greyhound Racing':'4339','American Football':'6423','Snooker':'6422','Baseball':'7511','Basketball':'7522','Ice Hockey':'7524','MMA':'26420','Esports':'27454'}
def cells():
    lc.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); C={}
    for sp,mt,lo,hi,side,f in lc.fetchall():
        et=EVT.get(sp)
        if et is None: log(f"no Betfair event type for sport {sp!r} — cells skipped"); continue
        C.setdefault((et,mt),[]).append((float(lo),float(hi),side,float(f)))
    return C''')
s=s.replace('''        if now-cat_t>300:   # universe: soccer markets of passed types kicking off in the next HORIZON_MIN
            t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":sorted(C),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(minutes=HORIZON_MIN)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
            cat={m['marketId']:m for m in api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200})}
            cat_t=now''',
'''        if now-cat_t>300:   # universe: every (event type, market type) a passed cell names, starting in the next HORIZON_MIN
            t0=datetime.datetime.utcnow(); cat={}
            for et in sorted({e for e,_ in C}):
                f={"eventTypeIds":[et],"marketTypeCodes":sorted({m for e,m in C if e==et}),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(minutes=HORIZON_MIN)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
                for m in api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","EVENT_TYPE","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}): m['_et']=et; cat[m['marketId']]=m
            cat_t=now''')
s=s.replace("            m=cat.get(mid); mt=(m.get('description') or {}).get('marketType') if m else None\n            if not m or mt not in C or",
            "            m=cat.get(mid); mt=(m.get('description') or {}).get('marketType') if m else None; k=int((m.get('description') or {}).get('numberOfWinners') or 1) if m else 1\n            if not m or (m.get('_et'),mt) not in C or")
s=s.replace("                p=(1/((bb+bl)/2))/tot; side,f=cell_for(C,mt,p)","                p=min(0.9999,(1/((bb+bl)/2))/tot*k); side,f=cell_for(C,(m['_et'],mt),p)")
assert s.count("m['_et']")>=2 and 'numberOfWinners' in s, "bot patch incomplete"; open(p,'w').write(s); print("bookie_v2 universe is every passed sport; k winners handled")
PY
python3 -m py_compile bookie_v2.py && echo "bookie_v2 compiles" || { cp bookie_v2.py.bak_544 bookie_v2.py; echo RESTORED; exit 1; }
pkill -f bookie_v2.py   # keepalive relaunches with the patch
echo "== run the engine now (all sports) — H1 marked proposed so the daemon also re-runs it on its 12-hour cycle =="
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H1 fair price v0'): h['status']='proposed'; h['id']='H1 fair price v1 (all sports, all single-line markets, k winners)'; h.pop('not_before',None)
json.dump(r,open(p,'w'),indent=1); print([h['id'][:40]+':'+h['status'] for h in r['hypotheses']])
PY
if pgrep -f fairprice_v0.py >/dev/null; then echo "H1 already running under the daemon — not started twice; its RESULT lines land on the scoreboard"; else cd /root/pe-sports/team && timeout 14000 python3 fairprice_v0.py 2>&1 | tee /root/pe-sports/team/fairprice_v1_first_run.log | grep -v "^RESULT" | tail -60
fi
echo "RESULT lines: $(grep -c '^RESULT' /root/pe-sports/team/fairprice_v1_first_run.log)"; python3 /root/pe-sports/team/verifier_cells.py
echo "544 done"
