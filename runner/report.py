import sys, os, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS job_results (job TEXT PRIMARY KEY, started TIMESTAMPTZ, finished TIMESTAMPTZ, status TEXT, exit_code INT, log TEXT);
               CREATE TABLE IF NOT EXISTS job_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, host TEXT)""")
a=sys.argv[1]
if a=='heartbeat':
    cur.execute("INSERT INTO job_heartbeat (id,last_seen,host) VALUES (1,NOW(),%s) ON CONFLICT (id) DO UPDATE SET last_seen=NOW()",(os.uname().nodename,))
elif a=='start':
    cur.execute("INSERT INTO job_results (job,started,status) VALUES (%s,NOW(),'running') ON CONFLICT (job) DO UPDATE SET started=NOW(), status='running', finished=NULL, log=NULL",(sys.argv[2],))
elif a=='finish':
    log=open(sys.argv[4],errors='replace').read()
    if len(log)>400000: log=log[:150000]+"\n...[truncated]...\n"+log[-250000:]
    cur.execute("UPDATE job_results SET finished=NOW(), status=%s, exit_code=%s, log=%s WHERE job=%s",('ok' if sys.argv[3]=='0' else 'waiting' if sys.argv[3]=='75' else 'failed',int(sys.argv[3]),log,sys.argv[2]))
