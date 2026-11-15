p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
old='487. TODO (NO RESULT 2026-11-09, run time'
assert s.count(old)==1
s=s.replace(old,'487. RUNNING 2026-11-09 (re-run about 10:10 UTC, one type a night: OVER_UNDER_45 first, unseen closes pulled once into a local table) (NO RESULT 2026-11-09, run time')
open(p,'w').write(s)
print('claimed')
