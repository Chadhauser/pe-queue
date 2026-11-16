#!/bin/bash
# 622 (Mon 16 Nov 2026, 18:15). Fixes from 621 (reports/stale_services.md), report in reports/fix_622.md:
#  1. 613 died at the table stage: "can't use a named cursor outside of transactions" (its connection is autocommit).
#     Give the named cursor its own non-autocommit connection and relaunch in the background (3h cap, push without GITHUB_TOKEN).
#  2. stats_collector dies on duplicate key goal_stats_live_pkey: sequences are behind after the table restore.
#     Move every sequence in the local DB up to max(id) of its column (only ever up, never down).
#  3. brain / espn / xg: show how they are meant to start (cron incl. commented lines), what runs now, the monitor_ht SQL error,
#     then start brain monitor_ht and stats_collector if they are not running. late_over and lo_live are never started.
#  4. In-play engine connection drop: where postgres logs now, and any backend crash since the 14:56 UTC restart.
R=/root/pe-queue/reports/fix_622.md
PY=/root/pe-sports/team/execution_methods.py
{
echo "# Fix 622 — $(date -u '+%F %H:%M') UTC"; echo
echo "## 1. Relaunch 613"
if pgrep -f execution_methods.py >/dev/null; then echo "already running"; else
  grep -q "con_s=psycopg2.connect" $PY || sed -i "s|^cur=con.cursor(name='st'); cur.itersize=200000|con_s=psycopg2.connect(creds.pg_local(),sslmode='disable'); con_s.autocommit=False; cur=con_s.cursor(name='st'); cur.itersize=200000|" $PY
  grep -n "cursor(name='st')" $PY
  python3 -m py_compile $PY && echo compiles || echo "COMPILE FAIL"
  cd /root/pe-sports/team && nohup setsid bash -c 'nice -n 10 timeout 10800 python3 execution_methods.py > execution_methods.log 2>&1; cd /root/pe-queue && git add reports/execution_methods.md && git commit -qm "execution methods on the recorded ladder" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q' >/dev/null 2>&1 < /dev/null &
  sleep 20; pgrep -af execution_methods.py | grep -v pgrep | head -2; tail -2 /root/pe-sports/team/execution_methods.log
fi
echo
echo "## 2. Sequences moved up to max(id)"
cd /root
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
c.execute("""SELECT s.relname, t.relname, a.attname FROM pg_class s JOIN pg_depend d ON d.objid=s.oid AND d.deptype IN ('a','i')
 JOIN pg_class t ON t.oid=d.refobjid JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=d.refobjsubid WHERE s.relkind='S'""")
moved=0
for seq,tab,col in c.fetchall():
    try:
        c.execute(f'SELECT max("{col}") FROM "{tab}"'); mx=c.fetchone()[0]
        if mx is None: continue
        c.execute(f'SELECT last_value FROM "{seq}"'); lv=c.fetchone()[0]
        if mx>lv:
            c.execute("SELECT setval(%s,%s)",(seq,mx)); moved+=1; print(f"- {tab}.{col}: {lv} -> {mx}")
    except Exception as e: print(f"- {tab}.{col}: skipped ({str(e)[:60]})")
print(f"moved {moved} sequences")
PY
echo
echo "## 3. brain / espn / xg"
echo "### cron lines (all, incl. commented)"; echo '```'; crontab -l | grep -nE 'pe-brain|pe-xg|espn|xg_|goal' ; echo '```'
echo "### running now"; echo '```'; ps -eo pid,lstart,args | grep -E 'pe-brain|pe-xg|espn|xg|goal' | grep -v grep; echo '```'
echo "### launchers"; echo '```'; ls -la /root/pe-xg/*.sh /root/pe-espn* /root/pe-xg 2>&1 | head -40; echo '```'
echo "### heartbeat rows"; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
c.execute("select table_name from information_schema.tables where table_name ilike '%heartbeat%'");
for (t,) in c.fetchall():
    try:
        c.execute(f'select * from "{t}" limit 0'); cols=[d[0] for d in c.description]; print(t, cols)
    except Exception as e: con.rollback(); print(t,'err',str(e)[:60])
PY
echo '```'
echo "### monitor_ht SQL error (calibrate_goal_model.py 115-140)"; echo '```'; sed -n 115,140p /root/pe-brain/repo/brain/calibrate_goal_model.py; echo '```'
echo "### db host each xg/espn/brain env points at (host only)"; echo '```'
for e in /root/pe-brain/env.sh /root/pe-xg/env.sh /root/pe-xg/.env /root/pe-espn/env.sh; do [ -f $e ] && echo "$e: $(grep -oE '@[a-zA-Z0-9.-]+(:[0-9]+)?/' $e | sort -u | tr '\n' ' ')"; done
echo '```'
echo "### start brain if down"
for s in monitor_ht stats_collector; do
  if pgrep -f "brain/$s.py" >/dev/null; then echo "- $s already running"; else
    nohup setsid /root/pe-brain/run_$s.sh >/dev/null 2>&1 < /dev/null & sleep 8
    echo "- $s started: $(pgrep -f "brain/$s.py" | wc -l) process(es)"; fi
done
sleep 30; echo '```'; tail -6 /root/pe-brain/stats_collector.log; echo ---; tail -6 /root/pe-brain/monitor_ht.log; echo '```'
echo
echo "## 4. Postgres since the restart"; echo '```'
sudo -u postgres psql -Atc "select name,setting from pg_settings where name in ('log_directory','log_filename','data_directory','logging_collector')"
ls -lt /var/log/postgresql/ 2>&1 | head -5
D=$(sudo -u postgres psql -Atc "show data_directory"); L=$(sudo -u postgres psql -Atc "show log_directory")
ls -t $D/$L 2>/dev/null | head -3
for f in $(ls -t /var/log/postgresql/*.log $D/$L/* 2>/dev/null | head -3); do echo "== $f"; grep -iE 'terminated by signal|server process|out of memory|crash|PANIC|could not' "$f" | tail -10; done
journalctl -u 'postgresql*' --since '14:50' 2>/dev/null | tail -15
echo '```'
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "622: relaunch 613, sequences, brain" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "622 done"
