p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "433. TODO (from 8 Nov; "
assert s.count(old) == 1
s = s.replace(old, "433. RUNNING 2026-11-07 (lane A, first part: item 179 via job 499_goal_type_guard; ", 1)
open(p, 'w').write(s)
print('ok')
