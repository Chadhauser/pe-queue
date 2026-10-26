#!/bin/bash
# 249: tennis T2 (first-set comeback, back and hold) becomes a nightly paper book computed from our own in-play tape — table t2_paper,
# rebuilt 05:35 daily from everything the tape holds, so the sample grows without a bot. 26 Oct: 50 entries, +£3.70/£10 settle,
# both halves positive, t 1.9. Added to the morning digest.
mkdir -p /root/pe-factory && cat > /root/pe-factory/t2_nightly.py <<'PYFILE'
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); con=psycopg2.connect(DB,sslmode='require'); SP=0.02; CM=0.02
mk=pd.read_sql("SELECT market_id FROM ip_tape WHERE sport ILIKE 'tennis' AND market_type='MATCH_ODDS' GROUP BY market_id HAVING min(secs_since_start)<=600 AND max(secs_since_start)>=3600 AND count(*)>=60",con)
mids=list(mk.market_id); print("tennis matches tracked from near the start:",len(mids))
T=pd.read_sql("SELECT market_id, event_name, competition, ts, secs_since_start s, status, sel_id, sel_name, back_px::float bp, lay_px::float lp, ltp::float ltp FROM ip_tape WHERE sport ILIKE 'tennis' AND market_type='MATCH_ODDS' AND market_id = ANY(%s) AND back_px IS NOT NULL ORDER BY market_id, ts",con,params=(mids,))
rows=[]
for mid,g in T.groupby('market_id',sort=False):
    sels=g.sel_id.unique()
    if len(sels)!=2: continue
    first=g[g.s<=600]
    if first.empty: continue
    sp={s:first[first.sel_id==s].bp.iloc[0] for s in sels if not first[first.sel_id==s].empty}
    if len(sp)<2: continue
    fav=min(sp,key=sp.get); p0=sp[fav]
    if not (1.30<=p0<=2.00): continue
    f=g[(g.sel_id==fav)].sort_values('ts'); last=g[g.ts==g.ts.max()]
    fin={r.sel_id:r.bp for r in last.itertuples()}; w=min(fin,key=fin.get); winner=w if fin[w]<=1.05 else None
    if winner is None: continue
    e=f[(f.s<=3600)&(f.bp>=1.6*p0)&(f.bp<=15)]
    if e.empty: continue
    r0=e.iloc[0]; px=r0.bp*(1-SP); won=(winner==fav)
    p_settle=(10*(px-1)*(1-CM)) if won else -10.0
    x=f[f.ts>=r0.ts+pd.Timedelta(minutes=20)]
    if x.empty: continue
    hx=x.iloc[0].lp*(1+SP); p_hedge=10*(px/hx-1); p_hedge=p_hedge*(1-CM) if p_hedge>0 else p_hedge
    rows.append(dict(event=g.event_name.iloc[0],comp=g.competition.iloc[0],ts=r0.ts,p0=p0,entry=r0.bp,drift=round(r0.bp/p0,2),mins=int(r0.s//60),won=won,p_settle=round(p_settle,2),p_hedge=round(p_hedge,2)))
R=pd.DataFrame(rows); print("T2 qualifying entries:",len(R))
import psycopg2.extras
cur=con.cursor(); cur.execute("CREATE TABLE IF NOT EXISTS t2_paper (event TEXT, comp TEXT, ts TIMESTAMPTZ, p0 NUMERIC, entry NUMERIC, drift NUMERIC, mins INT, won BOOLEAN, p_settle NUMERIC, p_hedge NUMERIC)"); cur.execute("DELETE FROM t2_paper")
if len(R): psycopg2.extras.execute_values(cur,"INSERT INTO t2_paper VALUES %s",[(r.event,r.comp,r.ts.to_pydatetime(),float(r.p0),float(r.entry),float(r.drift),int(r.mins),bool(r.won),float(r.p_settle),float(r.p_hedge)) for r in R.itertuples()]); con.commit()
if len(R):
    R['half']=np.where(R.ts<R.ts.median(),'H1','H2'); R['band']=pd.cut(R.drift,[1.6,2.0,2.5,3.5,10])
    for c in ('p_settle','p_hedge'):
        x=R[c]; print(f"{c}: mean per £10 {x.mean():+.2f} | win {(x>0).mean():.0%} | t {x.mean()/(x.std(ddof=1)/np.sqrt(len(x))):.2f} | H1 {R[R.half=='H1'][c].mean():+.2f} H2 {R[R.half=='H2'][c].mean():+.2f}")
    print("\nby drift band:\n",R.groupby('band',observed=True)[['p_settle','p_hedge']].agg(['size','mean']).round(2).to_string())
    print("\nfavourite still won after the drift:",f"{R.won.mean():.0%}","of",len(R),"| vendor claim implies ~45-50% needed at these prices")
    print("\nby competition (n>=5):\n",R.groupby('comp').p_settle.agg(['size','mean']).query('size>=5').round(2).to_string())
PYFILE
python3 -m py_compile /root/pe-factory/t2_nightly.py || exit 1
cd /root/pe-factory && timeout 1200 python3 t2_nightly.py 2>&1 | grep -v -E "UserWarning|pd.read_sql" | head -12
( crontab -l 2>/dev/null | grep -v t2_nightly ; echo "35 5 * * * cd /root/pe-factory && python3 t2_nightly.py >> t2.log 2>&1" ) | crontab -
python3 - <<'PY2'
p='/root/pe-push/digest.py'; s=open(p).read()
if 't2_paper' not in s:
    s=s.replace('mm=one("SELECT count(*) n, coalesce(sum(pnl_per_10),0) p FROM racing_mm_stream','t2=one("SELECT count(*) n, round(avg(p_settle),2) m, round(100*avg(CASE WHEN won THEN 1 ELSE 0 END)) w FROM t2_paper"); L.append(f"Tennis T2 (tape): {t2.get(\'n\')} entries, mean £{float(t2.get(\'m\') or 0):+.2f}/£10, fav won {t2.get(\'w\')}%")\nmm=one("SELECT count(*) n, coalesce(sum(pnl_per_10),0) p FROM racing_mm_stream',1)
    open(p,'w').write(s); print("digest line added")
PY2
python3 -m py_compile /root/pe-push/digest.py && echo "t2 nightly 05:35 installed"
