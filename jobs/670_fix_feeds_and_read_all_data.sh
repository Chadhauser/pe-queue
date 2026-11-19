#!/bin/bash
# 670 (Thu 19 Nov 2026, Peter 12:51: "do the fixes now"). One job, four broken lines from the scoreboard, plus the reading the map needs.
#  1. Football results feed (af_fixtures, last row 8 Nov): its cron (af_daily.py) was paused by 543 on 9 Nov. Peter's 14 Nov order is
#     "never stop collecting" -> un-pause it, run it now, show rows by day so the gap is visible.
#  2. Goal alerts (0 since 7 Nov): READ ONLY - is the monitor alive, what does its log say, were any monitored leagues playing.
#  3. Archive watermark (stuck 12 Nov): READ ONLY - are the two database addresses now the same machine (then there is nothing to copy),
#     and is the off-box archive (object storage) still uploading.
#  4. Other-sports history engine (crashed 15 Nov): READ ONLY - did the 16 Nov rerun replace it, what does Sunday's cron run.
#  5. What the map could read today: every sport and exchange on the real-price tapes, days covered, and which result tables exist.
# Nothing is deleted, nothing places an order, no secret is printed.
R=/root/pe-queue/reports/fix_670.md
{ echo "# 670 - $(date -u '+%F %H:%M') UTC"; echo '```'
echo "== 1. football results feed"
crontab -l > /root/crontab.bak_670
crontab -l | grep -n "af_daily" | cut -c1-160
crontab -l | sed 's|^#PAUSED-543 \(.*af_daily\.py.*\)$|\1|' | crontab -
echo "after:"; crontab -l | grep -n "af_daily" | cut -c1-160
head -25 /root/pe-data/af_daily.py 2>&1 | cut -c1-200
cd /root/pe-data && timeout 900 python3 af_daily.py >> af_daily.log 2>&1; echo "run exit $?"; tail -5 af_daily.log | cut -c1-200
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2, re
L=psycopg2.connect(creds.pg_local(),sslmode='disable'); L.autocommit=True; c=L.cursor(); c.execute("SET statement_timeout='300s'")
def show(t,sql):
    try: c.execute(sql); print(t); [print("  ",r) for r in c.fetchall()]
    except Exception as e: print(t,"ERR",repr(e)[:150])
show("af_fixtures finished by day, last 14 days:","select kickoff::date d, count(*) from af_fixtures where kickoff>now()-interval '14 days' and status in ('FT','AET','PEN') group by 1 order by 1")
print("== 2. goal monitor")
show("goal_live_predictions by day, last 7:","select captured_at::date, count(*), count(*) filter (where alert_sent) from goal_live_predictions where captured_at>now()-interval '7 days' group by 1 order by 1")
show("goal_alerts last:","select max(sent_at), count(*) from goal_alerts")
print("== 3. archive")
h=lambda d:(re.search(r'@([^:/]+)',d) or re.search(r'host=(\S+)',d) or [None,'?'])[1]
try: same = h(creds.pg_railway())==h(creds.pg_local()); print("the two database addresses are the same machine:", same)
except Exception as e: print("address compare ERR",repr(e)[:100])
show("archive watermarks:","select tbl, wm, rows, updated from tape_archive_wm")
print("== 5. what the map could read")
try:
    Rw=psycopg2.connect(creds.pg_railway(),connect_timeout=20); Rw.autocommit=True; r=Rw.cursor(); r.execute("SET statement_timeout='600s'")
    def rs(t,sql):
        try: r.execute(sql); print(t); [print("  ",x) for x in r.fetchall()]
        except Exception as e: print(t,"ERR",repr(e)[:150])
    rs("stream_ticks columns:","select string_agg(column_name,', ' order by ordinal_position) from information_schema.columns where table_name='stream_ticks'")
    rs("stream_ticks by sport, last 3 days (sport, rows, markets):","select sport, count(*), count(distinct market_id) from stream_ticks where ts_recv>now()-interval '3 days' group by 1 order by 2 desc")
    rs("stream_ticks first and last row:","select min(ts_recv), max(ts_recv) from stream_ticks")
    rs("other exchanges by sport, last 3 days (exchange, sport, rows, events):","select exchange, sport, count(*), count(distinct event_name) from xx_tape where ts>now()-interval '3 days' group by 1,2 order by 1,3 desc")
    rs("other exchanges first and last row:","select exchange, min(ts), max(ts) from xx_tape group by 1")
    rs("ip_tape last row:","select max(ts) from ip_tape")
except Exception as e: print("live db ERR",repr(e)[:150])
show("tables that hold results or settlements (local):","select relname, n_live_tup from pg_stat_user_tables where relname ~* 'result|settle|bsp|winner' order by 2 desc limit 25")
show("book_snap by day (rows, markets):","select ts::date, count(*), count(distinct market_id) from book_snap group by 1 order by 1")
show("history tables (local):","select relname, n_live_tup from pg_stat_user_tables where relname ~* '^bf_hist' order by 2 desc")
PY
echo "== 2b. goal monitor process and log"
pgrep -fa '[m]onitor_ht.py' | cut -c1-120 || echo "monitor NOT running"
tail -4 /root/pe-brain/monitor_ht.log 2>&1 | cut -c1-220
echo "== 3b. archive jobs"
crontab -l | grep -n -i "archive" | cut -c1-170
tail -3 /root/pe-data/archive.log 2>&1 | cut -c1-200
ls -la /root/pe-data/ | grep -i "offbox\|archive" | head -8
for f in /root/pe-data/archive_offbox.log /root/pe-data/offbox.log; do [ -f $f ] && { echo "-- $f"; tail -3 $f | cut -c1-200; }; done
echo "== 4. weekly engine"
cat /root/pe-sports/team/weekly_engine.sh 2>&1 | cut -c1-220 | head -20
ls -la /root/pe-sports/team/ | grep -i "fairprice\|weekly" | head -12
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "670: fix feeds, read all data" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
