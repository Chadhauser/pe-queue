#!/bin/bash
# Finder items 17, 129, 172: copy the 30 s real-touch logs from Railway to local tables, one day at a time, so joins run locally.
# bf_racing_log -> finder_rlog; bf_tennis_log -> finder_tlog; racing_results -> finder_rresults. Whole days only. Re-runnable: ON CONFLICT DO NOTHING.
# No DROP (a runner copy can run beside a hand copy). No secrets printed. Read-only on Railway.
set -o pipefail
python3 - <<'PY'
import sys, io, time, datetime as dt
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
R = psycopg2.connect(creds.pg_railway(), connect_timeout=30); R.autocommit = True
rc = R.cursor(); rc.execute("SET statement_timeout='600s'")
L = psycopg2.connect(creds.pg_local()); lc = L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
lc.execute("""CREATE TABLE IF NOT EXISTS finder_rlog (market_id text, venue text, market_name text, market_start timestamptz, selection_id bigint, runner text,
  back_price numeric, lay_price numeric, last_traded numeric, total_matched numeric, inplay boolean, mins_to_off numeric, captured_at timestamptz,
  UNIQUE (market_id, selection_id, captured_at))""")
lc.execute("""CREATE TABLE IF NOT EXISTS finder_tlog (market_id text, event_name text, competition text, market_start timestamptz, selection_id bigint, player text,
  back_price numeric, lay_price numeric, last_traded numeric, total_matched numeric, inplay boolean, captured_at timestamptz,
  UNIQUE (market_id, selection_id, captured_at))""")
lc.execute("""CREATE TABLE IF NOT EXISTS finder_rresults (market_id text, selection_id bigint, runner text, venue text, market_name text, market_start timestamptz,
  won boolean, bsp numeric, settled_at timestamptz, UNIQUE (market_id, selection_id))""")
L.commit()
Q = {'finder_rlog': ("bf_racing_log", "market_id,venue,market_name,market_start,selection_id,runner,back_price,lay_price,last_traded,total_matched,inplay,mins_to_off,captured_at"),
     'finder_tlog': ("bf_tennis_log", "market_id,event_name,competition,market_start,selection_id,player,back_price,lay_price,last_traded,total_matched,inplay,captured_at")}
END = dt.datetime.now(dt.timezone.utc).date()   # whole days only
def start_of(tgt):
    lc.execute(f"select max(captured_at) from {tgt}"); m = lc.fetchone()[0]
    return m.astimezone(dt.timezone.utc).date() if m else dt.date(2026, 9, 7)   # top up from the last day held, so a re-run does not re-copy everything
for tgt, (src, cols) in Q.items():
    d = start_of(tgt); tot = 0; t0 = time.time()
    while d < END:
        buf = io.StringIO()
        for attempt in (1, 2, 3):
            try:
                rc.copy_expert(f"COPY (SELECT {cols} FROM {src} WHERE captured_at>='{d}' AND captured_at<'{d + dt.timedelta(days=1)}') TO STDOUT", buf)
                break
            except psycopg2.Error as e:
                print('retry', d, type(e).__name__, flush=True); time.sleep(20); buf = io.StringIO()
                R = psycopg2.connect(creds.pg_railway(), connect_timeout=30); R.autocommit = True
                rc = R.cursor(); rc.execute("SET statement_timeout='600s'")
        else:
            print('GAVE UP', tgt, d, flush=True); d += dt.timedelta(days=1); continue
        buf.seek(0)
        lc.execute(f"CREATE TEMP TABLE _t (LIKE {tgt}) ON COMMIT DROP")
        lc.copy_expert(f"COPY _t ({cols}) FROM STDIN", buf)
        lc.execute(f"INSERT INTO {tgt} SELECT * FROM _t ON CONFLICT DO NOTHING")
        tot += lc.rowcount; L.commit()
        if d.day in (1, 15): print(tgt, d, f'rows so far {tot:,} in {time.time()-t0:.0f}s', flush=True)
        d += dt.timedelta(days=1)
    print(tgt, 'added', f'{tot:,}', f'{time.time()-t0:.0f}s', flush=True)
buf = io.StringIO()
rc.copy_expert("COPY (SELECT market_id,selection_id,runner,venue,market_name,market_start,won,bsp,settled_at FROM racing_results WHERE market_start>='2026-09-01') TO STDOUT", buf)
buf.seek(0)
lc.execute("CREATE TEMP TABLE _r (LIKE finder_rresults) ON COMMIT DROP")
lc.copy_expert("COPY _r FROM STDIN", buf)
lc.execute("INSERT INTO finder_rresults SELECT * FROM _r ON CONFLICT DO NOTHING"); print('finder_rresults added', lc.rowcount, flush=True); L.commit()
lc.execute("CREATE INDEX IF NOT EXISTS finder_rlog_t ON finder_rlog (captured_at)")
lc.execute("CREATE INDEX IF NOT EXISTS finder_tlog_t ON finder_tlog (captured_at)")
L.commit()
for t in ('finder_rlog', 'finder_tlog'):
    lc.execute(f"select count(*),count(distinct market_id),min(captured_at),max(captured_at) from {t}"); print(t, lc.fetchone(), flush=True)
lc.execute("select count(*),count(distinct market_id),count(*) filter (where won),count(bsp),min(market_start),max(market_start) from finder_rresults"); print('finder_rresults', lc.fetchone(), flush=True)
print("== SURVIVORS: a data pull, none")
PY
