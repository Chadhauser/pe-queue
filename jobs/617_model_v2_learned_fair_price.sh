#!/bin/bash
# 617 (Mon 16 Nov 2026, 16:35). Fair price v2: a learned model instead of price bands. Per sport, a gradient-boosted classifier predicts each
# runner's chance from: price 2 min before the off, its moves from 3 h / 60 / 30 / 10 min before, country, hour, weekday, runners in the
# market, the runner's rank, market type. Time split per sport: train oldest 50%, choose the betting margin on the next 25%, judge on the
# newest 25% (never seen). Bets at a tradable price (one tick worse than the last trade), 2% commission. Also reports whether the model's
# probabilities beat the market's own (log loss) on the unseen quarter: if they don't, there is no edge to find this way.
# Sized for the current 8 GB box (sampled markets per type); runs after 613 finishes, in the background. Writes reports/model_v2.md.
[ -f /root/pe-queue/reports/execution_methods.md ] || { echo "waiting for 613 to finish"; exit 75; }
python3 -c "import sklearn" 2>/dev/null || pip install -q scikit-learn --break-system-packages 2>&1 | tail -1
cat > /root/pe-sports/team/model_v2.py <<'PY'
import sys, datetime, numpy as np, pandas as pd, psycopg2
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import log_loss
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; STAKE=2.0; PER_TYPE=15000
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for hi,t in LADDER:
        if p<hi: return t
    return 10
up=np.vectorize(lambda p: round(min(1000,p+tick(p)),2)); down=np.vectorize(lambda p: round(max(1.01,p-tick(p-1e-9)),2))
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='7200s'"); c.execute("SET work_mem='128MB'")
c.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_result GROUP BY 1,2 HAVING count(DISTINCT market_id)>=1500 ORDER BY 1,3 DESC")
TYPES=[(s,m) for s,m,n in c.fetchall() if not any(k in m for k in ('ASIAN','HANDICAP','LINE','TOTAL_GOALS'))]
out=[f"# Fair price v2 — learned model, {datetime.datetime.utcnow():%F %H:%M} UTC","",
     "Price 2 min before the off plus its moves (3 h, 60, 30, 10 min), country, hour, weekday, runners, rank, market type. Per sport: train oldest 50%,",
     "choose the margin on the next 25%, judge on the newest 25% (unseen). Tradable price = one tick worse than the last trade. 2% commission, £2 a bet.",""]
frames=[]
for sport,mt in TYPES:
    q="""WITH mk AS (SELECT DISTINCT market_id FROM bf_hist_result WHERE sport=%s AND market_type=%s ORDER BY market_id LIMIT %s),
    agg AS (SELECT o.market_id, o.sel, max(o.market_time) mt, max(o.country) country,
      (array_agg(o.ltp ORDER BY o.ts DESC) FILTER (WHERE o.ts<=o.market_time-interval '120 seconds'))[1] p0,
      (array_agg(o.ltp ORDER BY o.ts DESC) FILTER (WHERE o.ts<=o.market_time-interval '10 minutes'))[1] p10,
      (array_agg(o.ltp ORDER BY o.ts DESC) FILTER (WHERE o.ts<=o.market_time-interval '30 minutes'))[1] p30,
      (array_agg(o.ltp ORDER BY o.ts DESC) FILTER (WHERE o.ts<=o.market_time-interval '60 minutes'))[1] p60,
      (array_agg(o.ltp ORDER BY o.ts ASC))[1] p180
      FROM bf_hist_other o JOIN mk USING (market_id) WHERE o.sport=%s AND o.market_type=%s AND NOT o.inplay AND o.ltp>1 AND o.ltp<1000
        AND o.ts>=o.market_time-interval '3 hours' GROUP BY 1,2)
    SELECT a.*, (r.status='WINNER')::int won FROM agg a JOIN bf_hist_result r ON r.market_id=a.market_id AND r.sel=a.sel WHERE r.status IN ('WINNER','LOSER') AND a.p0 IS NOT NULL"""
    try: d=pd.read_sql(q,con,params=(sport,mt,PER_TYPE,sport,mt))
    except Exception as e: con.rollback(); out.append(f"- {sport}/{mt}: query failed {str(e)[:80]}"); continue
    if len(d)<2000: continue
    d['sport']=sport; d['mtype']=mt; frames.append(d); print(sport,mt,len(d),flush=True)
