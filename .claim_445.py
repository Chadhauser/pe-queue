p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
old="445. TODO (re-check 12 Nov 2026, when Soccer 2023-02 reads DONE"
assert s.count(old)==1
s=s.replace(old,"445. RUNNING 2026-11-08 (lane A, interim read on Feb 2023: Soccer 2023-02 read DONE at 08:10 UTC, earlier than the 12 Nov estimate) (re-check 12 Nov 2026, when Soccer 2023-02 reads DONE",1)
open(p,'w').write(s); print('ok')
