import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
n = 0
for i, l in enumerate(L):
    if l.startswith('262. TODO ') or l.startswith('265. TODO '):
        L[i] = l.replace(' TODO ', ' RUNNING 2026-11-07 ', 1)
        n += 1
assert n == 2
open(p, 'w').write('\n'.join(L))
print('claimed', n)
