#!/bin/bash
# 149: ROBUSTNESS LAYER (AI Pathways Layer 3) on every paper/live book we hold. For each table *_paper (and pg trades) with a
# pnl_per_10 column and >= 30 settled rows, per rule/band: (1) BOOTSTRAP STRESS TEST — reshuffle the settled P&L sequence 1,000
# times, report 5th/50th/95th percentile total, worst-case drawdown across reshuffles, and the share of reshuffles that end positive;
# tag SOLID (5th pct > -1x mean stake and >=70% positive) / FRAGILE. (2) The same on strategy_results survivors is not possible yet
# (aggregates only) — Factory v4 stores per-trade returns so this runs on history too. -> robustness_results table + printed.
# Runs nightly 05:58 after the settlers so the Sunday table carries a solid/fragile flag per line.
mkdir -p /root/pe-factory && cat > /root/pe-factory/robustness.py <<'PYFILE'
import sys, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',250)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS robustness_results (run_date DATE, book TEXT, line TEXT, n INT, total NUMERIC, per_trade NUMERIC, p5 NUMERIC, p50 NUMERIC, p95 NUMERIC, worst_dd NUMERIC, pct_positive NUMERIC, flag TEXT)""")
cur.execute("DELETE FROM robustness_results WHERE run_date=current_date")
cur.execute("""SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND column_name='pnl_per_10' ORDER BY 1"""); tables=[r[0] for r in cur.fetchall()]
print("books with pnl_per_10:",tables)
rng=np.random.default_rng(24102026); out=[]
def boot(x,B=1000):
    x=np.asarray(x,float); tot=x.sum(); ends=[]; dds=[]
    for _ in range(B):
        s=rng.permutation(x); c=np.cumsum(s); dd=(np.maximum.accumulate(c)-c).max(); ends.append(c[-1]); dds.append(dd)
    ends=np.array(ends); dds=np.array(dds)
    # ends are identical under permutation (sum invariant) — the information is in the PATH: report drawdown distribution and
    # a block-bootstrap WITH replacement for the total (this is what varies the outcome)
    tot_b=np.array([rng.choice(x,size=len(x),replace=True).sum() for _ in range(B)])
    return dict(total=tot,p5=np.percentile(tot_b,5),p50=np.percentile(tot_b,50),p95=np.percentile(tot_b,95),worst_dd=dds.max(),med_dd=np.median(dds),pct_pos=(tot_b>0).mean())
for t in tables:
    cur.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name=%s",(t,)); cols={r[0] for r in cur.fetchall()}
    line_col=next((c for c in ('rule','band','strategy','side','first_side') if c in cols),None)
    q=f"SELECT {line_col+', ' if line_col else ''}pnl_per_10 FROM {t} WHERE pnl_per_10 IS NOT NULL" + (" AND band<>'junk'" if 'band' in cols else "")
    try: D=pd.read_sql(q,con)
    except Exception as e: print(t,"skip",repr(e)[:80]); continue
    if D.empty: continue
    groups=[('ALL',D.pnl_per_10.values)]
    if line_col: groups+=[(str(k),g.pnl_per_10.values) for k,g in D.groupby(line_col)]
    for line,x in groups:
        if len(x)<30: continue
        r=boot(x); per=r['total']/len(x)
        flag='SOLID' if (r['p5']>-10 and r['pct_pos']>=0.70) else ('FRAGILE' if r['total']>0 else 'NEGATIVE')
        out.append((datetime.date.today(),t,line,len(x),round(float(r['total']),2),round(float(per),3),round(float(r['p5']),2),round(float(r['p50']),2),round(float(r['p95']),2),round(float(r['worst_dd']),2),round(float(r['pct_pos']),3),flag))
if out:
    psycopg2.extras.execute_values(cur,"INSERT INTO robustness_results VALUES %s",out)
    R=pd.DataFrame(out,columns=['d','book','line','n','total','per_trade','p5','p50','p95','worst_dd','pct_pos','flag']).drop(columns='d')
    print("\n=== BOOTSTRAP (1,000 resamples) — per £10 stake, settled paper/live rows only ===\n",R.sort_values(['flag','total'],ascending=[True,False]).to_string(index=False))
    print("\nread: p5/p95 = 5th/95th percentile total if the same trades were drawn again; worst_dd = worst peak-to-trough across 1,000 orderings; SOLID = p5 > -£10 and >=70% of resamples positive")
else: print("no book has 30 settled rows yet")
PYFILE
python3 -m py_compile /root/pe-factory/robustness.py || exit 1
( crontab -l 2>/dev/null | grep -v robustness.py ; echo "58 5 * * * cd /root/pe-factory && python3 robustness.py >> robustness.log 2>&1" ) | crontab -
cd /root/pe-factory && timeout 900 python3 robustness.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
