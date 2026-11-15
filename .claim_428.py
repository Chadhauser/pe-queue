p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = '428. TODO (NO RESULT 2026-11-07'
assert s.count(old) == 1
s = s.replace(old, '428. RUNNING 2026-11-07 22:05 UTC lane A (NO RESULT 2026-11-07')
open(p, 'w').write(s)
print('ok')
