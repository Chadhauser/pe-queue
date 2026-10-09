#!/bin/bash
# 006: DATA-LED in-play edge search. No bands, no hypotheses. Every observable at every minute -> a gradient-boosted model
# learns where the MARKET's probability is wrong. Train 2024/25, test 2025/26. Edge = out-of-sample P&L of betting where
# the model disagrees with the market by k points, at the fresh LTP, 2pct spread, 2pct comm, held to full time.
cd /root/pe-scan && (python3 -c "import lightgbm" 2>/dev/null || pip install -q lightgbm 2>&1 | tail -1) && cat > market_error.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
import lightgbm as lgb
SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("""SELECT match_date, competition, home_team, away_team, goal_times, mo_home_back, mo_draw_back, mo_away_back, o25_back, u25_back,
               hf_pts, af_pts, hf_ave, af_ave, p6_hxg, p6_axg, ps_hxg, ps_axg, goal_ratio_all, home_rank, away_rank, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'""")
G={}; LG={}
for r in cur.fetchall():
    d=datetime.date.fromisoformat(str(r[0])[:10]); goals=[]
    for t in (r[4] or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    f=lambda x: float(x) if x not in (None,'') else np.nan
    G[(d,norm(r[2]),norm(r[3]))]=dict(goals=sorted(goals),lg=r[1],pm=[f(x) for x in r[5:10]],form=[f(x) for x in r[10:21]],fh=int(r[21]),fa=int(r[22]))
    LG.setdefault(r[1],len(LG))
print("goal/feature records",len(G),flush=True)
rows=[]; n_ev=0; n_seen=0
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL ORDER BY event_id,m")
SELS=[('MO','HOME'),('MO','DRAW'),('MO','AWAY'),('OU25','OVER'),('OU25','UNDER')]
def process(buf):
    global n_ev,n_seen
    n_seen+=1
    hw,aw=norm(buf[0][1]),norm(buf[0][2]); d=buf[0][3].date()
    rec=G.get((d,hw,aw)) or G.get((d-datetime.timedelta(days=1),hw,aw)) or G.get((d+datetime.timedelta(days=1),hw,aw))
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_ev} joined",flush=True)
        if n_ev<30: sys.exit("ABORT join")
    if not rec: return
    n_ev+=1
    goals=rec['goals']; season=0 if d<datetime.date(2025,7,1) else 1
    px=collections.defaultdict(dict)
    for _,_,_,m,minute,mkt,sel,ltp in buf:
        if ltp and ltp>1.0: px[(mkt,sel)][minute]=float(ltp)
    first={k:(px[k][min(px[k])] if px[k] else np.nan) for k in SELS}
    res={'HOME':rec['fh']>rec['fa'],'DRAW':rec['fh']==rec['fa'],'AWAY':rec['fh']<rec['fa'],'OVER':rec['fh']+rec['fa']>2.5,'UNDER':rec['fh']+rec['fa']<2.5}
    for t in range(5,88,3):
        if any(0<=t-g<3 for g,_ in goals): continue
        cur_px={k:px[k].get(t) for k in SELS}
        if any(v is None for v in cur_px.values()): continue
        sh=sum(1 for g,s in goals if g<=t and s=='H'); sa=sum(1 for g,s in goals if g<=t and s=='A')
        since=t-max([g for g,_ in goals if g<=t],default=0)
        inv={k:1/v for k,v in cur_px.items()}; mo_tot=inv[('MO','HOME')]+inv[('MO','DRAW')]+inv[('MO','AWAY')]; ou_tot=inv[('OU25','OVER')]+inv[('OU25','UNDER')]
        feats=[t,sh,sa,sh-sa,sh+sa,since,t>45,
               inv[('MO','HOME')]/mo_tot,inv[('MO','DRAW')]/mo_tot,inv[('MO','AWAY')]/mo_tot,inv[('OU25','OVER')]/ou_tot,
               *[ (cur_px[k]/first[k]-1) if first[k]==first[k] and first[k]>0 else np.nan for k in SELS ],
               *rec['pm'],*rec['form'],LG[rec['lg']]]
        for k in SELS:
            rows.append((season,k[0],k[1],cur_px[k],inv[k]/(mo_tot if k[0]=='MO' else ou_tot),int(res[k[1]]),*feats))
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last:
        process(buf); buf=[]
        if n_ev%2000==0 and n_ev: print("events",n_ev,"rows",len(rows),flush=True)
    buf.append(r); last=r[0]
