#!/bin/bash
# 669 (Thu 19 Nov 2026). The first map (668) ranked 3 slices on 2 days of prices and the Friday line added them up to £22,100 a month.
# That is a lead, not money. From now on the map and the Friday email only COUNT a slice's pounds once it has 300+ bets; smaller
# slices are shown as leads with their bet count and no monthly total. Nothing else changes.
T=/root/pe-sports/team; R=/root/pe-queue/reports/map_669.md
{ echo "# 669 - $(date -u '+%F %H:%M') UTC"; echo '```'
cp $T/friday_four.py $T/friday_four.py.bak_669; cp $T/machine_map.py $T/machine_map.py.bak_669
python3 - <<'PY'
T='/root/pe-sports/team'
p=f'{T}/friday_four.py'; s=open(p).read()
a=s.index("try: c.execute(\"SELECT slice, n, per_month"); b=s.index("try: W = json.load")
s=s[:a]+'''try:
    c.execute("SELECT slice, n, per_month FROM map_slices WHERE run_date=(SELECT max(run_date) FROM map_slices) ORDER BY rank"); M = c.fetchall()
except Exception: M = None
'''+s[b:]
a=s.index("     (f\"Map: the ten best"); b=s.index("     f\"Audit:")
s=s[:a]+'''     ("Map: not built yet." if M is None else (lambda big: (f"Map: {len(big)} slices have 300 or more bets and add up to £{sum(x[2] for x in big):,.0f} a month against £10,000." if big else f"Map: no slice has 300 bets yet, so no pounds are counted; {len(M)} leads are being followed, the largest on {max([x[1] for x in M], default=0)} bets."))([x for x in M if x[1] >= 300])),
'''+s[b:]
open(p,'w').write(s)
p=f'{T}/machine_map.py'; s=open(p).read()
old=s[s.index('    out += ["", f"Total of the ten:'):s.index('    open(REP,')]
new='''    big = top[top.n >= 300] if not top.empty else top
    out += ["", f"Counted (300+ bets): {len(big)} slices, £{(0 if big.empty else big.per_month.sum()):,.2f} a month against £10,000. The other {len(top) - len(big)} are leads: too few bets for their monthly figure to count. Days of recorded prices: {days}.",
            "Proof: tables map_slices and map_bets (local database), written by machine_map.py; the auditor re-adds them nightly (reports/audit_latest.md)."]
'''
s=s.replace(old,new); open(p,'w').write(s); print('patched both')
PY
for f in friday_four machine_map; do python3 -m py_compile $T/$f.py && echo "$f compiles" || { cp $T/$f.py.bak_669 $T/$f.py; echo "$f COMPILE FAILED - restored"; }; done
echo "== Friday four lines, dry run (not sent)"; python3 $T/friday_four.py 2>&1 | tail -5
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "669: map counts only 300+ bets" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
