#!/bin/bash
# 563 (Fri 13 Nov 2026, 14:05). Two corrections to the Friday email after reading the first one, and the break check learns today's break.
#  1. Line 2 said "since the proof gate opened on 12 November" — it is the running total of every settled paper bet on these rules. Say so.
#  2. Goal signal £ was summed at whatever stake each alert carried (£50 on the old alerts). State the stake alongside, from the table.
#  3. break_check.sh: the queue wedge (runner's git pull failing / no job pulled for 3 h while jobs wait) is now a break, emailed once a day.
set -o pipefail
cd /root/pe-sports/team
python3 - <<'PY'
p='/root/pe-sports/team/friday_email.py'; s=open(p).read()
s=s.replace('f"Running total since the proof gate opened on 12 November: £{tot:+.2f} after commission, all on paper at £2 a bet."',
            'f"Running total of every settled paper bet on these rules: £{tot:+.2f} after commission, all on paper at £2 a bet."')
s=s.replace('''ga=one("select count(*), count(*) filter (where settled), coalesce(sum(pnl_paper) filter (where settled),0), count(*) filter (where settled and pnl_paper>0) from goal_alerts where sent_at>now()-interval '7 days' and coalesce(alert_type,'')<>'BOOT_TEST'",(0,0,0,0))''',
            '''ga=one("select count(*), count(*) filter (where settled), coalesce(sum(pnl_paper) filter (where settled),0), count(*) filter (where settled and pnl_paper>0), coalesce(avg(stake_gbp),0) from goal_alerts where sent_at>now()-interval '7 days' and coalesce(alert_type,'')<>'BOOT_TEST'",(0,0,0,0,0))''')
s=s.replace('''f"Goal signal alerts this week: {ga[0]} sent, {ga[1]} scored so far, {ga[3]} of those won, £{float(ga[2]):+.2f} on paper."''',
            '''f"Goal signal alerts this week: {ga[0]} sent, {ga[1]} scored so far, {ga[3]} of those won, £{float(ga[2]):+.2f} on paper at the alerts' own paper stake (average £{float(ga[4]):.0f} an alert)."''')
open(p,'w').write(s); print("friday_email.py patched:", s.count("every settled paper bet"), s.count("own paper stake"))
PY
python3 -m py_compile friday_email.py && echo compiles && python3 friday_email.py | head -6
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read()
add='''# 563: the queue itself — git pull failing, or jobs waiting while nothing has run for 3 hours
cd /root/pe-queue && if ! timeout 60 git pull -q 2>/tmp/break_pull.err; then B="$B queue cannot pull ($(tail -1 /tmp/break_pull.err | cut -c1-60));"; fi
W=$(ls /root/pe-queue/jobs/*.sh | xargs -n1 basename | sed 's/\\.sh$//' | while read j; do [ -f /root/pe-queue-state/done/$j ] || [ -f /root/pe-queue-state/waiting/$j ] || echo $j; done | wc -l)
L=$(find /root/pe-queue-state/done -type f -newermt '-3 hours' 2>/dev/null | wc -l); [ "$W" -gt 0 ] && [ "$L" = 0 ] && B="$B $W jobs waiting and none run in 3 hours;"
'''
a='pgrep -f bookie_v2.py >/dev/null'
assert a in s and '563' not in s; s=s.replace(a,add+a,1); open(p,'w').write(s); print("break_check patched")
PY
bash -n /root/pe-sports/team/break_check.sh && echo "break_check compiles" && bash /root/pe-sports/team/break_check.sh; echo "break check exit $? (0 = nothing broken or already emailed)"
echo "563 done"
