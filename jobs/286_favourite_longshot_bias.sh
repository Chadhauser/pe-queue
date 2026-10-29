#!/bin/bash
# 286: THE BOOKIE'S BREAD — favourite-longshot bias on OUR tapes. Lay every runner at the LAY touch by price band, hold to settle,
# 2% commission, football Match Odds (in-play tape, settled by ESPN final score, matched games) — pre-match sample at the first
# in-play tick and in-play samples at 15'/30'/60'. If the public overbets longshots at the exchange touch, laying 6+ / 10+ shows
# it. Reports per band: n, lay P&L per £10 liability-equivalent, win rate, both halves by date. Racing: same from racing_bsp
# (lay at BSP by band was already DEAD, 222) so racing uses the pre-off stream touch instead when 2 weeks of stream exist.
set -e
python3 - <<'PY'
import sys,psycopg2,pandas as pd,numpy as np; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
fin=pd.read_sql("""SELECT DISTINCT ON (market_id) market_id, hs, "as" FROM espn_stats WHERE market_id IS NOT NULL AND hs IS NOT NULL AND minute>=89 ORDER BY market_id, ts DESC""",con)
print("games with an ESPN final score on a matched market:",len(fin))
px=pd.read_sql("""SELECT market_id, sel, minute, ts, lay_px::float lay_px, back_px::float back_px FROM liq_sample WHERE mkt='MO' AND lay_px IS NOT NULL AND back_px IS NOT NULL AND lay_px<=back_px*1.25
                  AND market_id IN (SELECT DISTINCT market_id FROM espn_stats WHERE market_id IS NOT NULL AND minute>=89)""",con)
d=px.merge(fin,on='market_id'); print("price samples:",len(d))
d['won']=np.where(d.sel=='HOME',d.hs>d['as'],np.where(d.sel=='AWAY',d['as']>d.hs,d.hs==d['as']))
# lay £10 liability-equivalent: stake = 10/(lay-1) so liability £10; pnl = +stake*0.98 if runner loses, -10 if it wins
d['stake']=10/(d.lay_px-1); d['pnl']=np.where(d.won,-10.0,d.stake*0.98)
d['band']=pd.cut(d.lay_px,[1,1.5,2,3,4,6,10,20,1000],labels=['<1.5','1.5-2','2-3','3-4','4-6','6-10','10-20','20+'])
d['phase']=pd.cut(d.minute,[-1,2,20,40,70,200],labels=['KO','3-20','21-40','41-70','71+'])
d['half']=(pd.to_datetime(d.ts)>pd.to_datetime(d.ts).median())
def rep(g,by):
    t=g.groupby(by,observed=True).agg(n=('pnl','size'),games=('market_id','nunique'),win_rate=('won','mean'),pnl10=('pnl','mean'),h1=('pnl',lambda x:x[~g.loc[x.index,'half']].mean()),h2=('pnl',lambda x:x[g.loc[x.index,'half']].mean())).round(3)
    print(t.to_string())
print("\n== LAY at the lay touch, per £10 liability, by price band (all phases)"); rep(d,'band')
print("\n== by band x phase"); rep(d,['band','phase'])
print("\n== BACK at the back touch (mirror), per £10 stake, by band")
d['bpnl']=np.where(d.won,10*(d.back_px-1)*0.98,-10.0); 
print(d.groupby('band',observed=True).agg(n=('bpnl','size'),pnl10=('bpnl','mean')).round(3).to_string())
print("\ndate range:",d.ts.min(),"->",d.ts.max())
PY
