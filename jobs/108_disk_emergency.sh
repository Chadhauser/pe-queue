#!/bin/bash
# 108: DISK EMERGENCY 18 Oct 11:50 (Railway 96% of 50 GB). Causes: the market_id repair rewrote 56M rows (heap doubled, bf_hist_other
# 17 GB), ip_tape 6.9 GB, xx_tape 2.4 GB. Actions: pause loader; xx_tape truncated (done from laptop 11:55); ip_tape rebuilt at
# 5 days; VACUUM FULL bf_hist_other once free space allows (returns the bloat to the OS); retention 5 days on both tapes.
touch /root/LOADER_PAUSED
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3600s'")
def gb(): cur.execute("SELECT round(pg_database_size(current_database())/1e9,1)"); return cur.fetchone()[0]
print("DB GB",gb(),flush=True)
cur.execute("SELECT to_regclass('ip_tape_new')")
if cur.fetchone()[0] is None:
    cur.execute("CREATE TABLE ip_tape_new AS SELECT * FROM ip_tape WHERE ts > now() - interval '5 days'"); print("ip_tape_new built",flush=True)
cur.execute("SELECT count(*) FROM ip_tape_new"); print("ip_tape_new rows",cur.fetchone()[0])
cur.execute("BEGIN"); cur.execute("DROP TABLE ip_tape"); cur.execute("ALTER TABLE ip_tape_new RENAME TO ip_tape")
cur.execute("CREATE INDEX ip_tape_mkt ON ip_tape (market_id, ts)"); cur.execute("CREATE INDEX ip_tape_sport_ts ON ip_tape (sport, ts)"); cur.execute("COMMIT"); print("ip_tape swapped; DB GB",gb(),flush=True)
cur.execute("VACUUM FULL bf_hist_other"); print("bf_hist_other compacted; DB GB",gb(),flush=True)
cur.execute("VACUUM FULL xx_tape"); cur.execute("ANALYZE bf_hist_other"); cur.execute("ANALYZE ip_tape")
cur.execute("SELECT c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 6"); print(cur.fetchall()); print("FINAL DB GB",gb())
PY
# retention: 5 days on both tapes, nightly 04:30
cat > /root/pe-report/retention.py <<'PYR'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor(); cur.execute("SET statement_timeout='1800s'")
for t in ('ip_tape','xx_tape','liq_sample'):
    cur.execute(f"DELETE FROM {t} WHERE ts < now()-interval '5 days'"); print(t,cur.rowcount); cur.execute(f"VACUUM {t}")
cur.execute("SELECT round(pg_database_size(current_database())/1e9,1)"); print("DB GB",cur.fetchone()[0])
PYR
( crontab -l 2>/dev/null | grep -v retention.py ; echo "30 4 * * * cd /root/pe-report && python3 retention.py >> retention.log 2>&1" ) | crontab -
echo "retention cron installed"
