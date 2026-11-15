import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_railway(), connect_timeout=20); c.autocommit = True
cur = c.cursor()
cur.execute("SET statement_timeout='45s'")
T = ['racing_form_features', 'bfsp_history', 'bf_golf_log', 'golf_markets', 'golf_leaderboards_today', 'jockey_course', 'race_fingerprints', 'ip_reopen', 'racing_signals', 'racing_shadow_trades']
for t in T:
    print('==', t)
    try:
        cur.execute(f"select * from {t} limit 2")
        cols = [d[0] for d in cur.description]
        print(' cols', cols)
        for r in cur.fetchall():
            print('  ', str(tuple(r))[:420])
        dc = [x for x in cols if x in ('ts', 'date', 'race_date', 'event_dt', 'market_time', 'created_at', 'off_time', 'recorded_at', 'snapshot_at', 'off_dt', 'fetched_at', 'race_datetime', 'captured_at')]
        for d in dc[:1]:
            cur.execute(f"select min({d}),max({d}),count(*) from {t}")
            print('  range', d, cur.fetchone())
    except Exception as e:
        print('  ERR', type(e).__name__, str(e)[:120])
