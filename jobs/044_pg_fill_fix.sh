#!/bin/bash
# 044: fills. Mon 12 Oct: 6 entry attempts, 1 matched, 5 unmatched. 60s after a goal the best lay moves between our read and our
# order. Fix: first attempt at best lay; each retry inside the window concedes one tick (lay one price lower), max 3 ticks.
# Also: liquidity report split by whitelist leagues vs the rest.
python3 - <<'PY'
p='/root/pe-pg/pg_bot.py'; s=open(p).read()
s=s.replace("pending[k]={'due':g['goal_ts']+datetime.timedelta(seconds=60),'g':g,'selkey':selkey,'goals':goals}",
            "pending[k]={'due':g['goal_ts']+datetime.timedelta(seconds=60),'g':g,'selkey':selkey,'goals':goals,'tries':0}")
s=s.replace("            res=place(g['market_id'],sel_id,'LAY',float(c['stake']),lp,bool(c['dry_run']))",
"""            # Betfair tick ladder: concede one tick per retry (lay at a lower price = fills against the backers queue)
            def tick_down(px,n):
                for _ in range(n):
                    step=0.01 if px<=2 else 0.02 if px<=3 else 0.05 if px<=4 else 0.1 if px<=6 else 0.2 if px<=10 else 0.5
                    px=round(px-step,2)
                return px
            lp_use=tick_down(lp,min(p.get('tries',0),3)); p['tries']=p.get('tries',0)+1
            if p['tries']>1: print("retry",p['tries'],"at",lp_use,"(best lay",lp,")",flush=True)
            res=place(g['market_id'],sel_id,'LAY',float(c['stake']),lp_use,bool(c['dry_run']))""")
s=s.replace("cur.execute(\"UPDATE pg_trades SET status='OPEN', entry_matched=%s, entry_size=%s, entry_bet_id=%s, exit_due=now()+interval '10 minutes' WHERE id=%s\",(res.get('averagePriceMatched') or lp,matched,res.get('betId'),row_id))",
            "cur.execute(\"UPDATE pg_trades SET status='OPEN', entry_matched=%s, entry_size=%s, entry_bet_id=%s, exit_due=now()+interval '10 minutes' WHERE id=%s\",(res.get('averagePriceMatched') or lp_use,matched,res.get('betId'),row_id))")
open(p,'w').write(s)
r='/root/pe-report/pg_report.py'; t=open(r).read()
t=t.replace("""A("  £ available to LAY 60s after a goal, last 7 days (median best / within 3 ticks):")
for r in d: A(f"    {r['mkt']:5} {r['band']:8} n={r['n']:4}  £{r['med_lay_best']} / £{r['med_lay3']}")""",
"""A("  £ available to LAY 60s after a goal, last 7 days (median best / within 3 ticks) — ALL leagues:")
for r in d: A(f"    {r['mkt']:5} {r['band']:8} n={r['n']:4}  £{r['med_lay_best']} / £{r['med_lay3']}")
try:
    sys.path.insert(0,'/root/pe-prematch'); from fts_collector import LEAGUES as WL
    d2=q(\"\"\"SELECT mkt, CASE WHEN ltp<1.5 THEN '<1.5' WHEN ltp<2.5 THEN '1.5-2.5' WHEN ltp<5 THEN '2.5-5' ELSE '5+' END band, count(*) n,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY lay_sz)::numeric) med_lay_best, round(percentile_cont(0.5) WITHIN GROUP (ORDER BY lay3_sz)::numeric) med_lay3
       FROM liq_goal_depth WHERE offset_s=60 AND goal_ts > now()-interval '7 days' AND competition = ANY(%s) GROUP BY 1,2 ORDER BY 1,2\"\"\",(list(WL),))
    A("  same, WHITELIST leagues only (the ones the bot trades):")
    for r in d2: A(f"    {r['mkt']:5} {r['band']:8} n={r['n']:4}  £{r['med_lay_best']} / £{r['med_lay3']}")
except Exception as e: A("  whitelist split unavailable: "+repr(e)[:80])""")
open(r,'w').write(t)
PY
python3 -m py_compile /root/pe-pg/pg_bot.py && python3 -m py_compile /root/pe-report/pg_report.py || exit 1
pkill -f pg_bot.py; sleep 70; pgrep -af pg_bot.py || echo NOT RUNNING; tail -3 /root/pe-pg/bot.log
cd /root/pe-report && python3 pg_report.py 2>/dev/null | sed -n '/LIQUIDITY/,/TENNIS/p'
