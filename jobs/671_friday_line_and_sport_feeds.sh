#!/bin/bash
# 671 (Thu 19 Nov 2026, CEO orders 12:57). (a) Friday email map line: until a slice has 300+ bets it reads "nothing proven yet" and names
# the days of data behind it. (b) READ ONLY: which sports each price recorder is writing, and how the stream chooses its sports, so the
# cricket/tennis/racing question is answered from the server and the missing sports can be switched on in the next job.
T=/root/pe-sports/team; R=/root/pe-queue/reports/feeds_671.md
{ echo "# 671 - $(date -u '+%F %H:%M') UTC"; echo '```'
cp $T/friday_four.py $T/friday_four.py.bak_671
python3 - <<'PY'
p='/root/pe-sports/team/friday_four.py'; s=open(p).read()
a=s.index('    c.execute("SELECT slice, n, per_month FROM map_slices'); b=s.index("except Exception: M = None")
s=s[:a]+'''    c.execute("SELECT slice, n, per_month, days FROM map_slices WHERE run_date=(SELECT max(run_date) FROM map_slices) ORDER BY rank"); M = c.fetchall()
'''+s[b:]
a=s.index('     ("Map: not built yet." if M is None'); b=s.index('     f"Audit:')
s=s[:a]+'''     ("Map: not built yet." if M is None else (lambda big: (f"Map: {len(big)} slices have 300 or more bets and add up to £{sum(x[2] for x in big):,.0f} a month against £10,000." if big else f"Map: nothing proven yet. {max([x[3] for x in M], default=0)} days of recorded prices behind it."))([x for x in M if x[1] >= 300])),
'''+s[b:]
open(p,'w').write(s); print('friday line patched')
PY
python3 -m py_compile $T/friday_four.py && echo compiles || { cp $T/friday_four.py.bak_671 $T/friday_four.py; echo "COMPILE FAILED - restored"; }
python3 $T/friday_four.py 2>&1 | tail -4
echo "== sports per recorder, last 3 days"
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_railway(),connect_timeout=20).cursor(); c.execute("SET statement_timeout='600s'")
def show(t,sql):
    try: c.execute(sql); print(t); [print("  ",r) for r in c.fetchall()]
    except Exception as e: print(t,"ERR",repr(e)[:160]); c.connection.rollback()
show("ip_tape columns:","select string_agg(column_name,', ' order by ordinal_position) from information_schema.columns where table_name='ip_tape'")
show("in-play recorder by sport, last 3 days:","select sport, count(*), count(distinct market_id) from ip_tape where ts>now()-interval '3 days' group by 1 order by 2 desc")
show("history files by sport (markets with a result):","select sport, count(distinct market_id) from bf_hist_result group by 1 order by 2 desc")
show("bf_hist_other columns:","select string_agg(column_name||' '||data_type,', ' order by ordinal_position) from information_schema.columns where table_name='bf_hist_other'")
show("bf_hist_result columns:","select string_agg(column_name||' '||data_type,', ' order by ordinal_position) from information_schema.columns where table_name='bf_hist_result'")
show("bf_hist_other sample:","select * from bf_hist_other limit 3")
show("xx_tape market names by exchange, last day:","select exchange, market_name, count(*) from xx_tape where ts>now()-interval '1 day' group by 1,2 order by 3 desc limit 15")
PY
echo "== how the stream picks sports"
grep -nE "eventTypeIds|EVENT_TYPES|SPORTS|eventTypes|marketTypes|MARKET_TYPES|countryCodes" /root/pe-stream/stream_client.py | head -20 | cut -c1-220
echo "== how the other-exchange recorder picks sports"
F=$(pgrep -fa 'xx|cross' | grep -v pgrep | head -3); echo "$F" | cut -c1-160
grep -rnE "^SM_SPORT|^MB_SPORT|SM_SPORT ?=|MB_SPORT ?=" /root/pe-xx/*.py /root/pe-logger/*.py 2>/dev/null | head -6 | cut -c1-260
echo "== in-play recorder sports"; grep -rnE "eventTypeIds|EVENT_TYPES|SPORTS ?=" /root/pe-ip/*.py /root/pe-liq/*.py 2>/dev/null | head -8 | cut -c1-220
echo "== paused sport lines (543)"; crontab -l | grep "PAUSED-543" | grep -iE "cricket|tennis|race|golf|logger" | cut -c1-150
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "671: friday line, sport feeds" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
