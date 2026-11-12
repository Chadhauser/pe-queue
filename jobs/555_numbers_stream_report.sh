#!/bin/bash
# 555 (Thu 12 Nov 2026, 17:15). Disk is back (23.9 GB free, loader running again). Two things left from today:
#  1. The numbers Peter is owed, printed here and written to reports/numbers_2026-11-12.md: passed cells by sport, taker bets by cell and
#     status, desk calls, history-loader months — all read from the tables, nothing from memory.
#  2. The stream recorder's catalogue 400s: confirm bf_chunk is imported (553 step 4) and, if the import is missing, add it; restart.
#  Also: jobs 549-555 added to the Watchman's REPORT_JOBS so their outputs appear in the hourly report (553/554 did not).
# Decisions on the Watchman's questions, recorded: the 17 dropped tables stay dropped (ARCHIVE class; dumps kept; the Finder is paused);
# 554 step 3 is NOT re-run (disk is fine); the player recorder is not needed for the bot (stays down).
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== stream catalogue guard =="
grep -n "bf_chunk" /root/pe-stream/stream_client.py | head -2 || true
if ! grep -q bf_chunk /root/pe-stream/stream_client.py; then
python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; lines=open(p).read().split('\n'); k=next(i for i,l in enumerate(lines) if l.startswith('import ') or l.startswith('from '))
lines.insert(k,"import sys as _s555; _s555.path.insert(0,'/root/pe-liq'); import bf_chunk  # 555: listMarketCatalogue TOO_MUCH_DATA -> bisect"); open(p,'w').write('\n'.join(lines)); print("bf_chunk imported")
PY
python3 -m py_compile /root/pe-stream/stream_client.py && pkill -f stream_client.py && echo "stream restarted"
fi
sleep 60; grep -c " 400 " /root/pe-stream/stream.log 2>/dev/null | head -1; tail -3 /root/pe-liq/bf_chunk.log 2>/dev/null
echo "== the numbers =="
python3 - <<'PY' | tee /root/pe-queue/reports/numbers_2026-11-12.md
import sys,psycopg2,datetime; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
print(f"# Numbers — {datetime.datetime.utcnow():%Y-%m-%d %H:%M} UTC (job 555, read from the tables)\n")
def q(sql):
    try: c.execute(sql); return c.fetchall()
    except Exception as e: c.connection.rollback(); return [('ERR',str(e)[:80])]
print("## Fair-price map\n"); print("| sport | map cells | passed cells (bot) |\n|---|---|---|")
m={s:n for s,n in q("select sport, count(*) from fair_price_calib group by 1")}; p={s:n for s,n in q("select sport, count(*) from fair_price_passed group by 1")}
for s in sorted(set(m)|set(p)): print(f"| {s} | {m.get(s,0)} | {p.get(s,0)} |")
print("\nDesk in-play cells:",q("select count(*) from fair_price_passed_inplay")[0][0])
print("\n## Bot v2 TAKER (paper, £2, passed cells, last 2 min pre-off)\n"); print("| market | side | bets | settled | won | £ | £ per £100 |\n|---|---|---|---|---|---|---|")
for mkt,side,n,st,w,pnl,stk in q("select mkt, side, count(*), count(*) filter (where status='settled'), coalesce(sum(won) filter (where status='settled'),0), round(coalesce(sum(pnl) filter (where status='settled'),0)::numeric,2), coalesce(sum(stake) filter (where status='settled'),0) from bookie_paper where version='v2' and fill_kind='taker' group by 1,2 order by 3 desc"):
    print(f"| {mkt} | {side} | {n} | {st} | {w} | {pnl:+.2f} | {('%+.2f' % (float(pnl)/float(stk)*100)) if stk else 'n/a'} |")
print("\nTaker by status:",q("select status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper where version='v2' and fill_kind='taker' group by 1"))
print("Maker v2 (9-10 Nov, off):",q("select status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper where version='v2' and coalesce(fill_kind,'maker')<>'taker' group by 1"))
print("\n## Desk\n",q("select line, status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from desk_calls group by 1,2 order by 1,2"))
print("\n## History loader\n",q("select status, count(*) from bf_hist_months group by 1"),"| files 24h:",q("select count(*) from bf_hist_other_files where loaded_at>now()-interval '24 hours'")[0][0])
print("\n## Disk/DB\n",q("select round(pg_database_size(current_database())/1e9,1)")[0][0],"GB database")
PY
for j in 549 550 551 552 553 554 555; do grep -q "^$j$" /root/pe-queue/watchman/REPORT_JOBS.txt || echo $j >> /root/pe-queue/watchman/REPORT_JOBS.txt; done
cd /root/pe-queue && git add reports/numbers_2026-11-12.md watchman/REPORT_JOBS.txt && git commit -q -m "555: numbers 12 Nov" && git pull -q --rebase && git push -q && echo pushed
echo "555 done"
