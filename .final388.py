import re, sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
s = open('/tmp/claude-0/-root-pe-queue/13945335-e254-4c0b-ba60-14d79c21104d/tasks/b78homzq7.output').read()
for pat in (r'files last 24 h.*', r'stale months.*', r'disk free.*', r'local DB.*', r'months still.*'):
    m = re.search(pat, s); print(m.group(0)[:150] if m else 'no ' + pat)
print(s.strip().split('\n')[-3][:160]); print(s.strip().split('\n')[-2][:160])
print([l.strip() for l in s.split('\n') if 'Soccer' in l and 'PARTIAL' in l][:1])
c = psycopg2.connect(creds.pg_railway(), connect_timeout=20); c.autocommit = True; cur = c.cursor(); cur.execute("SET statement_timeout='60s'")
cur.execute("select now(), max(ts_recv), count(*), count(distinct market_id) from stream_ticks where ts_recv>now()-interval '15 minutes'"); print('stream_ticks last 15 min (now, newest, rows, markets)', cur.fetchone())
cur.execute("select max(captured_at), count(distinct market_id) from bf_racing_log where captured_at>now()-interval '15 minutes'"); print('bf_racing_log last 15 min', cur.fetchone())
cur.execute("select max(captured_at), count(distinct market_id) from bf_tennis_log where captured_at>now()-interval '15 minutes'"); print('bf_tennis_log last 15 min', cur.fetchone())
L = psycopg2.connect(creds.pg_local()); lc = L.cursor()
lc.execute("select to_regclass('finder_rlog'),to_regclass('finder_tlog'),to_regclass('finder_rresults')"); print(lc.fetchone())
lc.execute("select pg_size_pretty(pg_total_relation_size('finder_rlog')),pg_size_pretty(pg_total_relation_size('finder_tlog'))"); print('local size', lc.fetchone())
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read()
print('numbers 388, 389 now in queue:', bool(re.search(r'^388\. ', Q, re.M)), bool(re.search(r'^389\. ', Q, re.M)))
