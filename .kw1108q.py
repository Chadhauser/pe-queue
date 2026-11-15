import re, glob
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(Q, 1):
    for m in re.finditer(r'golf', l, re.I):
        print(i, l[:60], '...', l[max(0, m.start()-300):m.start()+300])
        print('----')
for f in sorted(glob.glob('/root/pe-queue/jobs/*.sh')) + sorted(glob.glob('/root/pe-queue/reports/*.md')):
    s = open(f, errors='ignore').read()
    if re.search(r"golf", s, re.I):
        print('FILE', f)
