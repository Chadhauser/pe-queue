#!/bin/bash
# 335: RAILWAY COST AUDIT. The Postgres (sslmode=require, off-box) is on Railway and the bill is £173/month.
# Report what is costing it: total DB size, top tables, rows added per day by each recorder, and whether the
# Contabo box can host the database instead (disk, postgres present). Also revert the 60-day retention (333)
# to 14 days — the tape is useful, not £100/month useful — using the .bak copies 333 made. Report only.
# 402 (watchman fix of 335): 'relname' ambiguous (pg_class join pg_stat_user_tables) -> c.relname; audit only — retention-revert block already ran in 335 and edits /root/pe-* files, so not repeated
set -o pipefail
echo "== contabo disk"; df -h / | tail -1; echo "== local postgres?"; which psql pg_ctl postgres 2>/dev/null; dpkg -l | grep -i "postgresql-[0-9]" | awk '{print $2,$3}' | head -3
echo "== memory"; free -m | head -2
echo "== db audit"
python3 - <<'PY'
import sys,psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='600s'")
host=DB.split('@')[-1].split('/')[0]; print("host:",host)
cur.execute("select pg_size_pretty(pg_database_size(current_database())), pg_database_size(current_database())"); p,b=cur.fetchone(); print("TOTAL DB:",p,f"({b/1e9:.1f} GB)")
cur.execute("""select c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) sz, pg_total_relation_size(c.oid) b,
 pg_size_pretty(pg_relation_size(c.oid)) tbl, pg_size_pretty(pg_indexes_size(c.oid)) idx, n_live_tup, n_dead_tup
 from pg_class c join pg_stat_user_tables s on s.relid=c.oid where c.relkind='r' order by 3 desc limit 20""")
print("\n== top 20 tables (total | table | indexes | live rows | dead rows)")
for r in cur.fetchall(): print(f"{r[0]:32s} {r[1]:>9s} {r[3]:>9s} {r[4]:>9s} {r[5]:>12,} {r[6]:>12,}")
print("\n== growth per day (rows in last 24h) for recorders")
for t,c in [('ip_tape','ts'),('stream_ticks','ts_recv'),('liq_sample','ts'),('goal_live_predictions','created_at'),('goal_timeline','ts'),('goal_stats_live','ts'),('coach_tape','ts'),('preoff_scalp_paper','ts')]:
    try:
        cur.execute(f"select count(*), pg_size_pretty(pg_total_relation_size('{t}')) from {t} where {c} > now()-interval '1 day'"); n,s=cur.fetchone(); print(f"{t:24s} +{n:>10,}/day   size {s}")
    except Exception as e:
        con.rollback(); cur.execute("select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%' limit 3",(t,)); print(f"{t:24s} ts col? {[x[0] for x in cur.fetchall()]}")
print("\n== connections (who is using this DB)")
cur.execute("select coalesce(application_name,''), client_addr, state, count(*) from pg_stat_activity where datname=current_database() group by 1,2,3 order by 4 desc");
for r in cur.fetchall(): print(r)
print("\n== bloat candidates: dead rows > 20% of live")
cur.execute("select relname,n_live_tup,n_dead_tup from pg_stat_user_tables where n_dead_tup > 0.2*greatest(n_live_tup,1) and n_dead_tup>100000 order by n_dead_tup desc limit 10")
for r in cur.fetchall(): print(r)
PY
echo "== fit test: can Contabo hold it? (need free disk >= 2.5x DB size for dump+restore)"
echo "VERDICT lines above: TOTAL DB vs contabo disk Avail. Migration job 336 runs only if it fits."
