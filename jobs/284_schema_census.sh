#!/bin/bash
# 284: SCHEMA CENSUS for the dropped-items queue — columns, row counts, date ranges and sport/league coverage of every table and
# file the Thu/Fri/weekend jobs need (pre-match fair price, fan bias, Benter racing model, draw bias, basketball/golf/darts
# sweeps, CS cells), so those jobs are written against real columns.
set -e
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1"); tabs=[r[0] for r in k.fetchall()]; print("tables:",len(tabs)); print(tabs)
def cols(t): k.execute("SELECT string_agg(column_name||':'||data_type,', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name=%s",(t,)); return k.fetchone()[0]
for t in tabs:
    if any(x in t for x in ['ip_tape','ip_stats','golf','racing_bsp','racing_tape','bf_hist','understat','elo','fixtures','results','cs_','pg_','espn_stats','xx_tape','v4_','tennis','cricket','basket','dart','opp_map','liq_sample','stream_ticks','factory']):
        try:
            k.execute(f"SELECT count(*) FROM {t}"); n=k.fetchone()[0]; print(f"\n## {t} rows={n}\n   {cols(t)}")
            k.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s AND (data_type LIKE 'timestamp%%' OR data_type='date') ORDER BY ordinal_position LIMIT 1",(t,)); c=k.fetchone()
            if c and n: k.execute(f"SELECT min({c[0]}), max({c[0]}) FROM {t}"); print("   range:",k.fetchone())
            for sc in ('sport','league','competition','event_type','market_type','mkt'):
                k.execute("SELECT 1 FROM information_schema.columns WHERE table_name=%s AND column_name=%s",(t,sc))
                if k.fetchone() and n: k.execute(f"SELECT {sc}, count(*) FROM {t} GROUP BY 1 ORDER BY 2 DESC LIMIT 12"); print(f"   by {sc}:",k.fetchall())
        except Exception as e: print(t,"ERR",str(e)[:100]); k.connection.rollback()
PY
echo "== files"; ls -la /root/pe-data 2>/dev/null | head -30; ls /root/pe-*/*.csv /root/pe-*/*.parquet 2>/dev/null | head -40; du -sh /root/pe-* 2>/dev/null | sort -h | tail -12
for f in $(ls /root/pe-*/*.csv 2>/dev/null | head -12); do echo "-- $f"; head -2 "$f" | cut -c1-300; done
