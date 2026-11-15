# break_check.sh verbatim — 2026-11-15 16:42 UTC (job 590)

```bash
     1	#!/bin/bash
     2	# 561: one email per break per day. Checks: database, Betfair tapes, bot process, goal monitor, failed jobs in the last hour.
     3	D=/root/pe-sports/team/break_sent; mkdir -p $D; T=$(date -u +%F); B=""; HEALED=""
     4	pg_isready -q || B="$B database not answering;"
     5	if pg_isready -q; then
     6	  python3 - <<'PY' > /tmp/break_check.out 2>&1
     7	import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
     8	c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='60s'")
     9	c.execute("select count(*) from stream_ticks where ts_recv>now()-interval '30 minutes'"); a=c.fetchone()[0]
    10	c.execute("select count(*) from liq_sample where ts>now()-interval '30 minutes'"); b=c.fetchone()[0]
    11	c.execute("select string_agg(job,', ') from job_results where status='failed' and finished>now()-interval '70 minutes'"); f=c.fetchone()[0]
    12	print("stream tape stopped;" if a==0 else "", "in-play tape stopped;" if b==0 else "", f"failed jobs {f};" if f else "")
    13	PY
    14	  B="$B $(cat /tmp/break_check.out | tr -s ' ')"
    15	fi
    16	# 563: the queue itself — git pull failing, or jobs waiting while nothing has run for 3 hours
    17	cd /root/pe-queue
    18	if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -f .git/MERGE_HEAD ]; then git rebase --abort 2>/dev/null; git merge --abort 2>/dev/null; HEALED="$HEALED aborted a stuck rebase/merge;"; fi
    19	git config pull.rebase false; git config rebase.autoStash true
    20	if ! timeout 60 git pull -q --no-edit 2>/tmp/break_pull.err; then git add -u -q 2>/dev/null; git -c user.name=breakcheck -c user.email=peter@edwardsbros.co.uk commit -qm "server-side edits (break check)" 2>/dev/null; timeout 60 git pull -q --no-edit 2>/tmp/break_pull.err && HEALED="$HEALED committed stray edits and pulled
    21	[ "$(git rev-list origin/main..HEAD --count 2>/dev/null)" != 0 ] && { timeout 60 git push -q 2>/dev/null && HEALED="$HEALED pushed local commits;"; }
    22	# sequences behind the data silently block inserts (lesson of the 13 Nov restore)
    23	SEQ=$(python3 - <<'PYS'
    24	import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
    25	try:
    26	    con=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10); con.autocommit=True; c=con.cursor(); out=[]
    27	    for t in ('goal_alerts','goal_live_predictions','goal_timeline','m1_alerts','af_fixtures','af_events','bookie_paper','desk_calls'):
    28	        try:
    29	            c.execute("select pg_get_serial_sequence(%s,'id')",(t,)); sq=c.fetchone()[0]
    30	            if not sq: continue
    31	            c.execute(f"select coalesce(max(id),0) from {t}"); mx=c.fetchone()[0]; c.execute("select last_value from "+sq); lv=c.fetchone()[0]
    32	            if lv<mx: c.execute("select setval(%s,%s)",(sq,mx)); out.append(f"{t} sequence reset {lv}->{mx}")
    33	        except Exception: pass
    34	    print("; ".join(out))
    35	except Exception as e: print("")
    36	PYS
    37	); [ -n "$SEQ" ] && HEALED="$HEALED $SEQ;"
    38	W=$(ls /root/pe-queue/jobs/*.sh | xargs -n1 basename | sed 's/\.sh$//' | while read j; do [ -f /root/pe-queue-state/done/$j ] || [ -f /root/pe-queue-state/waiting/$j ] || echo $j; done | wc -l)
    39	L=$(find /root/pe-queue-state/done -type f -newermt '-3 hours' 2>/dev/null | wc -l); [ "$W" -gt 0 ] && [ "$L" = 0 ] && B="$B $W jobs waiting and none run in 3 hours;"
    40	# 568 (Peter): no bot bets in 6 hours while football is on; bot crash-looping; disk under 10 GB
    41	BOT=$(python3 - <<'PYB'
    42	import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
    43	try:
    44	    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='60s'")
    45	    c.execute("select count(distinct market_id) from liq_sample where mkt='MO' and ts>now()-interval '6 hours'"); on=c.fetchone()[0]
    46	    c.execute("select count(*) from bookie_paper where version='v2' and ts>now()-interval '6 hours'"); bets=c.fetchone()[0]
    47	    import datetime; H=datetime.datetime.utcnow().hour
    48	    print(f"no bot bets in 6 hours while football is on ({on} match-odds markets on the tape);" if (11<=H<23 and on>=40 and bets==0) else "")   # 570: European hours only
    49	except Exception as e: print("")
    50	PYB
    51	); B="$B $BOT"
    52	# 569: read the clock, not the whole log
    53	SINCE=$(date -u -d '-60 minutes' '+%Y-%m-%d %H:%M')
    54	TB=$(awk -v s="$SINCE" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' /root/pe-sports/bookie/bookie_v2.log 2>/dev/null | grep -c "Traceback"); [ "${TB:-0}" -ge 3 ] && B="$B bot crash-looping ($TB tracebacks in the last hour);"
    55	FEED=$(python3 - <<'PYF'
    56	import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
    57	try:
    58	    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='120s'"); out=[]
    59	    for t,ts in (('stream_ticks','ts_recv'),('ip_tape','ts'),('xx_tape','ts')):
    60	        c.execute(f"select sport from (select sport, count(*) filter (where {ts}>now()-interval '6 hours') now6, count(*) filter (where {ts} between now()-interval '7 days 6 hours' and now()-interval '7 days') last6 from {t} where {ts}>now()-interval '7 days 6 hours' and ({ts}>now()-interval '6 hours' or {ts}<now()-interv
    61	        for (sp,) in c.fetchall(): out.append(f"{sp} silent 6 hours on {t}")
    62	    print("; ".join(out)+(";" if out else ""))
    63	except Exception as e: print("")
    64	PYF
    65	); B="$B $FEED"
    66	FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ -n "$FREE" ] && [ "$FREE" -lt 10 ] && B="$B disk under 10 GB free ($FREE);"
    67	# 574: bot liveness from its own heartbeat row (fresh within 15 min = alive); stale + process present -> restart first, email only if still stale next hour
    68	HB=$(python3 - <<'PYH'
    69	import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
    70	try:
    71	    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("select extract(epoch from now()-max(ts))/60 from bookie_heartbeat"); print(int(c.fetchone()[0] or 9999))
    72	except Exception: print(-1)
    73	PYH
    74	)
    75	if [ "${HB:--1}" -ge 15 ] && # 583: the job runner itself — is it cycling, and is it picking up new jobs?
    76	RC=/root/pe-queue-state/runner_cycle
    77	if [ -f "$RC" ] && [ $(( $(date +%s) - $(stat -c %Y "$RC") )) -gt 600 ]; then B="$B job runner not cycling for $(( ( $(date +%s) - $(stat -c %Y "$RC") ) / 60 )) min (lock held or hung);"; fi
    78	cd /root/pe-queue && git fetch -q origin 2>/dev/null
    79	STALE=$(git ls-tree --name-only origin/main jobs/ 2>/dev/null | while read j; do n=$(basename "$j" .sh); [ -f /root/pe-queue-state/done/$n ] || [ -f /root/pe-queue-state/waiting/$n ] || { t=$(git log -1 --format=%ct origin/main -- "$j" 2>/dev/null); [ -n "$t" ] && [ $(( $(date +%s) - t )) -gt 1800 ] && ! grep -q "$n" /roo
    80	if [ -n "$STALE" ]; then
    81	  if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    82	    mkdir -p /root/pe-queue-state/aside; git ls-files --others --exclude-standard | while read f; do git cat-file -e origin/main:"$f" 2>/dev/null && { mkdir -p "/root/pe-queue-state/aside/$(dirname "$f")"; mv "$f" "/root/pe-queue-state/aside/$f"; }; done
    83	    git merge --abort 2>/dev/null; git rebase --abort 2>/dev/null; git pull -q --no-rebase --no-edit -X theirs 2>/dev/null && HEALED="$HEALED runner clone was behind origin (jobs $STALE unseen) - pulled;" || B="$B runner clone behind origin and pull still refused (jobs $STALE unseen);"
    84	  else B="$B jobs on origin older than 30 min not run and not waiting: $STALE;"; fi
    85	fi
    86	cd /root/pe-sports/team
    87	pgrep -f bookie_v2.py >/dev/null; then
    88	  if ls /root/pe-sports/team/bot_restarted_$(date -u -d '-60 minutes' +%F_%H) /root/pe-sports/team/bot_restarted_$(date -u +%F_%H) >/dev/null 2>&1; then B="$B bot heartbeat $HB minutes old an hour after a restart;"; else pkill -f "python3 bookie_v2.py"; touch /root/pe-sports/team/bot_restarted_$(date -u +%F_%H); HEALED="$
    89	fi
    90	pgrep -f bookie_v2.py >/dev/null || B="$B bot process not running;"
    91	pgrep -f brain/monitor_ht.py >/dev/null || B="$B goal monitor not running;"
    92	B=$(echo $B | sed 's/^ *//'); [ -n "$HEALED" ] && { echo "$(date -u +%FT%H:%M) healed:$HEALED" >> /root/pe-sports/team/break_healed.log; echo "$(date -u +%FT%H:%M) HEALED: $HEALED" >> /root/pe-queue/reports/breaks.md; }; [ -z "$B" ] && exit 0
    93	K=$(echo "$B" | tr -d 0-9 | md5sum | cut -c1-8)   # 570: same break, same key, whatever the numbers; ls $D/*-$K >/dev/null 2>&1 && exit 0
    94	echo "$(date -u +%FT%H:%M) BREAK: $B" >> /root/pe-queue/reports/breaks.md   # 575: every finding to the repository
    95	[ -f /root/pe-sports/team/BREAK_EMAILS_OFF ] && { touch $D/$T-$K; cd /root/pe-queue && git add reports/breaks.md && git commit -qm "break log" && git pull -q --no-edit && git push -q; exit 0; }   # 575: Peter, 14 Nov 10:52 — no break emails
    96	cd /root/operators && set -a && . ./.env && set +a && PYTHONPATH=/root/operators python3 - "$B" <<'PY' && touch $D/$T-$K
    97	import sys,datetime; from engines.mail import send_text
    98	send_text(f"Trading estate: break today, {datetime.date.today():%d %B}", f"Break found at {datetime.datetime.utcnow():%H:%M} UTC: {sys.argv[1]} The check tried to heal it first and could not. No real money is at risk.", "peter@edwardsbros.co.uk")
    99	PY
```
lines: 99

## bot_restarted markers
/root/pe-sports/team/bot_restarted_2026-11-15_15
/root/pe-sports/team/bot_restarted_2026-11-15_16

## heartbeat query by hand
ERR column "ts" does not exist
LINE 1: select extract(epoch from now()-max(ts))/60, max(ts), now() ...
                                            ^

