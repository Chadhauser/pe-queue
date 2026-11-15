import sys, os, glob, math
sys.path.insert(0,'/root/pe-queue/runner'); import creds
import psycopg2
def conn(x): return x if hasattr(x,'cursor') else psycopg2.connect(x)
L=conn(creds.pg_local()); lc=L.cursor()
def q(sql):
    try:
        lc.execute(sql); return lc.fetchall()
    except Exception as e:
        L.rollback(); return [('ERR',str(e).splitlines()[0])]
print('boring pass', q("select count(*) from boring_results_v3 where t>=3.5 and h1>0 and h2>0 and per10>=0.15"))
print('gsv3 max run_date', q("select max(run_date),count(*) from grid_survivors_v3"))
print('liq 15m', q("select count(*), max(ts) from liq_sample where ts>now()-interval '15 minutes'"))
print('st 15m', q("select count(*) from stream_ticks where pt>now()-interval '15 minutes'"))
rows=q("""select line,count(*),avg(pnl10),stddev(pnl10),
 avg(pnl10) filter (where tape_date< (select percentile_disc(0.5) within group (order by tape_date) from coach_tape where tape_date>current_date-7)),
 avg(pnl10) filter (where tape_date>=(select percentile_disc(0.5) within group (order by tape_date) from coach_tape where tape_date>current_date-7))
 from coach_tape where tape_date>current_date-7 and pnl10 is not null group by line order by 3 desc""")
npass=0
for r in rows:
    if r[0]=='ERR': print(r); break
    line,n,m,sd,h1,h2=r; t=(float(m)/(float(sd)/math.sqrt(n))) if sd and n>1 else 0
    ok= t>=3.5 and (h1 or 0)>0 and (h2 or 0)>0 and float(m)>=0.15
    npass+=ok
    print(line,n,round(float(m),2),round(t,2),h1 and round(float(h1),2),h2 and round(float(h2),2),'PASS' if ok else '')
print('coach lines',len(rows),'pass',npass, q("select max(tape_date) from coach_tape"))
done=set(os.listdir('/root/pe-queue-state/done'))
pend=[os.path.basename(j)[:-3] for j in sorted(glob.glob('/root/pe-queue/jobs/*.sh')) if os.path.basename(j)[:-3] not in done and os.path.basename(j) not in done]
print('pending',len(pend),pend[:30])
f=sorted(glob.glob('/root/pe-queue/reports/finder_*.md'),key=os.path.getmtime)[-1]
import time; print('finder',f,(time.time()-os.path.getmtime(f))/3600)
