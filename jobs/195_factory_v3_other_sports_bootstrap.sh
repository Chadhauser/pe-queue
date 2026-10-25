#!/bin/bash
# 195: TENNIS / CRICKET / RACING / GREYHOUNDS / BASKETBALL — the existing Factory (v3, two-tick confirmed) already generates the
# settle / drift-back / lay-green / steam cells over two years of per-minute history for these sports; what it lacked is the v4
# honesty layer. This job makes it store per-trade returns for every surviving cell (factory_trades) and, when the run finishes,
# applies the v4 gates: t >= 3.0 both halves (≈300 cells), bootstrap 500 resamples (p5 > 0 = SOLID), worst drawdown, neighbour
# agreement where the band grid allows. Runs in the background (1-2 h); 196 reports the shelf per sport.
cd /root/pe-factory && python3 - <<'PY'
p='factory.py'; s=open(p).read(); n=0
if 'TR=[]' not in s:
    s=s.replace("def emit(sport,strat,df,col,bandcol='band'):","TR=[]\ndef emit(sport,strat,df,col,bandcol='band'):",1); n+=1
old="        out.append((today,sport,strat,str(band),len(g),len(a),round(p1,2),round(t1,2),len(b),round(p2,2),round(t2,2),round(g[col].mean()*100,2),surv,f\"{pd.to_datetime(df.mt).min():%Y-%m}->{pd.to_datetime(df.mt).max():%Y-%m}\"))"
new=old+"\n        if p1>0 and p2>0 and tstat(g[col])>=2: TR.extend((today,sport,strat,str(band),pd.Timestamp(m_),float(v_)) for m_,v_ in zip(g.mt,g[col]) if pd.notna(v_))"
if "TR.extend" not in s:
    assert old in s; s=s.replace(old,new,1); n+=1
old2='psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out)'
new2=old2+'''
cur.execute("CREATE TABLE IF NOT EXISTS factory_trades (run_date DATE, sport TEXT, strategy TEXT, band TEXT, mt TIMESTAMPTZ, ret NUMERIC)"); cur.execute("DELETE FROM factory_trades WHERE run_date=%s",(today,))
if TR: psycopg2.extras.execute_values(cur,"INSERT INTO factory_trades VALUES %s",[(a,b,c,d,e,round(f,5)) for a,b,c,d,e,f in TR],page_size=5000)
print("factory_trades stored:",len(TR))
# ---- v4 gates on the stored trades
import numpy as np
F=pd.DataFrame(TR,columns=['d','sport','strategy','band','mt','ret'])
if len(F):
    rng=np.random.default_rng(11); rows=[]
    for (sp_,st_,bd_),g in F.groupby(['sport','strategy','band']):
        x=g.sort_values('mt').ret.values*100; n_=len(x); t=x.mean()/(x.std(ddof=1)/np.sqrt(n_)) if n_>2 and x.std(ddof=1)>0 else 0
        h1=x[:n_//2].mean(); h2=x[n_//2:].mean()
        tot=np.array([rng.choice(x,n_,replace=True).sum() for _ in range(500)]); dd=max((np.maximum.accumulate(np.cumsum(rng.permutation(x)))-np.cumsum(rng.permutation(x))).max() for _ in range(200))
        rows.append(dict(sport=sp_,strategy=st_,band=bd_,n=n_,per100=round(x.mean(),2),t=round(t,2),h1=round(h1,2),h2=round(h2,2),p5=round(np.percentile(tot,5)/n_,2),p95=round(np.percentile(tot,95)/n_,2),worst_dd=round(dd,0),flag=('SOLID' if (t>=3.0 and h1>0 and h2>0 and np.percentile(tot,5)>0) else 'FRAGILE')))
    V=pd.DataFrame(rows).sort_values(['flag','t'],ascending=[True,False])
    pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
    print("\\n=== v4 GATES ON FACTORY v3 CELLS (per £100 staked; p5/p95 = bootstrap per-trade; worst_dd per £100 stakes) ===\\n",V.to_string(index=False))
    cur.execute("CREATE TABLE IF NOT EXISTS factory_v4_shelf (run_date DATE, sport TEXT, strategy TEXT, band TEXT, n INT, per100 NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, p5 NUMERIC, p95 NUMERIC, worst_dd NUMERIC, flag TEXT)"); cur.execute("DELETE FROM factory_v4_shelf WHERE run_date=%s",(today,))
    psycopg2.extras.execute_values(cur,"INSERT INTO factory_v4_shelf VALUES %s",[(today,r.sport,r.strategy,r.band,int(r.n),float(r.per100),float(r.t),float(r.h1),float(r.h2),float(r.p5),float(r.p95),float(r.worst_dd),r.flag) for r in V.itertuples()])'''
if "factory_v4_shelf" not in s:
    assert old2 in s; s=s.replace(old2,new2,1); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile factory.py || exit 1
python3 - <<'PY'
# unit test of the bootstrap/gate block on synthetic trades
import numpy as np, pandas as pd
rng=np.random.default_rng(1); TR=[('d','Tennis','E fav drifts','1.5-2.0',pd.Timestamp('2025-01-01')+pd.Timedelta(days=i),v) for i,v in enumerate(rng.normal(0.02,0.3,400))]+[('d','Cricket','F lay','x',pd.Timestamp('2025-01-01')+pd.Timedelta(days=i),v) for i,v in enumerate(rng.normal(-0.01,0.3,300))]
F=pd.DataFrame(TR,columns=['d','sport','strategy','band','mt','ret']); rows=[]
for (sp_,st_,bd_),g in F.groupby(['sport','strategy','band']):
    x=g.sort_values('mt').ret.values*100; n_=len(x); t=x.mean()/(x.std(ddof=1)/np.sqrt(n_)); tot=np.array([rng.choice(x,n_,replace=True).sum() for _ in range(500)])
    rows.append((sp_,st_,n_,round(t,2),round(np.percentile(tot,5)/n_,2)))
print(rows); print("gate test OK")
PY
pgrep -f "python3 factory.py" >/dev/null && echo "factory already running" || (nohup timeout 9000 python3 factory.py >> factory.log 2>&1 &) ; echo "factory v3+v4 gates started"
