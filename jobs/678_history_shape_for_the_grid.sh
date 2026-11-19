#!/bin/bash
# 678 (Thu 19 Nov 2026). READ ONLY. Before the full grid runs on 282 million history rows: which indexes exist, how the rows spread by
# sport and year, how the in-play flag and results look on a small sample. Light queries only (index and catalogue reads, one 2,000-market sample).
R=/root/pe-queue/reports/grid_678.md
{ echo "# 678 - $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2, time
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='240s'")
def show(t,sql):
    t0=time.time()
    try: c.execute(sql); print(t); [print("  ",r) for r in c.fetchall()]; print(f"   ({time.time()-t0:.1f}s)")
    except Exception as e: print(t,"ERR",repr(e)[:160]); c.connection.rollback()
show("indexes:","select tablename, indexname, indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result','stream_ticks','xx_tape','ip_tape','liq_sample','book_snap') and schemaname='public' order by 1,2")
show("sizes:","select relname, pg_size_pretty(pg_total_relation_size(relid)) from pg_stat_user_tables where relname in ('bf_hist_other','bf_hist_result','stream_ticks','xx_tape','ip_tape','liq_sample','book_snap') and schemaname='public'")
show("result markets by sport and status:","select sport, status, count(*) from bf_hist_result group by 1,2 order by 1,3 desc")
show("result market types, top 40:","select sport, market_type, count(distinct market_id) from bf_hist_result group by 1,2 order by 3 desc limit 40")
show("sample: rows per market, share in-play, first/last print relative to the start (hours), 300 cricket markets:","""
 with m as (select distinct market_id from bf_hist_result where sport='Cricket' limit 300)
 select count(*) rows, count(distinct o.market_id) markets, round(avg(case when inplay then 1 else 0 end)::numeric,3) inplay_share,
        round(min(extract(epoch from (o.ts-o.market_time))/3600)::numeric,1) first_h, round(max(extract(epoch from (o.ts-o.market_time))/3600)::numeric,1) last_h,
        min(o.market_time)::date, max(o.market_time)::date
 from bf_hist_other o join m using (market_id)""")
show("history market_time range by sport (from results join on a sample is slow; use files table):","select column_name from information_schema.columns where table_name='bf_hist_other_files' order by ordinal_position")
show("files table sample:","select * from bf_hist_other_files limit 2")
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "678: history shape for the grid" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
