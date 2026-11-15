import re
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(Q, 1):
    for m in re.finditer(r'ipmin|ipmax', l, re.I):
        print(i, l[:80], '...', l[max(0, m.start()-400):m.start()+400].replace('\n', ' '))
        print('----')
import glob
for f in sorted(glob.glob('/root/pe-queue/jobs/*.sh')):
    s = open(f, errors='ignore').read()
    if re.search(r'ipmin|ipmax', s, re.I):
        print('JOB', f)
for f in sorted(glob.glob('/root/pe-queue/reports/finder_*.md')):
    s = open(f, errors='ignore').read()
    if re.search(r'ipmin|ipmax', s, re.I):
        print('REP', f)
