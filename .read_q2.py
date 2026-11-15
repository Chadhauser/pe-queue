import re
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
want = ['406', '420', '421', '339', '407', '409', '410', '184']
for l in L:
    m = re.match(r'^(\d+)\.', l)
    if m and m.group(1) in want:
        print(l[:2600])
        print()
