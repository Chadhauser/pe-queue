import re
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
H = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
nums = sorted({int(m.group(1)) for l in Q for m in [re.match(r'^(\d+)\.', l)] if m})
print('max items', nums[-5:])
pat = re.compile(r'first in-play print|first print|jump|off lag|at the off|first in-play', re.I)
print('--- queue')
for l in Q:
    m = re.match(r'^(\d+[a-z]?)\.', l)
    if m and pat.search(l):
        t = re.search(r'\*\*(.+?)\*\*', l)
        sp = re.search(r'(tennis|cricket|OVER_UNDER|OU2|BTTS)', l, re.I)
        print(m.group(1), (t.group(1) if t else l[:90])[:110], '|', sp.group(1) if sp else '')
print('--- ledger')
for l in H:
    if pat.search(l):
        print(l[:170])
for w in ['499_btts_cheap_older.sh', '499_cup_older.sh']:
    s = open('/root/pe-queue/jobs/' + w).read()
    print('---', w)
    for i, l in enumerate(s.split('\n'), 1):
        if re.search(r"2023|2024-0|WINS|month", l) and i < 60:
            print(i, l[:190])
