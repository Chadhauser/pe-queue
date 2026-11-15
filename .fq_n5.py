import re
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(L, 1):
    m = re.match(r'^(\d+)\. (TODO|RUNNING)', l)
    if m:
        print(i, l[:260])
        print()
