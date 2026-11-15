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
def cols(c,t): return [x[0] for x in q(c,"select column_name from information_schema.columns where table_name=%s order by ordinal_position",(t,))]
print('stream_ticks cols',cols(rc,'stream_ticks'))
for cn in cols(rc,'stream_ticks'):
    if cn in ('ts_utc','recv_ts','pt','received','ts_ms','t','tick_ts','created_at','inserted_at'):
        print(cn, q(rc,f"select max({cn}) from stream_ticks"))
print('== suite')
last=q(lc,"select max(run_at) from integrity_suite")[0][0]; print('last run',last)
print(q(lc,"select status,count(*) from integrity_suite where run_at=(select max(run_at) from integrity_suite) group by 1"))
for r in q(lc,"select chk,value,left(detail,140) from integrity_suite where run_at=(select max(run_at) from integrity_suite) and status<>'PASS' order by chk"): print(' FAIL',r)
print('== delete_trap', cols(rc,'delete_trap'))
dc=cols(rc,'delete_trap')
tcol=[c for c in dc if 'ts' in c or 'at' in c or 'time' in c]
print(q(rc,f"select * from delete_trap order by {tcol[0] if tcol else 1} desc limit 6"))
print(q(rc,f"select count(*) from delete_trap where {tcol[0]}>now()-interval '24 hours'") if tcol else '')
print('== tape_archive_wm', cols(lc,'tape_archive_wm'))
for r in q(lc,"select * from tape_archive_wm"): print(' ',r)
print('== survivors')
for t in ['boring_results_v3','rgrid_survivors','grid_survivors_v3','gs_vs_market','coach_tape']:
    for nm,c in [('local',lc),('rail',rc)]:
        n=q(c,f"select count(*) from {t}")
        print(t,nm,n, cols(c,t)[:25] if n and n[0][0]!='ERR' else '')
