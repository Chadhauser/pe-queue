import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
l = psycopg2.connect(creds.pg_local())
l.autocommit = True
c = l.cursor()
def q(sql, a=None, n=25):
    c.execute(sql, a)
    rows = c.fetchall()
    print(len(rows), 'rows')
    for row in rows[:n]: print(row)
print('== boring_results_v3 pass (t>=3.5,h1>0,h2>0,per10>=0.15)')
q("select level,pattern,fav,league,n,per10,t,h1,h2 from boring_results_v3 where t>=3.5 and h1>0 and h2>0 and per10>=0.15 order by t desc")
print('== grid_survivors_v3 pass (t>=3.5,h1>0,h2>0,mean>=0.15)')
q("select max(run_date) from grid_survivors_v3")
q("select run_date,level,mkt,sel,side,exit,tband,diff,tot,red,fav,league,n,mean,t,h1,h2 from grid_survivors_v3 where t>=3.5 and h1>0 and h2>0 and mean>=0.15 order by t desc")
print('== coach_tape last 7d by line')
q("""with x as (select line, tape_date, pnl10, row_number() over (partition by line order by tape_date, minute) rn,
 count(*) over (partition by line) cnt from coach_tape where tape_date >= current_date-7 and pnl10 is not null)
 select line, count(*), round(avg(pnl10),3), round(avg(pnl10) filter (where rn<=cnt/2),3), round(avg(pnl10) filter (where rn>cnt/2),3),
 round((avg(pnl10)/nullif(stddev(pnl10),0)*sqrt(count(*)))::numeric,2)
 from x group by line order by 3 desc""", n=40)
