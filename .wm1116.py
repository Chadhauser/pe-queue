import sys, re, os, glob, datetime
sys.path.insert(0,'/root/pe-queue/runner'); import creds
import psycopg2
def conn(x): return x if hasattr(x,'cursor') else psycopg2.connect(x)
R=conn(creds.pg_railway()); L=conn(creds.pg_local())
rc=R.cursor(); lc=L.cursor()
def q(c,sql,a=None):
    try:
        c.execute(sql,a); return c.fetchall()
    except Exception as e:
        c.connection.rollback(); return [('ERR',str(e).splitlines()[0])]
print('== hosts', q(rc,"select inet_server_addr()::text"), q(lc,"select inet_server_addr()::text"))
print('== scoreboard')
row=q(rc,"select finished,log from job_results where job='SPORTS_SCOREBOARD' order by finished desc limit 1")
if row and row[0][0]!='ERR':
    f,log=row[0]; print('as of',f)
    lines=(log or '').splitlines()
    out=[];take=False
    for ln in lines:
        if ln.startswith('#') : take = ('Data health' in ln) or ('Money' in ln)
        if take or ln.startswith('Money') or '**Money' in ln: out.append(ln)
    print('\n'.join(out[:40]))
print('== failures (3h)')
handled=set(open('/root/pe-watchman/handled.txt').read().split())
for job,f,s,e,log in q(rc,"select job,finished,status,exit_code,log from job_results where finished>now()-interval '3 hours' and job<>'SPORTS_SCOREBOARD' order by finished"):
    log=log or ''
    bad = s=='failed' or 'Traceback' in log or re.search(r'(?m)^Error',log)
    print(job,f,s,e,'BAD' if bad else '', 'HANDLED' if job in handled else '')
print('== integrity false 2h')
print(q(rc,"select chk,count(*) from integrity_log where ok=false and ts>now()-interval '2 hours' group by chk order by 2 desc"))
print('== freshness')
for t,col in [('stream_ticks','ts'),('liq_sample','ts')]:
    for nm,c in [('rail',rc),('local',lc)]:
        print(t,nm,q(c,f"select max({col}), now()-max({col}) from {t} where {col}>now()-interval '1 day'"))
print('== heartbeats')
for (t,) in q(rc,"select table_name from information_schema.tables where table_name like '%%_heartbeat' order by 1"):
    cols=[x[0] for x in q(rc,"select column_name from information_schema.columns where table_name=%s and data_type like 'timestamp%%'",(t,))]
    if cols: print(t, q(rc,f"select now()-max({cols[0]}) from {t}"))
print('== bot_status STOPPED', q(rc,"select * from bot_status where status ilike 'STOPPED%%'")[:20])
print('== integrity_suite latest')
print(q(lc,"select max(ts) from integrity_suite"))
cols=[x[0] for x in q(lc,"select column_name from information_schema.columns where table_name='integrity_suite'")]
print(cols)