D=pd.concat(frames,ignore_index=True)
for col in ('p0','p10','p30','p60','p180'): D[col]=D[col].astype(float)
for col in ('p10','p30','p60','p180'): D[col]=D[col].fillna(D.p0)
D['imp']=1/D.p0; D['lg']=np.log(D.imp/(1-D.imp).clip(1e-6))
for k in ('p10','p30','p60','p180'): D['mv_'+k]=np.log(D[k]/D.p0)
D['mt']=pd.to_datetime(D.mt,utc=True); D['hour']=D.mt.dt.hour; D['dow']=D.mt.dt.dayofweek
D['nrun']=D.groupby('market_id').sel.transform('count'); D['rank']=D.groupby('market_id').p0.rank(method='first')
D['book']=D.groupby('market_id').imp.transform('sum'); D['imp_n']=D.imp/D.book
D['country_c']=D.country.fillna('?').astype('category').cat.codes; D['mtype_c']=D.mtype.astype('category').cat.codes
F=['lg','imp_n','mv_p10','mv_p30','mv_p60','mv_p180','hour','dow','nrun','rank','book','country_c','mtype_c']
CAT=[F.index('country_c'),F.index('mtype_c')]
res_all=[]
out+=["| sport | runners | model log loss vs market (unseen) | margin chosen | unseen bets | unseen per £100 | unseen 1st half | unseen 2nd half |","|---|---|---|---|---|---|---|---|"]
for sport,S in D.groupby('sport'):
    S=S.sort_values('mt'); q50,q75=S.mt.quantile(0.5),S.mt.quantile(0.75)
    tr=S[S.mt<q50]; va=S[(S.mt>=q50)&(S.mt<q75)]; te=S[S.mt>=q75]
    if len(tr)<3000 or len(te)<1000: continue
    m=HistGradientBoostingClassifier(max_iter=300,learning_rate=0.05,max_leaf_nodes=31,l2_regularization=1.0,categorical_features=CAT,random_state=1)
    m.fit(tr[F],tr.won)
    def bets(X,margin):
        qv=m.predict_proba(X[F])[:,1]; pb=down(X.p0.values); pl=up(X.p0.values)
        vb=qv*pb-1; vl=1-qv*pl
        side=np.where(vb>=margin,'BACK',np.where(vl>=margin,'LAY',''))
        price=np.where(side=='BACK',pb,pl); won=X.won.values
        g=np.where(side=='BACK',np.where(won==1,(price-1)*STAKE,-STAKE),np.where(won==1,-(price-1)*STAKE,STAKE))
        pnl=np.where(g>0,g*(1-COMM),g); keep=side!=''
        return pd.DataFrame({'mt':X.mt.values[keep],'pnl':pnl[keep],'side':side[keep],'mtype':X.mtype.values[keep]})
    ll_m=log_loss(te.won,np.clip(m.predict_proba(te[F])[:,1],1e-6,1-1e-6)); ll_k=log_loss(te.won,np.clip(te.imp_n,1e-6,1-1e-6))
    best=None
    for mg in (0.01,0.02,0.04,0.06,0.10):
        b=bets(va,mg)
        if len(b)>=300:
            r=b.pnl.sum()/(len(b)*STAKE)
            if best is None or r>best[1]: best=(mg,r)
    if best is None: out.append(f"| {sport} | {len(S)} | {ll_m:.4f} vs {ll_k:.4f} | none with 300+ bets | | | | |"); continue
    b=bets(te,best[0]).sort_values('mt'); h=len(b)//2; f=lambda x: f"£{x.pnl.sum()/(len(x)*STAKE)*100:+.1f}" if len(x) else "-"
    out.append(f"| {sport} | {len(S)} | {ll_m:.4f} vs {ll_k:.4f} ({'model better' if ll_m<ll_k else 'market better'}) | {best[0]:.0%} | {len(b)} | {f(b)} | {f(b.iloc[:h])} | {f(b.iloc[h:])} |")
    b['sport']=sport; res_all.append(b)
if res_all:
    A=pd.concat(res_all); out+=["","Unseen quarter, by market type (bets, per £100):",""]
    for (sp,mt),g in A.groupby(['sport','mtype']):
        if len(g)>=50: out.append(f"- {sp} {mt}: {len(g)} bets, £{g.pnl.sum()/(len(g)*STAKE)*100:+.1f}")
out+=["","Lower log loss = better probabilities. If the model is not better than the market on the unseen quarter, any profit above is luck."]
open('/root/pe-queue/reports/model_v2.md','w').write("\n".join(out)+"\n"); print("\n".join(out))
PY
python3 -m py_compile /root/pe-sports/team/model_v2.py && echo compiles || exit 1
cd /root/pe-sports/team && nohup bash -c 'nice -n 10 timeout 14400 python3 model_v2.py > model_v2.log 2>&1; cd /root/pe-queue && git add reports/model_v2.md && git commit -qm "fair price v2 learned model" && git pull -q --no-rebase --no-edit && git push -q' >/dev/null 2>&1 &
sleep 20; tail -2 /root/pe-sports/team/model_v2.log
echo "617 done (running in the background)"
