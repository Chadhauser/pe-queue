#!/bin/bash
# 221: RACING LAY-AT-BSP, PROPERLY. The factory flagged "lay at SP 5-10 / 10-20" SOLID on two years of per-minute data. racing_bsp holds
# Betfair's own BSP + result files (UK+IE WIN, from Jan 2022) — a single clearing price, so no spread assumption is needed, only 2%
# commission on winning lays. Per band x year x country x race type: n, P&L per £100 stake, ROI on liability, win rate. Out-of-sample =
# by year. If it holds every year it is a volume line (~80 bets/day) that needs no bot beyond a BSP lay order placed pre-off.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',230); pd.set_option('display.max_rows',300)
con=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT country, event_dt, menu_hint, event_name, win_lose, bsp::float bsp, ip_vol::float ip_vol, pp_vol::float pp_vol FROM racing_bsp WHERE market='WIN' AND bsp IS NOT NULL AND bsp>1 AND win_lose IN (0,1)",con)
print("runners:",len(d),"| races:",d.groupby(['event_dt','event_name']).ngroups,"| dates:",d.event_dt.min().date(),"->",d.event_dt.max().date())
d['year']=d.event_dt.dt.year
d['band']=pd.cut(d.bsp,[1,2,3,5,8,12,20,50,1000],labels=['1-2','2-3','3-5','5-8','8-12','12-20','20-50','50+'])
d['lay']=np.where(d.win_lose==1,-100*(d.bsp-1),98.0)          # £100 lay stake, 2% comm on the win
d['liab']=100*(d.bsp-1)
mh=d.menu_hint.fillna('').str.lower(); d['rtype']=np.select([mh.str.contains('chs|chase'),mh.str.contains('hrd|hurdle'),mh.str.contains('nhf|bumper'),mh.str.contains('hcap')],['chase','hurdle','bumper','flat-hcap'],'flat-other')
def agg(g): return pd.Series(dict(n=len(g),per100=round(g.lay.mean(),2),roi_liab=round(100*g.lay.sum()/g.liab.sum(),2),lay_win=round((g.win_lose==0).mean(),3),t=round(g.lay.mean()/(g.lay.std(ddof=1)/np.sqrt(len(g))),2)))
print("\n=== LAY AT BSP by band (all years) — per £100 stake; roi_liab = % of liability ===\n",d.groupby('band',observed=True).apply(agg).to_string())
print("\n=== by band x year ===\n",d.groupby(['band','year'],observed=True).apply(agg)[['n','per100','roi_liab','t']].unstack('year').round(2).to_string())
print("\n=== by band x country ===\n",d.groupby(['band','country'],observed=True).apply(agg)[['n','per100','roi_liab']].unstack('country').round(2).to_string())
print("\n=== by band x race type ===\n",d.groupby(['band','rtype'],observed=True).apply(agg)[['n','per100','roi_liab']].unstack('rtype').round(2).to_string())
# field size effect
fs=d.groupby(['event_dt','event_name']).bsp.transform('size'); d['field']=pd.cut(fs,[0,6,9,13,40],labels=['<=6','7-9','10-13','14+'])
print("\n=== by band x field size ===\n",d.groupby(['band','field'],observed=True).apply(agg)[['n','per100','roi_liab']].unstack('field').round(2).to_string())
# daily P&L path for the 5-20 band at £10 lay stakes: worst drawdown
s=d[d.bsp.between(5,20)].copy(); s['pl']=s.lay/10; daily=s.groupby(s.event_dt.dt.date).pl.sum(); cum=daily.cumsum(); dd=(cum.cummax()-cum).max()
print(f"\n=== 5-20 band at £10 lay stakes: bets {len(s)} | total £{s.pl.sum():.0f} | per day £{daily.mean():.2f} | worst drawdown £{dd:.0f} | negative days {(daily<0).mean():.0%} | liability per bet £{(s.liab/10).mean():.0f} avg, £{(s.liab/10).max():.0f} max")
print("by year:",s.groupby('year').pl.sum().round(0).to_dict())
PY
