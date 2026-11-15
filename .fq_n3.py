import re
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(L, 1):
    m = re.match(r'^(\d+)\.\s+(\S+)', l)
    if m and m.group(2) in ('TODO', 'RUNNING'):
        print(i, l[:260])
        print()
