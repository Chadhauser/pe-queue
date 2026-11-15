p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
for it in ('445','448','450','465'):
    old='\n'+it+'. TODO ('
    assert s.count(old)==1, it
    s=s.replace(old,'\n'+it+'. RUNNING 2026-11-09 02:30 UTC (Soccer 2022-09 read DONE, Sep 2022 re-read, code unchanged) (',1)
open(p,'w').write(s)
print('ok')
