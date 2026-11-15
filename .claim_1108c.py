import re
p = 'watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
done = []
for i, l in enumerate(L):
    m = re.match(r'(\s*)(448|450|451)\. TODO ', l)
    if m:
        L[i] = l.replace(m.group(2) + '. TODO ', m.group(2) + '. RUNNING 2026-11-08 (lane A, Soccer 2023-01 and 2023-02 read DONE at 11:00 DB clock) ', 1)
        done.append(m.group(2))
open(p, 'w').write('\n'.join(L))
print('claimed', done)
