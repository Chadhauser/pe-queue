p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = '339. TODO (from 8 Nov;'
assert s.count(old) == 1
s = s.replace(old, '339. RUNNING 2026-11-08 (from 8 Nov;')
open(p, 'w').write(s)
print('claimed')
