p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
a = "303. TODO (needs data — Soccer months the test has not seen"
assert t.count(a) == 1
t = t.replace(a, "303. RUNNING 2026-11-07 (needs data — Soccer months the test has not seen")
open(p, 'w').write(t)
print('claimed 303')
