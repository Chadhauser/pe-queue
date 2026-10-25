#!/bin/bash
# 200: 195's patch asserted on an exact-string match. Same patch anchored on line prefixes (line 34 'out.append((today,sport,strat,str(band)'
# and line 103 'execute_values(cur,"INSERT INTO strategy_results'), then restart the factory so this run stores per-trade returns and
# applies the v4 gates (factory_trades, factory_v4_shelf). 196 keeps waiting on it.
cd /root/pe-factory && cp factory.py factory.py.bak200 && python3 - <<'PY'
p='factory.py'; L=open(p).read().split('\n'); n=0
if not any(l.startswith('TR=[]') for l in L):
    i=next(k for k,l in enumerate(L) if l.startswith('def emit(')); L.insert(i,'TR=[]'); n+=1
if not any('TR.extend' in l for l in L):
    i=next(k for k,l in enumerate(L) if l.strip().startswith('out.append((today,sport,strat,str(band)'))
    ind=L[i][:len(L[i])-len(L[i].lstrip())]
    L.insert(i+1,ind+"if p1>0 and p2>0 and tstat(g[col])>=2: TR.extend((today,sport,strat,str(band),pd.Timestamp(m_),float(v_)) for m_,v_ in zip(g.mt,g[col]) if pd.notna(v_))"); n+=1
if not any('factory_v4_shelf' in l for l in L):
    i=next(k for k,l in enumerate(L) if 'execute_values(cur,"INSERT INTO strategy_results' in l)
    block='''import numpy as np
cur.execute("CREATE TABLE IF NOT EXISTS factory_trades (run_date DATE, sport TEXT, strategy TEXT, band TEXT, mt TIMESTAMPTZ, ret NUMERIC)"); cur.execute("DELETE FROM factory_trades WHERE run_date=%s",(today,))
if TR: psycopg2.extras.execute_values(cur,"INSERT INTO factory_trades VALUES %s",[(a,b,c,d,e,round(f,5)) for a,b,c,d,e,f in TR],page_size=5000)
print("factory_trades stored:",len(TR))
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
    print("\\n=== v4 GATES ON FACTORY v3 CELLS (per £100 staked) ===\\n",V.to_string(index=False))
    cur.execute("CREATE TABLE IF NOT EXISTS factory_v4_shelf (run_date DATE, sport TEXT, strategy TEXT, band TEXT, n INT, per100 NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, p5 NUMERIC, p95 NUMERIC, worst_dd NUMERIC, flag TEXT)"); cur.execute("DELETE FROM factory_v4_shelf WHERE run_date=%s",(today,))
    psycopg2.extras.execute_values(cur,"INSERT INTO factory_v4_shelf VALUES %s",[(today,r.sport,r.strategy,r.band,int(r.n),float(r.per100),float(r.t),float(r.h1),float(r.h2),float(r.p5),float(r.p95),float(r.worst_dd),r.flag) for r in V.itertuples()])'''
    L[i+1:i+1]=block.split('\n'); n+=1
s='\n'.join(L)
open(p,'w').write(s); print("patches applied:",n)
PY
python3 -m py_compile factory.py || { cp factory.py.bak200 factory.py; echo "COMPILE FAILED - restored"; exit 1; }
grep -n -E "^TR=\[\]|TR.extend|factory_v4_shelf \(" factory.py | cut -c1-120
pkill -f "python3 factory.py"; sleep 2; (nohup timeout 9000 python3 factory.py >> factory.log 2>&1 &); sleep 5; pgrep -af "python3 factory.py" | head -1; echo "factory restarted with v4 gates"
