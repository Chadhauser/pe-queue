#!/bin/bash
# 575 (Sat 14 Nov 2026, 10:55). Peter: "Can we stop the emails then?" Yes. The break check keeps running every hour and keeps healing,
# but it EMAILS NOTHING. Everything it finds and heals is written to reports/breaks.md in the repository, which the chat reads.
# The Friday email is untouched. Turn back on by removing /root/pe-sports/team/BREAK_EMAILS_OFF.
set -o pipefail
touch /root/pe-sports/team/BREAK_EMAILS_OFF
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_575
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '575' not in s
old='cd /root/operators && set -a && . ./.env && set +a && PYTHONPATH=/root/operators python3 - "$B" <<\'PY\' && touch $D/$T-$K'
assert old in s, "mail anchor"
new='''echo "$(date -u +%FT%H:%M) BREAK: $B" >> /root/pe-queue/reports/breaks.md   # 575: every finding to the repository
[ -f /root/pe-sports/team/BREAK_EMAILS_OFF ] && { touch $D/$T-$K; cd /root/pe-queue && git add reports/breaks.md && git commit -qm "break log" && git pull -q --no-edit && git push -q; exit 0; }   # 575: Peter, 14 Nov 10:52 — no break emails
'''+old
s=s.replace(old,new,1)
s=s.replace('[ -n "$HEALED" ] && echo "$(date -u +%FT%H:%M) healed:$HEALED" >> /root/pe-sports/team/break_healed.log','[ -n "$HEALED" ] && { echo "$(date -u +%FT%H:%M) healed:$HEALED" >> /root/pe-sports/team/break_healed.log; echo "$(date -u +%FT%H:%M) HEALED: $HEALED" >> /root/pe-queue/reports/breaks.md; }')
open(p,'w').write(s); print("break emails off; findings and heals go to reports/breaks.md")
PY
bash -n $S && echo compiles || { cp $S.bak_575 $S; echo RESTORED; exit 1; }
bash $S; echo "break check exit $?"; tail -3 /root/pe-queue/reports/breaks.md 2>/dev/null
cd /root/pe-queue && git add reports/breaks.md 2>/dev/null; git commit -qm "575: break log" 2>/dev/null; git pull -q --no-edit && git push -q
echo "575 done"
