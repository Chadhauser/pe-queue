#!/bin/bash
# 543 (Mon 9 Nov 2026, Peter 08:11): "List every job, test, recorder and file. KEEP only if the fair-price bot cannot go live without it.
# Delete, archive or pause everything else today and show me the list with proof. Then build the fair-price engine and nothing else."
# Order of the goal: (1) fair-price engine, all sports and all markets the tape covers; (2) the mechanical bot live at that price;
# (3) the manual screen and practice mode. Only (1) and (2) are KEEP today.
# This job: inventories crontab, running processes, /root/pe-* directories, the hypothesis registry and the database tables; classifies each
# by rule (below); PAUSES everything not KEEP that lives under /root/pe-* (cron line disabled with a '#PAUSED-543' prefix, process killed,
# STOPPED file written so watchdogs leave it down); leaves anything outside /root/pe-* untouched and listed OUT OF SCOPE (other ventures'
# agents share this box). Nothing is deleted: paused things come back by removing the prefix. Writes inventory/2026-11-09.md to the repo.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
mkdir -p /root/pe-queue/inventory
python3 - <<'PY'
import subprocess, re, os, json, datetime, glob
KEEP=[  # pattern -> why the bot cannot go live without it
 (r'liq_recorder|pe-liq/keepalive','Betfair in-play football tape (liq_sample) — the live prices the bot and the in-play map read'),
 (r'stream_client|pe-stream','Betfair stream tape (stream_ticks) — pre-off and racing prices for the map and the bot'),
 (r'xx_recorder|pe-xx','Matchbook/Smarkets tape (xx_tape) — the cross-exchange legs of the bot'),
 (r'ip_recorder|ip_tape|pe-ip','other-sports in-play tape (ip_tape) — all sports the tape covers'),
 (r'watchdog','restarts the recorders when they stall'),
 (r'recorder|xx_','a tape recorder — every market the tape covers feeds the map and the bot'),
 (r'pe-hist|hist_loader|load_basic|bf_hist','Betfair BASIC history loader — the data the fair-price map is built from'),
 (r'bsp_daily|racing_bsp','racing BSP/results files — racing map and settlement'),
 (r'sports_team|run_team','the Verifier daemon: fair-price map (H1/H1b/H1c), scoreboard'),
 (r'verifier_cells','the ONLY writer of the passed-cells table the bot quotes from'),
 (r'bookie_v2|run_bookie_v2','the mechanical bot (paper now, live at the gate)'),
 (r'integrity_suite|pe-data/integrity','the gate: data health PASS/FAIL before anything goes live'),
 (r'railway_guard','keeps the live database answering (kills 4-min reads)'),
 (r'sync_railway|pe-migrate','the database move — local must hold everything before the bot goes live on it'),
 (r'tape_archive|archive','tape archive into local — needed until the cutover is proven'),
 (r'pe-queue/runner|run_queue|queue_runner|runner\.py','the job runner — how every build lands on the box'),
 (r'watchman','the hourly health report — the proof channel for every line above'),
]
OUT_OF_SCOPE=r'operators|pe-fin|fin_team|procintel|edge-letter|edgeletter|apt|certbot|logrotate|^\s*$|^\s*#'
def cls(cmd):
    if re.search(OUT_OF_SCOPE,cmd): return 'OUT OF SCOPE',''
    if re.search(r'FINDER|finder',cmd): return 'PAUSE','the Finder test lane — paused until the bot is live'
    for pat,why in KEEP:
        if re.search(pat,cmd): return 'KEEP',why
    if '/root/pe-' in cmd or 'pe-' in cmd: return 'PAUSE','not needed for the fair-price bot to go live (stage 3 or a test)'
    return 'OUT OF SCOPE','not a trading-estate item'
rep=[f"# Inventory and action — {datetime.date.today()} (job 543)","","Rule: KEEP only if the fair-price bot cannot go live without it. Everything else under /root/pe-* PAUSED today (cron disabled, process stopped, STOPPED file). Nothing deleted. OUT OF SCOPE = other ventures' agents on the same box, untouched.",""]
# ---- crontab
cron=subprocess.run("crontab -l",shell=True,capture_output=True,text=True).stdout.split('\n')
new=[]; rep.append("## Cron lines"); rep.append("| action | line | why |"); rep.append("|---|---|---|")
for l in cron:
    if not l.strip(): new.append(l); continue
    if l.startswith('#PAUSED-543'): new.append(l); rep.append(f"| (already paused) | `{l[12:80]}` | |"); continue
    if l.startswith('#'): new.append(l); continue
    a,why=cls(l)
    if a=='PAUSE': new.append('#PAUSED-543 '+l)
    else: new.append(l)
    rep.append(f"| {a} | `{l[:90].replace('|','/')}` | {why} |")
