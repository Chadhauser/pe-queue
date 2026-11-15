import sys, time
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2, pandas as pd
c = psycopg2.connect(creds.pg_local()); c.autocommit = True
c.cursor().execute("SET work_mem='64MB'; SET statement_timeout='900s'")
T0 = time.time()
for lo, hi in (('2024-03-01', '2024-03-08'), ('2026-09-01', '2026-09-08'), ('2023-02-01', '2023-02-08')):
    q = """SELECT market_id, min(ts) first_ts, max(market_time) mt,
       count(*) FILTER (WHERE NOT inplay) npre,
       count(*) FILTER (WHERE NOT inplay AND ts BETWEEN market_time-interval '25 hours' AND market_time-interval '23 hours') n24,
       count(*) FILTER (WHERE NOT inplay AND ts BETWEEN market_time-interval '7 hours' AND market_time-interval '6 hours') n6,
       count(*) FILTER (WHERE NOT inplay AND ts BETWEEN market_time-interval '150 minutes' AND market_time-interval '120 minutes') n2,
       count(*) FILTER (WHERE NOT inplay AND ts BETWEEN market_time-interval '15 minutes' AND market_time) nko,
       count(*) FILTER (WHERE NOT inplay AND ts > market_time) nlate
       FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s GROUP BY 1"""
    A = pd.read_sql(q, c, params=(lo, hi))
    A['lead_h'] = (A.mt - A.first_ts).dt.total_seconds() / 3600
    print(lo, 'markets', len(A), 'lead hours quantiles', A.lead_h.quantile([.1, .25, .5, .75, .9]).round(1).tolist())
    for k in ('n24', 'n6', 'n2', 'nko', 'nlate'):
        print('  ', k, 'share with >=1 row', round((A[k] > 0).mean(), 3), 'median rows', A[k].median())
    print('  ', f'{time.time()-T0:.0f}s', flush=True)
