p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
assert s.count(old) == 1
s = s.replace(old, old + "2026-11-08 about 14:23 UTC (light read, .lp1108q.py, bf_hist_months and bf_hist_other_files only): about 269 files/min (2,688 in 10 min); Soccer 2022-12 DONE (44,077), 2023-01 to 2023-03 DONE, 2022-11 loading with no row yet (reports/finder_2026-11-08_item459.md). ")
open(p, 'w').write(s)
print('ok')
