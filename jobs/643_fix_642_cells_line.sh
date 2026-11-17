#!/bin/bash
# 643 (Tue 17 Nov 2026, 09:20). 642's edit put its comment in front of "; C={}" on the cells() query line, so cells() would fail on C.
# Move the comment after it, restart the bot, prove cells load. Report: reports/bot_643.md
R=/root/pe-queue/reports/bot_643.md; B=/root/pe-sports/bookie/bookie_v2.py
{ echo "# 643 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - "$B" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
old='x.band_lo=p.band_lo)")   # 642; C={}'; new='x.band_lo=p.band_lo)"); C={}   # 642'
print("fixed" if s.count(old)==1 else f"anchor count {s.count(old)}"); s=s.replace(old,new); open(p,'w').write(s)
PY
python3 -m py_compile $B && echo compiles; sed -n 55p $B | cut -c150-260
pkill -f 'python3 bookie_v2.py'; sleep 45
echo "bot processes: $(pgrep -f 'python3 bookie_v2.py' | wc -l)"
grep -E "passed cells|Traceback|Error" /root/pe-sports/bookie/bookie_v2.log | tail -4; tail -3 /root/pe-sports/bookie/bookie_v2.out | grep -v Deprecation | cut -c1-200
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "643: fix 642 cells line" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
