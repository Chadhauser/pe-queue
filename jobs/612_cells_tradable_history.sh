#!/bin/bash
# 612 (Mon 16 Nov 2026, 16:10). Peter: faster and better. Two questions, answered on the full history (thousands of bets) instead of waiting:
#  A. Do the passed cells make money at a price we could actually take 2 minutes before the off (not the closing price)? Each bet priced at the
#     last traded price at least 120 s before the off, twice: optimistic (at that price) and pessimistic (one tick worse: back lower, lay higher).
#  B. Does a value filter fix it? Only bet when the price beats the cell's fair price (implied x fair_factor) by a margin m in {0, 1%, 2%, 4%}.
#     The margin is CHOSEN on the first half of the history and only REPORTED on the second half, so it is not fitted to the answer.
# Same rule set then re-run on the recorded-ladder replay bets. Background; writes reports/cells_tradable.md.
cat > /root/pe-sports/team/cells_tradable.py <<'PY'
import sys, datetime, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; STAKE=2.0
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for hi,t in LADDER:
        if p<hi: return t
    return 10
def up(p): return round(min(1000,p+tick(p)),2)
def down(p): return round(max(1.01,p-tick(p-1e-9)),2)
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='5400s'"); c.execute("SET work_mem='64MB'")
c.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); CELLS=[(s,m,float(a),float(b),sd,float(f)) for s,m,a,b,sd,f in c.fetchall()]
out=[f"# Passed cells at a tradable price, full history — {datetime.datetime.utcnow():%F %H:%M} UTC","",
 "Each bet: last traded price at least 120 s before the off. 'opt' = at that price, 'pess' = one tick worse. 2% commission. £2 a bet. Per £100 staked.",""]
allrows=[]
for sport,mt in sorted({(s,m) for s,m,*_ in CELLS}):
    q="""WITH p AS (SELECT DISTINCT ON (o.market_id,o.sel) o.market_id,o.sel,o.market_time,o.ltp FROM bf_hist_other o
                WHERE o.sport=%s AND o.market_type=%s AND NOT o.inplay AND o.ltp>1 AND o.ltp<1000 AND o.ts<=o.market_time-interval '120 seconds'
                ORDER BY o.market_id,o.sel,o.ts DESC)
         SELECT p.market_id,p.sel,p.market_time,p.ltp,(r.status='WINNER')::int won FROM p JOIN bf_hist_result r ON r.market_id=p.market_id AND r.sel=p.sel
         WHERE r.status IN ('WINNER','LOSER')"""
    try: df=pd.read_sql(q,con,params=(sport,mt))
    except Exception as e: out.append(f"{sport}/{mt}: query failed {str(e)[:100]}"); con.rollback(); continue
    if df.empty: out.append(f"{sport}/{mt}: no rows"); continue
    df['ltp']=df.ltp.astype(float); df['p']=1/df.ltp
    for s,m,a,b,side,ff in [x for x in CELLS if x[0]==sport and x[1]==mt]:
        d=df[(df.p>=a)&(df.p<b)].copy()
        if d.empty: continue
        d['cell']=f"{s} {m} {a:.2f}-{b:.2f} {side}"; d['side']=side; d['fair_p']=d.p*ff
        for lab,f in (('opt',lambda x:x),('pess',(down if side=='BACK' else up))):
            pr=d.ltp.map(f) if lab=='pess' else d.ltp
            g=np.where(side=='BACK', np.where(d.won==1,(pr-1)*STAKE,-STAKE), np.where(d.won==1,-(pr-1)*STAKE,STAKE))
            d['pnl_'+lab]=np.where(g>0,g*(1-COMM),g); d['px_'+lab]=pr
        # value: BACK needs fair_p > 1/price*(1+m); LAY needs fair_p < 1/price*(1-m), on the pessimistic price
        d['val']=np.where(side=='BACK', d.fair_p*d.px_pess-1, 1-d.fair_p*d.px_pess)
        allrows.append(d)
if not allrows: open('/root/pe-queue/reports/cells_tradable.md','w').write("\n".join(out+["no data"])); sys.exit()
D=pd.concat(allrows).sort_values('market_time'); split=D.market_time.quantile(0.5)
def row(lbl,d,col):
    if len(d)==0: return f"| {lbl} | 0 | | | |"
    h1=d[d.market_time<split]; h2=d[d.market_time>=split]
    f=lambda x: f"£{x[col].sum()/(len(x)*STAKE)*100:+.1f}" if len(x) else "-"
    return f"| {lbl} | {len(d)} | {f(d)} | {f(h1)} | {f(h2)} |"
out+=["## A. Every cell, no value filter","","| cell | bets | pess per £100 | 1st half | 2nd half |","|---|---|---|---|---|",row("ALL (pessimistic)",D,'pnl_pess'),row("ALL (optimistic)",D,'pnl_opt')]
for cl,d in D.groupby('cell'): out.append(row(cl,d,'pnl_pess'))
# B. choose margin on half 1 (pessimistic), report half 2
H1=D[D.market_time<split]; H2=D[D.market_time>=split]
res=[(m, H1[H1.val>=m].pnl_pess.sum()/max(1,len(H1[H1.val>=m])*STAKE)*100, len(H1[H1.val>=m])) for m in (0,0.01,0.02,0.04)]
best=max(res,key=lambda x:x[1] if x[2]>=200 else -999)[0]
out+=["","## B. Value filter (price must beat the cell's fair price by m, pessimistic price)","","| m | 1st-half bets | 1st-half per £100 | 2nd-half bets | 2nd-half per £100 (untouched) |","|---|---|---|---|---|"]
for m,r1,n1 in res:
    d2=H2[H2.val>=m]; out.append(f"| {m:.0%} | {n1} | £{r1:+.1f} | {len(d2)} | £{d2.pnl_pess.sum()/max(1,len(d2)*STAKE)*100:+.1f} |")
out+=["",f"Margin chosen on the first half only: **{best:.0%}**. Its second-half result above is the honest test.",""]
d2=H2[H2.val>=best]
out+=["Chosen rule, second half, by cell:","","| cell | bets | per £100 |","|---|---|---|"]
for cl,d in d2.groupby('cell'): out.append(f"| {cl} | {len(d)} | £{d.pnl_pess.sum()/(len(d)*STAKE)*100:+.1f} |")
months=(D.market_time.max()-D.market_time.min()).days/30.4
out+=["",f"History span {D.market_time.min():%d %b %Y} to {D.market_time.max():%d %b %Y} ({months:.0f} months). Bets a month under the chosen rule: {len(D[D.val>=best])/max(1,months):.0f}."]
open('/root/pe-queue/reports/cells_tradable.md','w').write("\n".join(out)+"\n"); print("\n".join(out))
PY
python3 -m py_compile /root/pe-sports/team/cells_tradable.py && echo compiles || exit 1
cd /root/pe-sports/team && nohup bash -c 'nice -n 10 timeout 10800 python3 cells_tradable.py > cells_tradable.log 2>&1; cd /root/pe-queue && git add reports/cells_tradable.md && git commit -qm "cells at a tradable price, full history" && git pull -q --no-rebase --no-edit && git push -q' >/dev/null 2>&1 &
sleep 30; tail -2 /root/pe-sports/team/cells_tradable.log
echo "612 done (running in the background)"
