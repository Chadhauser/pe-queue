import re
t = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read()
ns = [int(m) for m in re.findall(r'^(\d+)\. ', t, re.M)]
print(max(ns), ns.count(451), ns.count(452))
print(t.split('\n')[-3][:300])
print(repr(t[-200:]))
