import re
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for l in L:
    m = re.match(r'^(\d+)\.', l)
    if m and m.group(1) in ('294', '414'):
        print(l[:2300])
        print()
