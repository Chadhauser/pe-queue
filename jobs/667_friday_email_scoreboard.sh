#!/bin/bash
# 667 (Thu 19 Nov 2026, 08:25). Promised: "Friday: the scoreboard is in the email". friday_email.py only knew the v2 bot and the fade.
# Add one line: every rule on the one scoreboard's proof-gate table (top-level rows only, so it stays short). Dry run proves it.
T=/root/pe-sports/team; R=/root/pe-queue/reports/friday_667.md
{ echo '```'; cp $T/friday_email.py $T/friday_email.py.bak_667
python3 - <<'PY'
p='/root/pe-sports/team/friday_email.py'; s=open(p).read()
anchor='body="\\n".join(L)+f"\\n\\nSent'
ins='''# 667: the one scoreboard's proof-gate table (every paper runner and the machine's adopted fixes), top-level rows only
try:
    sbt=open('/root/pe-sports/team/scoreboard.md').read().split('## PROOF GATE')[1].split('## Data health')[0]; G=[]
    for ln in sbt.splitlines():
        p=[x.strip() for x in ln.split('|')]
        if len(p)>8 and p[1] and not ln.startswith('|  ') and p[1]!='rule' and not p[1].startswith('---'): G.append(f"{p[1]}: {p[2]}, £{p[3]} ({p[7]})")
    if G: L.append("Every rule on paper (the one scoreboard): "+"; ".join(G)+".")
except Exception as e: L.append(f"(scoreboard table unreadable: {e!r})"[:120])
'''
if '# 667:' in s: print('already')
else:
    assert s.count(anchor)==1, 'anchor'; open(p,'w').write(s.replace(anchor, ins+anchor)); print('patched')
PY
python3 -m py_compile $T/friday_email.py && echo compiles || { cp $T/friday_email.py.bak_667 $T/friday_email.py; echo RESTORED; }
echo "== dry run (not sent)"; cd $T && timeout 600 python3 friday_email.py 2>&1 | grep -v Deprecation | tail -6 | cut -c1-1500
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "667: friday email carries the scoreboard" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