open('/root/pe-queue/inventory/.crontab_before_543','w').write('\n'.join(cron))
subprocess.run("crontab -",input='\n'.join(new),shell=True,text=True)
# ---- processes
rep+=["","## Processes (python/bash under /root/pe-*)","| action | process | why |","|---|---|---|"]
ps=subprocess.run("ps -eo pid,etimes,args --no-headers",shell=True,capture_output=True,text=True).stdout.split('\n')
killed=[]
for l in ps:
    if not l.strip(): continue
    pid,et,cmd=l.split(None,2)
    if not re.search(r'pe-|sports_team|bookie|desk\.py|recorder|stream_client|watchman|finder',cmd): continue
    if 'ps -eo' in cmd or '543_inventory' in cmd: continue
    a,why=cls(cmd)
    rep.append(f"| {a} | `{cmd[:90].replace('|','/')}` ({int(et)//60} min) | {why} |")
    if a=='PAUSE':
        try: os.kill(int(pid),15); killed.append(cmd[:60])
        except Exception as e: rep.append(f"|  | kill failed {e} | |")
# ---- directories
rep+=["","## Directories /root/pe-*","| action | dir | why |","|---|---|---|"]
for d in sorted(glob.glob('/root/pe-*')):
    a,why=cls(d+'/')
    if a=='PAUSE': open(os.path.join(d,'STOPPED'),'w').write(f'paused 543 {datetime.date.today()} — not needed for the fair-price bot\n')
    stopped=' (STOPPED file present)' if os.path.exists(os.path.join(d,'STOPPED')) else ''
    rep.append(f"| {a} | {d}{stopped} | {why} |")
# ---- hypotheses registry
try:
    p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p)); rep+=["","## Hypotheses (Verifier daemon)","| action | id | status |","|---|---|---|"]
    for h in r['hypotheses']:
        keep=h['id'].startswith('H1')
        if not keep and h.get('status')!='paused': h['status']='paused'; h['note']='paused 543: engine only'
        rep.append(f"| {'KEEP' if keep else 'PAUSE'} | {h['id'][:70]} | {h['status']} |")
    json.dump(r,open(p,'w'),indent=1)
except Exception as e: rep.append(f"hypotheses: {e!r}")
# ---- tables (local), classification only: nothing dropped
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
KEEP_T=r'^(bf_hist|racing_bsp|liq_sample|liq_runners|stream_ticks|xx_tape|ip_tape|fair_price|bookie_paper|bookie_heartbeat|integrity|job_results|liq_heartbeat|stream_heartbeat|tape_archive)'
try:
    c=psycopg2.connect(creds.pg_local()).cursor(); c.execute("SELECT schemaname, tablename, pg_total_relation_size(quote_ident(schemaname)||'.'||quote_ident(tablename)) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 3 DESC")
    rep+=["","## Local database tables (classification; nothing dropped — a table costs nothing to keep and some hold the record)","| action | table | size |","|---|---|---|"]
    for sch,t,sz in c.fetchall():
        a='KEEP' if (sch=='public' and re.search(KEEP_T,t)) else ('ARCHIVE' if sch!='public' else 'ARCHIVE (left in place)')
        rep.append(f"| {a} | {sch}.{t} | {sz/1e6:.0f} MB |")
except Exception as e: rep.append(f"tables: {e!r}")
# ---- repo jobs: all 5xx jobs stay as the record; Finder lane (499_*) queue frozen
rep+=["","## Repo","- jobs/*.sh: the record of every build — ARCHIVE in place (git history), nothing deleted.","- Finder lane (watchman/FINDER_QUEUE.md, 499_*): PAUSED — the Finder prompt is told to stop below.","- calls/: desk output — PAUSED with the desk (stage 3).","- reports/: Watchman reports — KEEP (proof channel)."]
rep+=["",f"Killed now: {len(killed)} processes. Cron before-state saved at inventory/.crontab_before_543."]
open(f"/root/pe-queue/inventory/{datetime.date.today()}.md",'w').write('\n'.join(rep)); print('\n'.join(rep))
PY
# Finder: tell the hourly agent to stand down (its prompt file), keep the Watchman
if [ -f /root/pe-queue/watchman/FINDER.md ]; then sed -i '1i # PAUSED 9 Nov 2026 (job 543): the Finder is paused until the fair-price bot is live. Do nothing, write no job, exit.' /root/pe-queue/watchman/FINDER.md; fi
sleep 5; echo "-- after-state --"; echo "active cron lines: $(crontab -l | grep -vc '^#\|^$')  paused: $(crontab -l | grep -c '^#PAUSED-543')"; echo "pe processes still running:"; pgrep -fa 'pe-|sports_team|bookie|desk.py|recorder|stream_client' | grep -v 543_inventory | cut -c1-80
cd /root/pe-queue && git add inventory watchman/FINDER.md && git commit -q -m "543: inventory with KEEP/PAUSE per item; everything not needed for the fair-price bot paused" && git pull -q --rebase && git push -q && echo "inventory pushed: inventory/$(date +%F).md"
echo "543 done"
