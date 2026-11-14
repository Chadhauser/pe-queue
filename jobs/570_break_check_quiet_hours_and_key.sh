#!/bin/bash
# 570 (Sat 14 Nov 2026, 08:25). Two faults in the break check, both mine:
#  1. The "no bot bets in 6 hours while football is on" test counts any match-odds market on the tape, so an overnight Asian card trips it
#     when the 18 cells simply had no qualifying price. It now applies only 11:00-23:00 UTC, when the European card the cells were built on is playing.
#  2. The once-per-break key hashed the message text, which carries changing numbers, so the same break re-emailed every hour. The key is
#     now the text with digits removed.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_570
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '570' not in s
old='print(f"no bot bets in 6 hours while football is on ({on} match-odds markets on the tape);" if on>=40 and bets==0 else "")'
new='import datetime; H=datetime.datetime.utcnow().hour\n    print(f"no bot bets in 6 hours while football is on ({on} match-odds markets on the tape);" if (11<=H<23 and on>=40 and bets==0) else "")   # 570: European hours only'
assert old in s; s=s.replace(old,new,1)
old2='K=$(echo "$B" | md5sum | cut -c1-8)'; assert old2 in s
s=s.replace(old2,'K=$(echo "$B" | tr -d 0-9 | md5sum | cut -c1-8)   # 570: same break, same key, whatever the numbers',1)
open(p,'w').write(s); print("break_check patched (570)")
PY
bash -n $S && echo compiles || { cp $S.bak_570 $S; echo RESTORED; exit 1; }
echo "emails sent so far today:"; ls -la /root/pe-sports/team/break_sent/ | grep "$(date -u +%F)" | wc -l; tail -5 /root/pe-sports/team/break_healed.log 2>/dev/null
bash $S; echo "break check exit $?"
echo "570 done"
