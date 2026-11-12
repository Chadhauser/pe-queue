#!/bin/bash
# 557 (Thu 12 Nov 2026, 19:00). CEO orders 1-3 (checked against the reports to 16:17). Nothing else runs until a bet is live.
#  1. Stream recorder fixed (catalogue guard present + restart + proof), goal tables restored from the 554 dumps. No migrations/gates/clean-ups.
#  2. Post-goal fade UN-PAUSED (H0 in hypotheses.json back to proposed, daily). Its paper record since 9 Oct in one table
#     (m1_alerts paper + real, by month) and the Verdict by the standing gate, written to reports/fade_record.md.
#  3. The plain-English page of every rule allowed to bet: sample, £ per £100 after costs, bets/day, stake the liquidity supports,
#     expected £/day — reports/rules_page.md, read back into chat by me. If it is under £10/day it says so.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== 1a. stream recorder =="
grep -q bf_chunk /root/pe-stream/stream_client.py || { python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; L=open(p).read().split('\n'); k=next(i for i,l in enumerate(L) if l.startswith('import ') or l.startswith('from ')); L.insert(k,"import sys as _s557; _s557.path.insert(0,'/root/pe-liq'); import bf_chunk"); open(p,'w').write('\n'.join(L)); print("guard imported")
PY
}
python3 -m py_compile /root/pe-stream/stream_client.py && pkill -f stream_client.py; sleep 120
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("select count(*), count(distinct market_id) from stream_ticks where ts_recv>now()-interval '2 minutes'"); print("stream last 2 min: rows, markets =",c.fetchone())
c.execute("select last_seen, markets, conn_state from stream_heartbeat"); print("heartbeat:",c.fetchall())
PY
echo "stream.log 400s in last 200 lines: $(tail -200 /root/pe-stream/stream.log 2>/dev/null | grep -c ' 400 ')"; tail -2 /root/pe-liq/bf_chunk.log 2>/dev/null
echo "== 1b. restore goal tables from the dumps =="
DSN=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")
for t in goal_alerts goal_live_predictions goal_timeline m1_alerts real_trades af_fixtures af_events; do
  f=/root/pe-archive/tables/public.$t.sql.zst
  if [ -f "$f" ]; then
    if psql "$DSN" -At -c "select to_regclass('public.$t')" | grep -q "$t"; then echo "$t already present"; else zstdcat "$f" | psql -q "$DSN" >/dev/null 2>&1 && echo "restored $t: $(psql "$DSN" -At -c "select count(*) from $t") rows"; fi
  else echo "$t: no dump (was never dropped)"; fi
done
echo "== 2. post-goal fade un-paused + record =="
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H0'): h['status']='proposed'; h.pop('not_before',None); h['note']='un-paused 12 Nov (CEO order 2): the only verified edge'
json.dump(r,open(p,'w'),indent=1); print([(h['id'][:30],h['status']) for h in r['hypotheses']])
PY
python3 - <<'PY' | tee /root/pe-queue/reports/fade_record.md
import sys,math,json,psycopg2,datetime; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
def q(sql,args=()):
    try: c.execute(sql,args); return c.fetchall()
    except Exception as e: con.rollback(); return [('ERR',str(e)[:100])]
def t(x): import statistics; x=[float(v) for v in x if v is not None]; return (statistics.mean(x)/(statistics.stdev(x)/math.sqrt(len(x)))) if len(x)>5 and statistics.stdev(x)>0 else 0.0
print(f"# Post-goal fade — paper and real record since 9 Oct 2026 ({datetime.date.today()}, job 557)\n")
cols=[r[0] for r in q("select column_name from information_schema.columns where table_name='m1_alerts'")]
print("m1_alerts columns:",cols,"\n")
tscol=next((k for k in ('sent_at','ts','created_at','alert_ts') if k in cols),None); pp='pnl_paper' if 'pnl_paper' in cols else None; ap='actual_pnl' if 'actual_pnl' in cols else None
if tscol and (pp or ap):
    print("| month | alerts | paper settled | paper £ | real trades | real £ |\n|---|---|---|---|---|---|")
    for m,n,ps,ppnl,rn,rpnl in q(f"select to_char(date_trunc('month',{tscol}),'YYYY-MM'), count(*), count({pp}), round(coalesce(sum({pp}),0)::numeric,2), count({ap}), round(coalesce(sum({ap}),0)::numeric,2) from m1_alerts where {tscol}>='2026-10-09' group by 1 order by 1"):
        print(f"| {m} | {n} | {ps} | {ppnl:+.2f} | {rn} | {rpnl:+.2f} |")
    x=[r[0] for r in q(f"select {pp} from m1_alerts where {tscol}>='2026-10-09' and {pp} is not null order by {tscol}")]
    if x:
        h=len(x)//2; a,b=x[:h],x[h:]; mean=sum(x)/len(x); tt=t(x); both=sum(a)>0 and sum(b)>0
        print(f"\nPaper since 9 Oct: n {len(x)}, total {sum(x):+.2f}, mean per bet {mean:+.3f}, t {tt:.2f}, first half {sum(a):+.2f}, second half {sum(b):+.2f}")
        v="WORKS — live at £2 with the kill switch" if (len(x)>=300 and tt>=3.5 and both) else ("WORKS AT £2 — live at £2 with the kill switch (−£50 total stops it)" if (len(x)>=100 and tt>=2.0 and both) else f"NOT YET — n {len(x)}, t {tt:.2f}, halves {sum(a):+.2f}/{sum(b):+.2f}; next read Mon 17 Nov after the weekend's goals")
        print("\n**VERDICT:",v+"**")
    else: print("\n**VERDICT: NOT YET — no settled paper rows in m1_alerts since 9 Oct; the H0 forward paper (fade_forward.py, daily from tonight) is the record from here; next read Mon 17 Nov**")
