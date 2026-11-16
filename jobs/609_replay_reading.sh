#!/bin/bash
# 609 (Mon 16 Nov 2026, 15:30). Peter: use the data we hold to test the fair-price cells now, not only the forward paper. Plan: replay the
# bot's exact rule (passed cells, take the price in the last 2 min before the off, >= £10 both sides) on the tape recorded since mid-Oct,
# which is after the history the cells were derived from, so it is out-of-sample at real prices. This job READS what the replay needs:
# the bot's decision and settlement code, the tape tables' columns, date ranges and market types, and the results source for tape markets.
set -o pipefail
R=/root/pe-queue/reports/replay_reading.md
{ echo "# Replay reading $(date -u '+%F %H:%M') UTC (job 609)"; echo
echo "## bot decision + settlement (bookie_v2.py)"; echo '```'
grep -n "def \|liq_sample\|stream_ticks\|listMarketBook\|listMarketCatalogue\|MIN_SIZE\|MIN_MATCHED\|seconds\|120\|fair_price_passed\|band_lo\|status='settled'\|settle\|won\|pnl\|commission\|0.02\|EX_BEST\|availableToBack\|availableToLay" /root/pe-sports/bookie/bookie_v2.py | cut -c1-200 | head -90
echo '```'
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='600s'")
def q(s):
    try: c.execute(s); return c.fetchall()
    except Exception as e: c.connection.rollback(); return [("ERR",str(e)[:150])]
for t in ('liq_sample','stream_ticks','bookie_paper','fair_price_passed','bf_hist_result','market_results','bf_results','mkt_results'):
    print(f"## {t} columns:", [r[0] for r in q(f"select column_name from information_schema.columns where table_name='{t}' order by ordinal_position")])
print("## liq_sample range + market types:", q("select min(ts)::date, max(ts)::date from liq_sample"), q("select mkt, count(distinct market_id) from liq_sample where ts>now()-interval '30 days' group by 1 order by 2 desc limit 25"))
print("## stream_ticks range + sports:", q("select min(ts_recv)::date, max(ts_recv)::date from stream_ticks"), q("select sport, count(distinct market_id) from stream_ticks where ts_recv>now()-interval '30 days' group by 1 order by 2 desc"))
print("## sample liq_sample row:", q("select * from liq_sample order by ts desc limit 1"))
print("## sample stream_ticks row:", q("select * from stream_ticks order by ts_recv desc limit 1"))
print("## passed cells:", q("select sport, market_type, band_lo, band_hi, side from fair_price_passed order by 1,2"))
print("## bookie_paper settled sample:", q("select market_id, mkt, side, price, stake, status, won, pnl, start_ts, settled_ts from bookie_paper where status='settled' order by settled_ts desc limit 3"))
print("## tables with 'result' in the name:", q("select table_name from information_schema.tables where table_schema='public' and table_name ilike '%result%'"))
PY
echo; echo "## archive files by table (tape held off the database)"; for d in /root/pe-archive/*/; do echo "$d $(ls $d | wc -l) files $(ls $d | head -1) .. $(ls $d | tail -1)"; done
} > $R 2>&1
cd /root/pe-queue && git add reports/replay_reading.md && git commit -qm "609: replay reading" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "609 done"
