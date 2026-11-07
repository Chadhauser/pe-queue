#!/bin/bash
# 529: FINDING from 527 — EDGE_DB_URL points at the TRADING database on Railway itself (same tables: liq_heartbeat, delete_trap, goal_*,
# bf_hist_*). EdgeLetter never had its own results store; it reads trading's. 527 was therefore dumping the whole 54 GB Railway schema
# into local `edge` and was stopped at bf_hist_price (its pg_dump backend terminated 09:00). This job: (1) proves the two DSNs share a
# host; (2) drops the partial `edge` schema; (3) copies only the EdgeLetter-specific small tables that are NOT already local
# (draw_bias, el_subscribers, referee_stats, trainer_name_map, upcoming_referees) into local schema `edge`; (4) reports what is new.
set -o pipefail
export PATH=/usr/lib/postgresql/18/bin:$PATH
set -a; . /root/operators/.env 2>/dev/null; set +a
python3 - <<'PY'
import os,sys,re,psycopg2,subprocess; sys.path.insert(0,'/root/pe-queue/runner'); import creds
def host(d): m=re.search(r'@([^/:]+)',d or ''); return m.group(1) if m else '?'
print("EDGE_DB_URL host:",host(os.environ.get('EDGE_DB_URL')),"| trading railway host:",host(creds.pg_railway()),"| same:",host(os.environ.get('EDGE_DB_URL'))==host(creds.pg_railway()))
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute("SET statement_timeout='900s'")
lc.execute("select table_name, pg_total_relation_size('edge.'||quote_ident(table_name)) from information_schema.tables where table_schema='edge'"); print("partial edge schema tables from 527:",len(lc.fetchall()))
lc.execute("DROP SCHEMA IF EXISTS edge CASCADE; CREATE SCHEMA edge")
R=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc=R.cursor(); rc.execute("SET statement_timeout='300s'")
lc.execute("select table_name from information_schema.tables where table_schema='public'"); local_tabs={t for (t,) in lc.fetchall()}
want=['draw_bias','el_subscribers','referee_stats','trainer_name_map','upcoming_referees','racing_fill_model','pe_backtest_results','pe_backtest_all_runners']
env=dict(os.environ); env['PATH']='/usr/lib/postgresql/18/bin:'+env['PATH']
for t in want:
    rc.execute("select to_regclass(%s) is not null",(t,))
    if not rc.fetchone()[0]: print(f"  {t}: not on railway"); continue
    if t in local_tabs: print(f"  {t}: already local (public), skipped"); continue
    p=subprocess.run(f"pg_dump --no-owner --no-acl -t public.{t} '{creds.pg_railway()}' | sed -E 's/public\\.{t}/edge.{t}/g; s/^SET search_path = .*$/SET search_path = edge, public;/' | psql -q '{creds.pg_local()}'",shell=True,capture_output=True,text=True,env=env)
    lc.execute(f"select count(*) from edge.{t}"); n=lc.fetchone()[0]
    lc.execute("select column_name,data_type from information_schema.columns where table_schema='edge' and table_name=%s order by ordinal_position",(t,)); cols=lc.fetchall()
    dcol=next((c for c,d in cols if d in ('date','timestamp without time zone','timestamp with time zone')),None); rng=''
    if dcol and n: lc.execute(f'select min("{dcol}")::date,max("{dcol}")::date from edge.{t}'); rng=f" | {dcol} {lc.fetchone()}"
    print(f"  edge.{t}: {n} rows | cols {', '.join(c for c,_ in cols)[:150]}{rng}")
rc.execute("select count(*), min(race_date), max(race_date) from draw_bias") if False else None
print("== EdgeLetter pages' data sources already local (racing_bsp, bf_hist_price, af_fixtures, fd_matches): yes — see 527's overlap block")
PY
