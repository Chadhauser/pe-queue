import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).readlines()
done = 0
for i, l in enumerate(L):
    for n in ('17', '172', '129'):
        if l.startswith(n + '. TODO (needs data'):
            L[i] = n + '. RUNNING 2026-11-07 (data found on the box: Railway bf_racing_log and bf_tennis_log, 30 s real touch since 7 Sep 2026, no Finder job had read them) — ' + l[len(n) + 2 + 5:]
            done += 1
assert done == 3, done
open(p, 'w').writelines(L)
print('claimed', done)
