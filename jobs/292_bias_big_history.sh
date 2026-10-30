#!/bin/bash
# 292: favourite-longshot bias at scale — two seasons of Betfair in-play Match Odds (bf_hist_price, 1-min LTP) joined to API-Football
# results via af_price_map (291). Lay every runner at LTP+1 tick (conservative for a lay) by price band x minute band, hold to settle,
# 2% commission, per £10 liability; both halves by date; per league group. Needs 291's map; waits (75) until it exists.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
try: cur.execute("SELECT count(*) FROM af_price_map"); n=cur.fetchone()[0]
except Exception: print("map missing"); sys.exit(75)
if n<1000: print("map too small",n); sys.exit(75)
res=pd.read_sql("""SELECT m.event_id, f.hg, f.ag, f.league FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status IN ('FT','AET','PEN')""",con)
print("games with results:",len(res))
tot=[]
for i in range(0,len(res),2000):
    sub=res.iloc[i:i+2000]
    p=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 90 AND ltp>1.01",con,params=(list(sub.event_id),))
    d=p.merge(sub,on='event_id'); tot.append(d)
d=pd.concat(tot); print("price samples:",len(d))
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
d['lay']=d.ltp+d.ltp.map(tick)
d['won']=np.where(d.sel=='HOME',d.hg>d.ag,np.where(d.sel=='AWAY',d.ag>d.hg,d.hg==d.ag))
d['pnl']=np.where(d.won,-10.0,(10/(d.lay-1))*0.98)
d['band']=pd.cut(d.lay,[1,1.5,2,3,4,6,10,20,1000],labels=['<1.5','1.5-2','2-3','3-4','4-6','6-10','10-20','20+'])
d['phase']=pd.cut(d.minute,[-1,2,20,40,70,200],labels=['KO','3-20','21-40','41-70','71+'])
d['half']=pd.to_datetime(d.m)>pd.to_datetime(d.m).median()
def t(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0
g=d.groupby(['band','phase'],observed=True).agg(n=('pnl','size'),games=('event_id','nunique'),win=('won','mean'),pnl10=('pnl','mean'),t=('pnl',t),h1=('pnl',lambda x:x[~d.loc[x.index,'half']].mean()),h2=('pnl',lambda x:x[d.loc[x.index,'half']].mean())).round(3)
print("\n== LAY at LTP+1 tick, per £10 liability, band x phase"); print(g.to_string())
print("\n== per league group, lay 6-10 and 20+ before 70'")
d['grp']=d.league.str.replace(r' .*','',regex=True)
s=d[d.band.isin(['6-10','20+'])&(d.minute<=70)]
print(s.groupby(['band','league'],observed=True).agg(n=('pnl','size'),pnl10=('pnl','mean'),t=('pnl',t)).round(3).sort_values('t',ascending=False).head(30).to_string())
PY
