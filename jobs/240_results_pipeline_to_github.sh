#!/bin/bash
# 240: RESULTS PIPELINE — the server publishes its own results so Claude can read them without Peter's laptop. Every 10 minutes:
# job logs changed in the last 20 min, the digest, heartbeats, and CSV snapshots of every paper/live book go into the PRIVATE repo
# Chadhauser/pe-results (results/jobs/<job>.log, results/status/*.json|md, results/paper/*.csv). Needs GITHUB_RESULTS_TOKEN in
# /root/pe-logger/.env (fine-grained, Contents: write on pe-results). Waits (exit 75) until the token is there; creates the repo via
# the API if the token is allowed to (classic token), otherwise expects it to exist. The token lives only in the server env and the
# local clone's remote URL (/root/pe-results, mode 700); it never enters this public queue repo.
TOK=$(grep -E '^GITHUB_RESULTS_TOKEN=' /root/pe-logger/.env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')
if [ -z "$TOK" ]; then echo "waiting for GITHUB_RESULTS_TOKEN in /root/pe-logger/.env"; exit 75; fi
OWNER=Chadhauser; REPO=pe-results
# ensure the repo exists (create if the token can)
code=$(curl -s -o /tmp/pr.json -w '%{http_code}' -H "Authorization: Bearer $TOK" https://api.github.com/repos/$OWNER/$REPO)
if [ "$code" = "404" ]; then
  curl -s -o /tmp/pr2.json -w 'create=%{http_code}\n' -X POST -H "Authorization: Bearer $TOK" -H "Accept: application/vnd.github+json" https://api.github.com/user/repos -d "{\"name\":\"$REPO\",\"private\":true,\"auto_init\":true,\"description\":\"PE trading results (server-published)\"}"
elif [ "$code" != "200" ]; then echo "repo check HTTP $code: $(head -c 200 /tmp/pr.json)"; exit 75; fi
mkdir -p /root/pe-results && chmod 700 /root/pe-results
if [ ! -d /root/pe-results/repo/.git ]; then
  git clone -q "https://x-access-token:$TOK@github.com/$OWNER/$REPO.git" /root/pe-results/repo || { echo "clone failed"; exit 1; }
fi
cat > /root/pe-results/publish.py <<'PYFILE'
import sys, os, json, csv, datetime, subprocess, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
R='/root/pe-results/repo'; con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
os.makedirs(f'{R}/results/jobs',exist_ok=True); os.makedirs(f'{R}/results/status',exist_ok=True); os.makedirs(f'{R}/results/paper',exist_ok=True)
def q(sql):
    try: cur.execute(sql); return cur.fetchall()
    except Exception as e: con.rollback(); return [{'error':str(e)[:200]}]
# 1. job logs changed recently (and any never written)
cur.execute("SELECT job, status, exit_code, started, finished, log FROM job_results WHERE coalesce(finished,started)>now()-interval '20 minutes' OR status='running' ORDER BY job")
for r in cur.fetchall():
    with open(f"{R}/results/jobs/{r['job']}.log",'w') as f: f.write(f"# {r['job']} | {r['status']} | exit {r['exit_code']} | started {r['started']} | finished {r['finished']}\n\n{r['log'] or ''}")
# 2. status
hb={}
for t in ('stream_heartbeat','espn_heartbeat','stats_heartbeat','xg_heartbeat','late_over_heartbeat','ltd_heartbeat','lo_live_heartbeat','racing_mm_heartbeat','racing_mm_stream_hb','job_heartbeat','xx_heartbeat','ip_heartbeat','cricket_fav_heartbeat'):
    hb[t]=q(f"SELECT * FROM {t}")
json.dump(hb,open(f'{R}/results/status/heartbeats.json','w'),default=str,indent=1)
d=q("SELECT ts, body FROM digest_log WHERE part=0 ORDER BY ts DESC LIMIT 1")
open(f'{R}/results/status/digest.md','w').write(f"# Latest digest ({d[0]['ts'] if d and 'ts' in d[0] else '?'})\n\n```\n{d[0]['body'] if d and 'body' in d[0] else ''}\n```\n")
jl=q("SELECT job, status, exit_code, started, finished FROM job_results ORDER BY started DESC LIMIT 60")
open(f'{R}/results/status/jobs.md','w').write("| job | status | exit | started | finished |\n|---|---|---|---|---|\n"+"\n".join(f"| {r['job']} | {r['status']} | {r['exit_code']} | {r['started']} | {r['finished']} |" for r in jl if 'job' in r))
# 3. paper/live books as CSV
books={'late_over_paper':'SELECT * FROM late_over_paper ORDER BY entry_ts','xg_paper':'SELECT * FROM xg_paper ORDER BY entry_ts','ltd_inplay_paper':'SELECT * FROM ltd_inplay_paper ORDER BY entry_ts',
       'cricket_fav_paper':'SELECT * FROM cricket_fav_paper ORDER BY ts','racing_mm_paper':'SELECT * FROM racing_mm_paper WHERE quoted_ts>now()-interval \'14 days\' ORDER BY quoted_ts','racing_mm_stream':'SELECT * FROM racing_mm_stream ORDER BY quoted_ts',
       'lo_live_trades':'SELECT * FROM lo_live_trades ORDER BY entered_at','ltd_live_trades':'SELECT * FROM ltd_live_trades ORDER BY entered_at','pg_trades':'SELECT * FROM pg_trades ORDER BY 1 DESC LIMIT 500',
       'tennis_dog_paper':'SELECT * FROM tennis_dog_paper ORDER BY 1 DESC LIMIT 500','clv_paper':'SELECT * FROM clv_paper ORDER BY 1 DESC LIMIT 500','cs_late_paper':'SELECT * FROM cs_late_paper ORDER BY 1 DESC LIMIT 500',
       'factory_v4_shelf':'SELECT * FROM factory_v4_shelf WHERE run_date=(SELECT max(run_date) FROM factory_v4_shelf)','v4_stats_results':'SELECT * FROM v4_stats_results WHERE run_date=(SELECT max(run_date) FROM v4_stats_results) AND n>=100 ORDER BY t DESC',
       'opp_map_summary':'SELECT mkt, sel, direction, count(*) n, round(avg(pnl_per_10),2) mean FROM opp_map GROUP BY 1,2,3 ORDER BY mean DESC'}
for name,sql in books.items():
    rows=q(sql)
    if not rows or 'error' in rows[0]: open(f'{R}/results/paper/{name}.csv','w').write(f"error,{(rows or [{}])[0].get('error','empty')}\n"); continue
    with open(f'{R}/results/paper/{name}.csv','w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys())); w.writeheader(); [w.writerow({k:(v if v is not None else '') for k,v in r.items()}) for r in rows]
open(f'{R}/results/status/updated.txt','w').write(datetime.datetime.utcnow().isoformat()+"Z\n")
r=subprocess.run(f"cd {R} && git add -A && git -c user.name=pe-server -c user.email=pe-server@local commit -qm 'results {datetime.datetime.utcnow():%Y-%m-%d %H:%M}' && git push -q origin HEAD",shell=True,capture_output=True,text=True)
print("publish:",'pushed' if r.returncode==0 else ('nothing new' if 'nothing to commit' in (r.stdout+r.stderr) else r.stderr[-300:]))
PYFILE
python3 -m py_compile /root/pe-results/publish.py || exit 1
( crontab -l 2>/dev/null | grep -v "pe-results/publish.py" ; echo "*/10 * * * * cd /root/pe-results && python3 publish.py >> publish.log 2>&1" ) | crontab -
cd /root/pe-results && python3 publish.py && echo "pipeline live: $OWNER/$REPO every 10 min" && ls repo/results/paper | head -30
