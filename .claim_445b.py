p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
old='\n445. TODO ('
assert s.count(old)==1
s=s.replace(old,'\n445. RUNNING 2026-11-08 16:05 UTC (Nov 2022 read DONE, re-run unchanged) (',1)
open(p,'w').write(s)
print('ok')
