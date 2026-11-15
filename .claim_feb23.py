p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
for n in (342, 352, 406, 420, 421, 422, 423, 435):
    a = '\n%d. TODO (' % n
    assert t.count(a) == 1, a
    t = t.replace(a, '\n%d. RUNNING 2026-11-08 (Feb 2023 re-read, jobs/499_feb23_rereads.sh; back to TODO after) (' % n)
open(p, 'w').write(t)
print('claimed')
