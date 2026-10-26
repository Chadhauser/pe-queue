#!/bin/bash
# 242 (cross-exchange, run 4: Matchbook names use 'vs' and the market name is 'Match Odds'; normalise both; guard empty frames): CROSS-EXCHANGE — first use of the Smarkets/Matchbook tape (xx_tape, recording since 14 Oct; never analysed until Peter asked).
# Three questions, all on matched events (same event name on Betfair's liq_sample/ip_tape and the other exchange):
#   1. Health: rows per exchange per day, live markets, last seen.
#   2. Lag: after a Betfair in-play move of >= 10% in a selection's best back, how long until the other exchange's best back has moved
#      >= 5% the same way (median seconds), and what fraction never follow within 3 minutes.  (originator-follower)
#   3. Arb / best price: at each Betfair sample, is there a selection where the other exchange's BACK price exceeds Betfair's LAY price
#      (a riskless back-there / lay-here) after 2% Betfair + 2% Smarkets / 4% Matchbook commission; how often, size available, which
#      markets. Plus: how often the other book's lay price beats Betfair's for the late lay-Over state.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pandas only"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',230); con=psycopg2.connect(DB,sslmode='require')
print("=== 1. HEALTH ===")
print(pd.read_sql("SELECT exchange, date_trunc('day',ts)::date d, count(*) rows, count(DISTINCT market_id) markets FROM xx_tape WHERE ts>now()-interval '5 days' GROUP BY 1,2 ORDER BY 1,2",con).to_string(index=False))
print(pd.read_sql("SELECT * FROM xx_heartbeat",con).to_string(index=False))
X=pd.read_sql("SELECT ts, exchange, sport, event_name, market_name, inplay, sel_name, back_px::float bp, back_sz::float bsz, lay_px::float lp, lay_sz::float lsz FROM xx_tape WHERE ts>now()-interval '5 days' AND back_px IS NOT NULL AND inplay",con)
print("\nother-exchange rows:",len(X),"| events:",X.event_name.nunique(),"| by exchange x sport:\n",X.groupby(['exchange','sport']).size().to_string())
B=pd.read_sql("SELECT ts, event_name, sel, back_px::float bp, back_sz::float bsz, lay_px::float lp, lay_sz::float lsz, minute FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '5 days' AND back_px IS NOT NULL",con)
# name normalisation for matching
import re, unicodedata
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().replace(' vs ',' v '); s=re.sub(r"\b(fc|cf|afc|sc|ac|the|draw|1)\b"," ",s); return ' '.join(re.sub(r"[^a-z0-9 ]"," ",s).split())
X['ev']=X.event_name.map(norm); B['ev']=B.event_name.map(norm)
common=set(X.ev)&set(B.ev); print("\nevents on both Betfair and another exchange (in-play Match Odds):",len(common))
X=X[X.ev.isin(common)]; B=B[B.ev.isin(common)]
if X.empty: print('no overlap after name normalisation — sample Betfair:',sorted(set(B.ev))[:5],'sample other:',sorted(set(pd.read_sql("SELECT DISTINCT event_name FROM xx_tape WHERE ts>now()-interval '1 day' LIMIT 5",con).event_name.map(norm))))
else: X=X[X.market_name.fillna('').str.lower().str.contains('match odds|winner')]
selmap={'home':'HOME','away':'AWAY','draw':'DRAW'}
def side(row):
    s=row.sel_name.lower()
    if 'draw' in s: return 'DRAW'
    h,a=row.ev.split(' v ') if ' v ' in row.ev else (row.ev,'')
    return 'HOME' if norm(row.sel_name) and norm(row.sel_name) in h else ('AWAY' if norm(row.sel_name) in a else None)
X['side']=X.apply(side,axis=1) if len(X) else pd.Series(dtype=object); X=X[X.side.notna()] if len(X) else X
print("\n=== 2. LAG after a Betfair move >= 10% in best back ===")
lags=[]; never=0; n=0
for (ev,s),g in B.groupby(['ev','sel']):
    g=g.sort_values('ts'); g['prev']=g.bp.shift(); mv=g[(g.bp>=g.prev*1.10)|(g.bp<=g.prev*0.90)]
    for r in mv.itertuples():
        o=X[(X.ev==ev)&(X.side==s)&(X.ts>=r.ts-pd.Timedelta(seconds=60))&(X.ts<=r.ts+pd.Timedelta(minutes=3))].sort_values('ts')
        pre=o[o.ts<r.ts]; post=o[o.ts>=r.ts]
        if pre.empty or post.empty: continue
        n+=1; p0=pre.iloc[-1].bp; up=r.bp>r.prev
        hit=post[(post.bp>=p0*1.05)] if up else post[(post.bp<=p0*0.95)]
        if hit.empty: never+=1
        else: lags.append((hit.iloc[0].ts-r.ts).total_seconds())
print(f"Betfair moves with the other exchange observed: {n} | followed within 3 min: {len(lags)} | never followed: {never}")
if lags: print("lag seconds: median",np.median(lags),"| p25",np.percentile(lags,25),"| p75",np.percentile(lags,75),"| <=30 s:",f"{np.mean(np.array(lags)<=30):.0%}")
print("(note: both tapes sample ~1/min, so a lag under 60 s cannot be resolved here — the stream tape fixes this from today)")
print("\n=== 3. ARB / BEST PRICE at Betfair sample times ===")
rows=[]
for (ev,s),g in B.groupby(['ev','sel']):
    o=X[(X.ev==ev)&(X.side==s)].sort_values('ts')
    if o.empty: continue
    m=pd.merge_asof(g.sort_values('ts'),o[['ts','exchange','bp','bsz','lp','lsz']].rename(columns={'bp':'obp','bsz':'obsz','lp':'olp','lsz':'olsz'}),on='ts',direction='nearest',tolerance=pd.Timedelta(seconds=45))
    m=m.dropna(subset=['obp']); m['ev']=ev; m['sel']=s; rows.append(m)
M=pd.concat(rows) if rows else pd.DataFrame()
if len(M):
    comm={'smarkets':0.02,'matchbook':0.04}
    M['c']=M.exchange.map(lambda e: comm.get(str(e).lower(),0.02))
    # back on other at obp, lay on Betfair at lp: profit per £10 back if the hedge is riskless: 10*(obp*(1-c) - lp*(1-0.02))/... simplified edge = obp*(1-c)/lp - 1 (both sides net)
    M['edge']=M.obp*(1-M.c)/M.lp-1
    M['edge2']=M.bp*(1-0.02)/M.olp-1      # back Betfair, lay other
    arb=M[(M.edge>0)|(M.edge2>0)]
    print("matched samples:",len(M),"| samples with a riskless cross-book arb after commission:",len(arb),f"({len(arb)/len(M):.1%})")
    if len(arb): print(" mean edge",round(arb[['edge','edge2']].max(axis=1).mean()*100,2),"% | median size available £",round(arb[['obsz','olsz','bsz','lsz']].min(axis=1).median(),0)); print(arb.groupby('exchange').size().to_string())
    M['better_lay_other']=M.olp<M.lp
    print("other exchange offers a LOWER lay price than Betfair in",f"{M.better_lay_other.mean():.0%}","of samples; mean improvement when it does:",round((1-M[M.better_lay_other].olp/M[M.better_lay_other].lp).mean()*100,2),"%")
    late=M[(M.minute>=70)&(M.sel=='DRAW')]; print("late (70'+) draw samples with another book:",len(late))
else: print("no overlapping samples — check the name matching / recorder")
PY
