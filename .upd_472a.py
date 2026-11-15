p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
a = "472. TODO (from 9 Nov; "
assert t.count(a) == 1
t = t.replace(a, "472. RUNNING 2026-11-08 22:45 UTC (lane A, jobs/499_btts_bound.sh; guard added before any price was read: an OU1.5 Over print above 1.10 in the 300 s before entry, so an unprinted second goal cannot pass) (")
open(p, 'w').write(t); print('ok')
