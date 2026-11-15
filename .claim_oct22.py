import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
tag = '(RUNNING 2026-11-08 22:05 UTC: Oct 2022 re-read, lane A, jobs/499_oct22_rereads.sh) '
done = []
for i, l in enumerate(L):
    m = re.match(r'^(445|448|450|451|465)\. TODO ', l)
    if m:
        L[i] = l.replace(' TODO ', ' TODO ' + tag, 1)
        done.append(m.group(1))
open(p, 'w').write('\n'.join(L))
print(done)
