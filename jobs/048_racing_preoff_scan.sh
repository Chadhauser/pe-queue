#!/bin/bash
# 048: RACING PRE-OFF SCAN — same machine as football, pointed at our own racing tape. bf_racing_log: 5.77M rows, 1,427 races,
# 7 Sep–11 Oct 2026, best back/lay + last traded every ~60s with mins_to_off; racing_results: BSP + won per runner.
# States: price band at 10 min × move 10m->5m (steam/drift) × market rank × field size. For every state: (a) SCALP back at 5m,
# close at BSP (and back at 10m close at 5m); (b) LAY at 5m close at BSP; (c) BACK-TO-WIN at 5m price vs at BSP (is the 5m price
# better or worse than the start price?). 2pct spread each way, 2pct comm. Train = to 30 Sep, test = Oct. Data-led: every cell printed,
# survivors = positive both halves, n>=150 train / 60 test, t>=2 both.
cd /root/pe-scan && cat > racing_preoff_scan.py <<'PYFILE'
import sys, math, datetime, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
con=psycopg2.connect(DB,sslmode='require')
R=pd.read_sql("SELECT market_id, selection_id, runner, venue, market_name, market_start, won, bsp FROM racing_results WHERE bsp IS NOT NULL AND bsp>1",con)
R['bsp']=R.bsp.astype(float); print("results rows",len(R),"races",R.market_id.nunique(),flush=True)
# pre-off prices at fixed points: take the snapshot nearest each target mins_to_off within ±0.75 min
T=pd.read_sql("""SELECT market_id, selection_id, mins_to_off, back_price, lay_price, last_traded, total_matched, runners, captured_at
                 FROM bf_racing_log WHERE inplay=false AND mins_to_off BETWEEN -0.5 AND 12.5 AND back_price IS NOT NULL AND lay_price IS NOT NULL""",con)
print("pre-off rows",len(T),flush=True)
T['mid']=(T.back_price.astype(float)+T.lay_price.astype(float))/2
pts={'p10':10,'p5':5,'p3':3,'p1':1,'p0':0.25}
out=None
for name,m in pts.items():
    s=T[(T.mins_to_off-m).abs()<=0.75].copy(); s['d']=(s.mins_to_off-m).abs()
    s=s.sort_values('d').drop_duplicates(['market_id','selection_id'])[['market_id','selection_id','mid','back_price','lay_price','total_matched','runners']]
    s=s.rename(columns={'mid':name,'back_price':name+'_b','lay_price':name+'_l','total_matched':name+'_tm','runners':'runners_'+name})
    out=s if out is None else out.merge(s,on=['market_id','selection_id'],how='outer')
D=out.merge(R,on=['market_id','selection_id'],how='inner')
D=D[D.p10.notna()&D.p5.notna()]
D['date']=pd.to_datetime(D.market_start).dt.date
D['split']=np.where(pd.to_datetime(D.market_start)<pd.Timestamp('2026-10-01'),'train Sep','test Oct')
D['field']=D.groupby('market_id').selection_id.transform('count')
D['rank10']=D.groupby('market_id').p10.rank(method='first')
D['band10']=pd.cut(D.p10,[1,2,3,5,8,12,20,1000],labels=['<2','2-3','3-5','5-8','8-12','12-20','20+'])
D['move']=D.p5/D.p10-1
D['mv']=pd.cut(D.move,[-9,-0.15,-0.07,-0.02,0.02,0.07,0.15,9],labels=['steam15+','steam7-15','steam2-7','flat','drift2-7','drift7-15','drift15+'])
D['fav']=np.where(D.rank10==1,'fav',np.where(D.rank10<=3,'2nd-3rd','rest'))
D['fieldb']=pd.cut(D.field,[0,6,9,13,40],labels=['<=6','7-9','10-13','14+'])
for c in ('p10','p5','p3','p1','p0','bsp'): D[c]=D[c].astype(float)
def back_then_lay(e,x):  # back at e (pay spread), lay at x
    p=(e*(1-SPREAD))/(x*(1+SPREAD))-1; return p*(1-COMM) if p>0 else p
def lay_then_back(e,x):
    p=1-(e*(1+SPREAD))/(x*(1-SPREAD)); return p*(1-COMM) if p>0 else p
