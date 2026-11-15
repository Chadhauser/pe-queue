import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
want = {'406', '420', '421', '422', '423', '342', '352'}
done = []
for i, l in enumerate(L):
    m = re.match(r'^(\s*)(\d+)\. TODO (.*)$', l)
    if m and m.group(2) in want:
        L[i] = f"{m.group(1)}{m.group(2)}. RUNNING 2026-11-08 (Finder, April 2023 re-read: Soccer 2023-04 read DONE about 01:50 UTC 8 Nov, after the May 2023 reads; jobs/499_apr23_rereads.sh) {m.group(3)}"
        done.append(m.group(2))
assert sorted(done) == sorted(want), done
open(p, 'w').write('\n'.join(L))
print('claimed', sorted(done))
