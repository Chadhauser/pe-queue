p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "487. TODO (next door of item 486;"
assert s.count(old) == 1
s = s.replace(old, "487. RUNNING 2026-11-09 (claimed about 07:56 UTC, same run as 486; next door of item 486;")
open(p, 'w').write(s); print('ok')