D['scalp_b5_bsp']=[back_then_lay(e,x) for e,x in zip(D.p5,D.bsp)]
D['scalp_l5_bsp']=[lay_then_back(e,x) for e,x in zip(D.p5,D.bsp)]
D['scalp_b10_5']=[back_then_lay(e,x) for e,x in zip(D.p10,D.p5)]
D['win5']=np.where(D.won,(D.p5*(1-SPREAD)-1)*(1-COMM),-1.0)       # back to win at the 5m price
D['winbsp']=np.where(D.won,(D.bsp-1)*(1-COMM),-1.0)                 # back to win at BSP (benchmark)
D['lay5']=np.where(D.won,-(D.p5*(1+SPREAD)-1),(1-COMM))             # lay to lose at 5m, per £1 stake
D['lay5_liab']=D.lay5/np.where(D.won,1,1)/(D.p5*(1+SPREAD)-1).clip(lower=0.01)  # per £1 liability
pd.set_option('display.width',260); pd.set_option('display.max_rows',400)
print(f"\nrunners with 10m+5m price and BSP: {len(D)} | races {D.market_id.nunique()} | train {int((D.split=='train Sep').sum())} test {int((D.split=='test Oct').sum())}")
print("\n=== 0. Does the 5-min price beat BSP as a predictor? back-to-win ROI per £100 by band (5m price vs BSP) ===")
print(D.groupby(['band10','split'],observed=True)[['win5','winbsp']].mean().mul(100).round(1).unstack('split').to_string())
def tstat(x): x=x.dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def survivors(cols,measures,title,min_tr=150,min_te=60):
    rows=[]
    for key,g in D.groupby(cols,observed=True):
        tr=g[g.split=='train Sep']; te=g[g.split=='test Oct']
        if len(tr)<min_tr or len(te)<min_te: continue
        for m in measures:
            a,b=tr[m].mean()*100,te[m].mean()*100; ta,tb=tstat(tr[m]),tstat(te[m])
            rows.append((*(key if isinstance(key,tuple) else (key,)),m,len(tr),round(a,1),round(ta,1),len(te),round(b,1),round(tb,1)))
    S=pd.DataFrame(rows,columns=[*cols,'measure','n_tr','per100_tr','t_tr','n_te','per100_te','t_te'])
    ok=S[(S.per100_tr>1)&(S.per100_te>1)&(S.t_tr>=2)&(S.t_te>=2)]
    print(f"\n=== {title}: cells {len(S)} | train-qualifying {int(((S.per100_tr>1)&(S.t_tr>=2)).sum())} | SURVIVORS both halves {len(ok)} ===")
    if len(ok): print(ok.sort_values('per100_te',ascending=False).head(40).to_string(index=False))
    print("-- biggest train effects regardless (top 15):"); print(S.reindex(S.per100_tr.abs().sort_values(ascending=False).index).head(15).to_string(index=False))
    return S
survivors(['band10','mv'],['scalp_b5_bsp','scalp_l5_bsp'],'1. SCALP 5m -> BSP by price band x 10m->5m move')
survivors(['fav','mv','fieldb'],['scalp_b5_bsp','scalp_l5_bsp'],'2. SCALP by rank x move x field size')
survivors(['band10','mv'],['scalp_b10_5'],'3. SCALP 10m -> 5m (does a move continue?)')
survivors(['band10','mv','fav'],['win5','lay5_liab'],'4. BACK-TO-WIN / LAY-TO-LOSE at 5m by band x move x rank')
# steam/drift continuation summary
print("\n=== 5. Momentum: after a 10m->5m move, what does the price do by the off (median pct change 5m -> BSP)? ===")
print(D.assign(cont=(D.bsp/D.p5-1)*100).groupby(['mv','split'],observed=True).cont.agg(['size','median','mean']).round(2).unstack('split').to_string())
print("\n=== 6. Liquidity: median total matched at 5m and 1m by band (what size the scalp can carry) ===")
print(D.groupby('band10',observed=True)[['p5_tm','p1_tm']].median().round(0).to_string())
print("\nVERDICT RULE: a cell is a candidate only if positive in BOTH halves with t>=2 both; 5 weeks is ONE season-fifth — anything that passes goes to £2 live and must survive a second month before scaling.")
PYFILE
python3 racing_preoff_scan.py
