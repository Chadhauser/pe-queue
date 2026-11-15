p='watchman/FINDER_QUEUE.md'
s=open(p).read()
old='472. TODO (RESULT 2026-11-08'
assert s.count(old)==1
s=s.replace(old,'472. RUNNING 2026-11-09 (Finder lane default/top, 01:45 UTC: .diag472c.py trade-level check) (RESULT 2026-11-08')
open(p,'w').write(s)
print('ok')
