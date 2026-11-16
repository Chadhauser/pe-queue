#!/bin/bash
# 616 (Mon 16 Nov 2026, 16:20). Peter: don't just take the calculations, check them. Waits until 612 and 613 have reported, then:
#  A. Replay engine vs reality: every live paper bet the bot actually placed since 2 Nov is looked up on the recorded ladder at the moment
#     it filled. Does the tape show the price the bot got (within 1 tick)? Does the cached Betfair result agree with how the bot settled it?
#     If the replay's prices or results disagree with what really happened, the replay figures are not to be trusted.
#  B. Twelve worked examples from the history test, with match, runner, kick-off, price 2 min before, result and profit, so any of them can
#     be checked by hand against a results site.
#  C. The settlement maths re-done independently in SQL for the live bets (stake, price, result, 2% commission) against the bot's own pnl.
[ -f /root/pe-queue/reports/cells_tradable.md ] && [ -f /root/pe-queue/reports/execution_methods.md ] || { echo "waiting for 612 and 613"; exit 75; }
set -o pipefail
R=/root/pe-queue/reports/verification.md
python3 - > $R 2>&1 <<'PY'
import sys, psycopg2, datetime
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='1800s'")
print(f"# Verification of the replay and history tests — {datetime.datetime.utcnow():%F %H:%M} UTC\n")
print("## A. Replay engine against the bot's real paper bets (same market, same runner, same moment)\n")
c.execute("""SELECT b.id, b.event_name, b.mkt, b.sel, b.side, b.fill_price::float, b.fill_ts, b.won, b.pnl::float, b.market_id,
   (SELECT CASE WHEN b.side='BACK' THEN t.back_px ELSE t.lay_px END FROM stream_ticks t WHERE t.market_id=b.market_id AND t.sel=b.sel
      AND t.ts_recv BETWEEN b.fill_ts - interval '60 seconds' AND b.fill_ts + interval '60 seconds' ORDER BY abs(extract(epoch from t.ts_recv-b.fill_ts)) LIMIT 1)::float tape_px
   FROM bookie_paper b WHERE b.version='v2' AND b.fill_kind='taker' AND b.status='settled' AND b.fill_ts>'2026-11-11' ORDER BY b.fill_ts""")
rows=c.fetchall(); seen=[r for r in rows if r[10] is not None]
def ticks_apart(a,b):
    L=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
    def t(p):
        for hi,s in L:
            if p<hi: return s
        return 10
    lo,hi=min(a,b),max(a,b); n=0
    while lo<hi-1e-9 and n<60: lo=round(lo+t(lo),2); n+=1
    return n
ok=sum(1 for r in seen if ticks_apart(r[5],r[10])<=1)
print(f"Bot paper bets since 11 Nov (table tape): {len(rows)}; found on the tape: {len(seen)}; tape price within 1 tick of the bot's fill: {ok} of {len(seen)}.\n")
print("| match | market | runner | side | bot price | tape price |\n|---|---|---|---|---|---|")
for r in seen[:15]: print(f"| {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[10]} |")
c.execute("""SELECT count(*), count(*) FILTER (WHERE (b.won=1)=(r.status='WINNER')) FROM bookie_paper b JOIN stream_ticks t ON t.market_id=b.market_id AND t.sel=b.sel
             JOIN tape_results r ON r.market_id=b.market_id AND r.sel_id=t.sel_id::text WHERE b.version='v2' AND b.status='settled' AND b.fill_ts>'2026-11-11'
             AND t.ts_recv BETWEEN b.fill_ts - interval '60 seconds' AND b.fill_ts + interval '60 seconds'""")
n,agree=c.fetchone(); print(f"\nResult agreement (bot's settlement vs the replay's cached Betfair result), tick-level rows: {agree} of {n}.\n")
print("## C. Settlement maths re-done independently\n")
c.execute("""SELECT count(*), sum(abs(b.pnl - CASE WHEN b.side='BACK' THEN (CASE WHEN b.won=1 THEN (b.fill_price-1)*b.stake*0.98 ELSE -b.stake END)
                                         ELSE (CASE WHEN b.won=1 THEN -(b.fill_price-1)*b.stake ELSE b.stake*0.98 END) END)) FROM bookie_paper b
             WHERE b.version='v2' AND b.fill_kind='taker' AND b.status='settled'""")
n,diff=c.fetchone(); print(f"{n} settled bets; total difference between the bot's pnl and an independent recalculation: £{float(diff or 0):.2f}\n")
print("## B. Twelve worked examples from the history test (check any against a results site)\n")
print("| kick-off | match | market | runner | cell | price 2 min before | result | profit at £2 |\n|---|---|---|---|---|---|---|---|")
c.execute("SELECT sport, market_type, band_lo::float, band_hi::float, side FROM fair_price_passed WHERE sport='Soccer' ORDER BY random() LIMIT 12")
for sp,mt,a,b,side in c.fetchall():
    c.execute("""WITH p AS (SELECT DISTINCT ON (o.market_id,o.sel) o.market_id,o.sel,o.event_name,o.market_time,o.ltp FROM bf_hist_other o
                 WHERE o.sport=%s AND o.market_type=%s AND NOT o.inplay AND o.ts<=o.market_time-interval '120 seconds' AND o.market_time between '2025-12-01' and '2026-09-30'
                 AND o.market_id IN (SELECT market_id FROM bf_hist_result WHERE sport=%s AND market_type=%s ORDER BY random() LIMIT 400)
                 ORDER BY o.market_id,o.sel,o.ts DESC)
                 SELECT p.market_time, p.event_name, p.sel, p.ltp::float, r.status FROM p JOIN bf_hist_result r ON r.market_id=p.market_id AND r.sel=p.sel
                 WHERE 1/p.ltp >= %s AND 1/p.ltp < %s AND r.status IN ('WINNER','LOSER') LIMIT 1""",(sp,mt,sp,mt,a,b))
    x=c.fetchone()
    if not x: continue
    kt,ev,sel,ltp,st=x; won=st=='WINNER'
    g=((ltp-1)*2 if won else -2) if side=='BACK' else (-(ltp-1)*2 if won else 2); g=g*0.98 if g>0 else g
    print(f"| {kt:%d %b %Y %H:%M} | {ev} | {mt} | {sel} | {side} {a:.2f}-{b:.2f} | {ltp} | {st} | £{g:+.2f} |")
PY
cd /root/pe-queue && git add reports/verification.md && git commit -qm "616: verification of replay and history tests" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "616 done"
