#!/bin/bash
# 246: RACING PLACE MARKETS AT BSP — never looked at. racing_bsp holds UK+IE 'place' files (116k runner rows, Dec 2021-Oct 2026) with
# BSP and win_lose (placed or not). Same honest cut as the WIN test (222): lay and back at place BSP by band x year x country x field
# size, 2% commission, per £100 stake and % of liability. Also the WIN-vs-PLACE relationship: for runners in both files, the implied
# place probability from the win BSP (Harville, field size) vs the place BSP — is either side systematically mispriced?
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',230); pd.set_option('display.max_rows',300); con=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT country, event_dt, event_name, selection_id, selection_name, win_lose, bsp::float bsp FROM racing_bsp WHERE market='place' AND bsp IS NOT NULL AND bsp>1 AND win_lose IN (0,1)",con)
print("place runners:",len(d),"| races:",d.groupby(['event_dt','event_name']).ngroups,"|",d.event_dt.min().date(),"->",d.event_dt.max().date())
d['year']=d.event_dt.dt.year; d['band']=pd.cut(d.bsp,[1,1.3,1.6,2,3,5,8,15,1000],labels=['1-1.3','1.3-1.6','1.6-2','2-3','3-5','5-8','8-15','15+'])
d['lay']=np.where(d.win_lose==1,-100*(d.bsp-1),98.0); d['back']=np.where(d.win_lose==1,100*(d.bsp-1)*0.98,-100.0); d['liab']=100*(d.bsp-1)
fs=d.groupby(['event_dt','event_name']).bsp.transform('size'); d['field']=pd.cut(fs,[0,7,10,13,40],labels=['<=7','8-10','11-13','14+'])
def agg(g): return pd.Series(dict(n=len(g),lay100=round(g.lay.mean(),2),lay_roi_liab=round(100*g.lay.sum()/g.liab.sum(),2),back100=round(g.back.mean(),2),t_lay=round(g.lay.mean()/(g.lay.std(ddof=1)/np.sqrt(len(g))),2),t_back=round(g.back.mean()/(g.back.std(ddof=1)/np.sqrt(len(g))),2),placed=round((g.win_lose==1).mean(),3)))
print("\n=== PLACE BSP by band (all years) ===\n",d.groupby('band',observed=True).apply(agg).to_string())
print("\n=== by band x year: lay per £100 ===\n",d.groupby(['band','year'],observed=True).lay.mean().unstack('year').round(2).to_string())
print("\n=== by band x year: back per £100 ===\n",d.groupby(['band','year'],observed=True).back.mean().unstack('year').round(2).to_string())
print("\n=== by band x country ===\n",d.groupby(['band','country'],observed=True).apply(agg)[['n','lay100','back100']].unstack('country').round(2).to_string())
print("\n=== by band x field size ===\n",d.groupby(['band','field'],observed=True).apply(agg)[['n','lay100','back100']].unstack('field').round(2).to_string())
# win vs place consistency
w=pd.read_sql("SELECT event_dt, event_name, selection_id, bsp::float wbsp FROM racing_bsp WHERE market='win' AND bsp IS NOT NULL AND bsp>1",con)
m=d.merge(w,on=['event_dt','event_name','selection_id'],how='inner'); print("\nrunners with both win and place BSP:",len(m))
if len(m):
    m['n_field']=m.groupby(['event_dt','event_name']).wbsp.transform('size'); m['places']=np.where(m.n_field>=8,3,np.where(m.n_field>=5,2,1))
    m['pwin']=1/m.wbsp; m['pwin_n']=m.pwin/m.groupby(['event_dt','event_name']).pwin.transform('sum')
    # crude place probability: Harville first-two/three approximation = min(1, places * pwin_n * adjustment) ; use simple scaling and compare to 1/place bsp
    m['p_place_impl']=np.clip(m.places*m.pwin_n*0.9,0,0.98); m['p_place_mkt']=1/m.bsp
    m['edge']=m.p_place_impl-m.p_place_mkt; m['eb']=pd.cut(m.edge,[-1,-0.1,-0.05,0,0.05,0.1,1])
    print("\n=== back place by (model - market) place probability gap; per £100 back ===\n",m.groupby('eb',observed=True).agg(n=('back','size'),back100=('back','mean'),lay100=('lay','mean'),placed=('win_lose','mean')).round(2).to_string())
PY
