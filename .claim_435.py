import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
n = 0
for i, l in enumerate(L):
    m = re.match(r'^(\s*)435\. TODO (.*)$', l)
    if m:
        L[i] = f"{m.group(1)}435. RUNNING 2026-11-08 (Finder, March 2023 read: Soccer 2023-03 read DONE about 04:05 UTC 8 Nov, the first month before Apr 2023 on the tape; jobs/499_mar23_rereads.sh) {m.group(2)}"
        n += 1
assert n == 1, n
open(p, 'w').write('\n'.join(L))
print('claimed 435')
