#!/bin/bash
set -o pipefail
# 467 (Finder 2026-11-03, item 0f): census first — does bf_hist_price hold AH / DNB / FH05 / FH15 for the 12,255 mapped games?
# Item 8 (jobs/457) reported bf_hist_price has NO AH/DNB; FH05/FH15 were tested in item 14 (jobs/462). This job re-checks the census
# directly so 0f is decided on evidence, and lists any other table that could carry two-season AH/DNB history.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
cur.execute("SELECT mkt, count(DISTINCT sel), count(DISTINCT event_id), count(*), min(minute), max(minute) FROM bf_hist_price GROUP BY 1 ORDER BY 1")
print("== bf_hist_price by mkt: mkt | distinct sel | events | rows | min minute | max minute")
for r in cur.fetchall(): print(" ",r)
cur.execute("SELECT DISTINCT mkt, sel FROM bf_hist_price WHERE mkt NOT IN ('MO','OU15','OU25','OU35','BTTS') ORDER BY 1,2 LIMIT 60")
print("== non-core mkt/sel pairs:",cur.fetchall())
cur.execute("""SELECT table_name FROM information_schema.tables WHERE table_schema='public'
 AND (table_name ILIKE '%%ah%%' OR table_name ILIKE '%%dnb%%' OR table_name ILIKE '%%handicap%%' OR table_name ILIKE '%%hist%%') ORDER BY 1""")
print("== candidate tables:",[r[0] for r in cur.fetchall()])
cur.execute("SELECT min(ts), max(ts) FROM liq_sample")
print("== liq_sample range:",cur.fetchone())
for t in ('bf_hist_other','bf_hist_other_files'):
    cur.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position",(t,))
    print(f"== {t} columns:",cur.fetchall())
    cur.execute(f"SELECT count(*) FROM {t}"); print(f"   rows:",cur.fetchone()[0])
    cur.execute(f"SELECT * FROM {t} LIMIT 1"); print("   sample:",cur.fetchall())
# full GROUP BY over 56M rows did not finish in 10 min: 2% block sample (rows x50 ~ total; markets are a lower bound)
cur.execute("""SELECT sport, market_type, count(DISTINCT market_id), count(*)*50, sum(inplay::int)*50,
 min(market_time)::date, max(market_time)::date FROM bf_hist_other TABLESAMPLE SYSTEM (2) GROUP BY 1,2 ORDER BY 1,3 DESC""")
print("== bf_hist_other (2% sample): sport | market_type | markets seen | ~rows | ~inplay rows | first | last")
for r in cur.fetchall(): print(" ",r)
print("\n== SURVIVORS: census job, no trades")
PY
