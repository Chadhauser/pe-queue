#!/bin/bash
# 509: the Verifier mirrors scoreboard.md into job_results (row job='FIN_SCOREBOARD') on every cycle so the chat can read it from the
# laptop MCP until the estate's off-Railway read route exists. Patch + restart daemon + print current scoreboard.
cd /root/pe-fin/team || exit 1
python3 - <<'PY'
s=open('fin_team.py').read()
if 'def mirror(' not in s:
    s=s.replace("def cycle():","""def mirror(md):
    try:
        sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
        con=psycopg2.connect(creds.pg_railway(),sslmode='require'); con.autocommit=True; cur=con.cursor()
        cur.execute("DELETE FROM job_results WHERE job='FIN_SCOREBOARD'")
        cur.execute("INSERT INTO job_results (job,started,finished,status,exit_code,log) VALUES ('FIN_SCOREBOARD',now(),now(),'scoreboard',0,%s)",(md,)); con.close()
    except Exception as e: log('mirror failed '+repr(e)[:120])
def cycle():""")
    s=s.replace("    write_scoreboard(sb)\n","    write_scoreboard(sb)\n    mirror(open(SBMD).read())\n")
    open('fin_team.py','w').write(s)
PY
python3 -m py_compile fin_team.py || exit 1
pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown; sleep 3
pgrep -f fin_team.py >/dev/null && echo "daemon restarted" || { echo "DAEMON NOT RUNNING"; exit 1; }
sleep 60; cat scoreboard.md; echo; tail -3 team.log