if buf: process(buf)
print("events joined",n_ev,"rows",len(rows),flush=True)
fcols=['minute','sh','sa','diff','tot','since_goal','second_half','mp_home','mp_draw','mp_away','mp_over','mv_home','mv_draw','mv_away','mv_over','mv_under',
       'pm_home','pm_draw','pm_away','pm_o25','pm_u25','hf_pts','af_pts','hf_ave','af_ave','p6_hxg','p6_axg','ps_hxg','ps_axg','goal_ratio','home_rank','away_rank','league']
D=pd.DataFrame(rows,columns=['season','mkt','sel','price','mprob','won']+fcols)
D['sel_id']=D.sel.map({'HOME':0,'DRAW':1,'AWAY':2,'OVER':3,'UNDER':4})
X=D[fcols+['sel_id','mprob']]; y=D.won
tr=D.season==0; te=D.season==1
# model learns P(won | everything incl. market prob). If the market were perfect the model could not beat mprob.
m=lgb.LGBMClassifier(n_estimators=600,learning_rate=0.03,num_leaves=31,min_child_samples=500,subsample=0.8,colsample_bytree=0.8,reg_lambda=5,verbose=-1)
m.fit(X[tr],y[tr],categorical_feature=['league','sel_id'])
p=m.predict_proba(X[te])[:,1]
from sklearn.metrics import log_loss
print(f"\nOUT-OF-SAMPLE 2025/26 log-loss: market {log_loss(y[te],D.mprob[te].clip(0.001,0.999)):.5f}  model {log_loss(y[te],np.clip(p,0.001,0.999)):.5f}  (lower is better; rows {te.sum()})")
T=D[te].copy(); T['p']=p; T['edge']=T.p-T.mprob
T['back']=np.where(T.won==1,(T.price*(1-SPREAD)-1)*(1-COMM),-1.0); T['lay']=np.where(T.won==1,-(T.price*(1+SPREAD)-1),(1-COMM))
print("\nP&L per £100 on 2025/26 (never seen) when betting where model disagrees with market by k points — the data-led edge table:")
for k in (0.02,0.03,0.05,0.08):
    b=T[T.edge>=k]; l=T[T.edge<=-k]
    print(f"  k={k:.2f}: BACK n={len(b):6d} per100={100*b.back.mean() if len(b) else 0:+6.1f}   LAY n={len(l):6d} per100={100*l.lay.mean() if len(l) else 0:+6.1f}")
print("\nBy market/selection at k=0.03:")
for (mk,s),g in T.groupby(['mkt','sel']):
    b=g[g.edge>=0.03]; l=g[g.edge<=-0.03]
    print(f"  {mk:5} {s:5}: BACK n={len(b):5d} {100*b.back.mean() if len(b) else 0:+6.1f} | LAY n={len(l):5d} {100*l.lay.mean() if len(l) else 0:+6.1f}")
print("\nTop 15 features by importance (what the data says matters):")
imp=pd.Series(m.feature_importances_,index=X.columns).sort_values(ascending=False); print(imp.head(15).to_string())
T[['mkt','sel','minute','sh','sa','price','mprob','p','edge','won','back','lay','league']].to_csv('/root/pe-scan/market_error_test_rows.csv',index=False)
cur2=con.cursor(); con.autocommit=True
cur2.execute("DROP TABLE IF EXISTS market_error_v1"); cur2.execute("CREATE TABLE market_error_v1 (k NUMERIC, side TEXT, n INT, per100 NUMERIC)")
for k in (0.02,0.03,0.05,0.08):
    b=T[T.edge>=k]; l=T[T.edge<=-k]
    cur2.execute("INSERT INTO market_error_v1 VALUES (%s,'BACK',%s,%s),(%s,'LAY',%s,%s)",(k,len(b),float(100*b.back.mean()) if len(b) else None,k,len(l),float(100*l.lay.mean()) if len(l) else None))
print("\nwritten market_error_v1")
PYFILE
python3 market_error.py
