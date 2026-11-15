import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
def q(sql, a=None, n=20, to='60s'):
    try:
        r = psycopg2.connect(creds.pg_railway(), connect_timeout=20)
        r.autocommit = True
        c = r.cursor()
        c.execute(f"set statement_timeout='{to}'")
        c.execute(sql, a)
        rows = c.fetchall()
        r.close()
        return rows
    except Exception as e:
        return [('ERR', str(e).splitlines()[0][:120])]
def p(label, rows):
    print(label)
    for row in rows: print('  ', row)
p('liq_sample cols', q("select column_name from information_schema.columns where table_name='liq_sample' and data_type like 'timestamp%%'"))
p('liq_sample 60s inserts (pg_stat)', q("select n_tup_ins from pg_stat_user_tables where relname='liq_sample'"))
p('liq_sample recent', q("select max(ts), count(*) from liq_sample where ts > now()-interval '15 minutes'", to='90s'))
hb = q("select table_name from information_schema.tables where table_name like '%%heartbeat%%' and table_schema='public'")
for (t, *_) in hb:
    cols = q("select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%'", (t,))
    if cols and cols[0][0] != 'ERR':
        p(t, q(f"select max({cols[0][0]}), round(extract(epoch from now()-max({cols[0][0]}))/60) from {t}"))
p('bot_status', q("select * from bot_status"))
p('delete_trap cols', q("select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_name='delete_trap'"))
p('delete_trap last', q("select * from delete_trap order by 1 desc limit 6"))
p('report jobs 6h', q("select job, status, exit_code, finished from job_results where finished > now()-interval '6 hours' and job = any(%s) order by finished",
  ([l.strip() for l in open('/root/pe-queue/watchman/REPORT_JOBS.txt') if l.strip()],)))
p('all jobs 3h', q("select job, status, exit_code, finished from job_results where finished > now()-interval '3 hours' and job<>'SPORTS_SCOREBOARD' order by finished"))
p('scoreboard mirror', q("select max(finished) from job_results where job='SPORTS_SCOREBOARD'"))
p('active long queries', q("select count(*), max(round(extract(epoch from now()-query_start))) from pg_stat_activity where state='active' and now()-query_start > interval '20 seconds'"))
