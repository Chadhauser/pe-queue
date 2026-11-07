#!/bin/bash
# 527: BUILD STEP 7 Nov — pull the EdgeLetter results database into the trading store (Peter 08:32: "First build step: pull the
# EdgeLetter results database into the trading store and report what's new"). Source: EDGE_DB_URL in /root/operators/.env (read-only
# role; never printed). Target: local PostgreSQL, schema `edge` (one-off copy; data then flows only trading -> EdgeLetter).
# Report: every table with rows, columns, and date range; what trading already holds (racing_bsp, bf_hist_*, af_*) for the overlap.
set -o pipefail
export PATH=/usr/lib/postgresql/18/bin:$PATH
set -a; . /root/operators/.env 2>/dev/null; set +a
[ -n "$EDGE_DB_URL" ] || { echo "EDGE_DB_URL not in /root/operators/.env — looking elsewhere"; grep -l EDGE_DB_URL /root/*/.env /root/pe-logger/.env 2>/dev/null; exit 1; }
LOCAL=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")
echo "== source inventory (read-only)"
psql "$EDGE_DB_URL" -Atc "select current_database(), version()" | cut -c1-80
psql "$EDGE_DB_URL" -Atc "select n.nspname||'.'||c.relname||' | '||c.reltuples::bigint||' est rows | '||pg_size_pretty(pg_total_relation_size(c.oid)) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname not in ('pg_catalog','information_schema') order by pg_total_relation_size(c.oid) desc"
echo "== copy into local schema edge"
psql "$LOCAL" -c "DROP SCHEMA IF EXISTS edge CASCADE; CREATE SCHEMA edge"
pg_dump --no-owner --no-acl --no-privileges --schema=public "$EDGE_DB_URL" | sed -E 's/^SET search_path = .*$/SET search_path = edge, public;/; s/^(CREATE TABLE|ALTER TABLE( ONLY)?|COPY|INSERT INTO|CREATE (UNIQUE )?INDEX [^ ]+ ON|CREATE SEQUENCE|ALTER SEQUENCE|SELECT pg_catalog.setval\()\s*public\./\1 edge./; s/REFERENCES public\./REFERENCES edge./g; s/^CREATE SCHEMA public;//' | psql -q "$LOCAL" 2>&1 | grep -v "already exists\|^SET\|^$" | tail -5
echo "== local edge schema: rows and date ranges"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='900s'")
k.execute("select table_name from information_schema.tables where table_schema='edge' and table_type='BASE TABLE' order by 1"); tabs=[t for (t,) in k.fetchall()]
print("tables:",len(tabs))
for t in tabs:
    k.execute("select column_name,data_type from information_schema.columns where table_schema='edge' and table_name=%s order by ordinal_position",(t,)); cols=k.fetchall()
    dcol=next((cn for cn,dt in cols if dt in ('date','timestamp without time zone','timestamp with time zone')),None)
    k.execute(f'select count(*) from edge."{t}"'); n=k.fetchone()[0]
    rng=''
    if dcol and n:
        k.execute(f'select min("{dcol}")::date, max("{dcol}")::date from edge."{t}"'); a,b=k.fetchone(); rng=f" | {dcol} {a}..{b}"
    print(f"  edge.{t}: {n} rows | {len(cols)} cols: {', '.join(cn for cn,_ in cols)[:160]}{rng}")
print("== what trading already holds (for the overlap)")
for sql,label in (("select count(*), min(event_dt)::date, max(event_dt)::date from racing_bsp","racing_bsp (BSP+result, UK/IE)"),
                  ("select count(*), min(market_time)::date, max(market_time)::date from bf_hist_price","bf_hist_price (Betfair history, racing)"),
                  ("select count(distinct market_id), min(market_time)::date, max(market_time)::date from bf_hist_other where sport='Horse Racing'","bf_hist_other Horse Racing markets"),
                  ("select count(*), min(kickoff)::date, max(kickoff)::date from af_fixtures where status in ('FT','AET','PEN')","af_fixtures finished"),
                  ("select count(*), min(date)::date, max(date)::date from fd_matches","fd_matches (football-data.co.uk)")):
    try: k.execute(sql); print(" ",label,k.fetchone())
    except Exception as e: print(" ",label,"n/a",str(e)[:60]); c.rollback()
PY