else: print("m1_alerts has no usable columns; VERDICT: NOT YET — see H0 RESULT lines on the scoreboard from tonight")
print("\n## H0 forward-paper lines on the scoreboard (real ladder, 2% commission, one tick adverse)\n")
try:
    sb=json.load(open('/root/pe-sports/team/scoreboard.json'))
    for v in sb.get('verdicts',[]):
        if str(v.get('name','')).startswith('H0'): print(f"- {v['name']}: n {v.get('n')}, £/£10 {v.get('mean_per10')}, t {v.get('t')}, IS t {v.get('is_t')}, OOS t {v.get('oos_t')} — {v.get('verdict')}")
except Exception as e: print("scoreboard unreadable:",e)
PY
echo "== 3. the rules page =="
python3 - <<'PY' | tee /root/pe-queue/reports/rules_page.md
import sys,psycopg2,datetime; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
def q(sql,args=()):
    try: c.execute(sql,args); return c.fetchall()
    except Exception as e: con.rollback(); return []
print(f"# Every rule allowed to bet — {datetime.date.today()} (job 557). All paper. Costs: 2% commission, one tick adverse.\n")
days=max(1,(datetime.datetime.utcnow()-datetime.datetime(2026,11,10,13,40)).total_seconds()/86400)
print(f"## Bot v2 TAKER — passed fair-price cells, taken in the last 2 min before the off (running since 10 Nov 13:40, {days:.1f} days)\n")
print("| sport | market | price band | side | history n | edge | bets so far | bets/day | settled | £ per £100 (paper) | stake liquidity supports |\n|---|---|---|---|---|---|---|---|---|---|---|")
tot_day=0.0; rows=q("select p.sport,p.market_type,p.band_lo,p.band_hi,p.side,p.n_is+p.n_oos,p.edge_is from fair_price_passed p order by 1,2,3")
for sp,mt,lo,hi,side,n,edge in rows:
    b=q("select count(*), count(*) filter (where status='settled'), coalesce(sum(pnl) filter (where status='settled'),0), coalesce(sum(stake) filter (where status='settled'),0) from bookie_paper where version='v2' and fill_kind='taker' and mkt=%s and side=%s",(mt,side))
    nb,st,pnl,stk=b[0] if b else (0,0,0,0); per100=(float(pnl)/float(stk)*100) if stk else None
    exp_per100=float(edge)*100 if side=='BACK' else abs(float(edge))*100   # backtest edge in points of probability ~ £ per £100 at evens; stated as the history figure
    perday=nb/days; tot_day+=perday*2*(per100 if per100 is not None else exp_per100)/100
    print(f"| {sp} | {mt} | {float(lo):.2f}-{float(hi):.2f} | {side} | {n} | {float(edge):+.3f} | {nb} | {perday:.1f} | {st} | {'n/a yet' if per100 is None else f'{per100:+.1f}'} (history {exp_per100:+.1f}) | ≥£10 available both sides is the bot's floor; typical pre-off football books carry £50-£500 at the touch |")
nb_all=q("select count(*), count(*) filter (where status='settled'), coalesce(sum(pnl) filter (where status='settled'),0) from bookie_paper where version='v2' and fill_kind='taker'")[0]
print(f"\nTotal taker bets {nb_all[0]} ({nb_all[0]/days:.1f}/day), settled {nb_all[1]}, paper £{float(nb_all[2]):+.2f}.")
print(f"\n**Expected at £2 a bet, using the history edge where no paper has settled: about £{tot_day:+.2f} per day.** {'That is under £10 a day.' if tot_day<10 else ''} At £20 a bet it is 10x that, if the books take it — the ≥£10 floor says they take £2; £20 needs the liquidity column read live, which is the next measurement.")
print("\n## Desk (calls for a human, £2 a click, your money only if you click)\n")
print("| line | rule | history | calls so far | settled | £ |\n|---|---|---|---|---|---|")
d={r[0]:r for r in q("select line, count(*), count(*) filter (where status in ('settled','closed')), coalesce(sum(pnl) filter (where status in ('settled','closed')),0) from desk_calls group by 1")}
for line,rule,hist in [('FADE','lay the scorer at +2 min after a goal (price ≤6), back out at +10 min','your verified result; H0 forward paper daily'),('HT11','1-1 at half-time → back Over 2.5, hold','coach tape n 79, +£1.78/£10, second half −0.13 — thin'),('CELL','in-play fair-price cell at this minute → take price, hold','H1b map, desk bar n≥100 both halves positive')]:
    r=d.get(line,(line,0,0,0)); print(f"| {line} | {rule} | {hist} | {r[1]} | {r[2]} | {float(r[3]):+.2f} |")
print(f"\nDesk in-play cells available: {q('select count(*) from fair_price_passed_inplay')[0][0] if q('select count(*) from fair_price_passed_inplay') else 0}.")
print("\n## Not allowed to bet\n- Maker (resting) quoting: off — the 8-day pre-off football replay showed ~7% per fill against a random maker (control). CEO order 4 re-runs the replay in-play after goals and on Matchbook/Smarkets before this is dropped.\n- Everything paused by the 9 Nov inventory.")
PY
cd /root/pe-queue && git add reports/fade_record.md reports/rules_page.md && git commit -q -m "557: fade record + rules page" && git pull -q --rebase && git push -q && echo pushed
echo "557 done"
