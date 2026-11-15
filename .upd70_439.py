p='watchman/FINDER_QUEUE.md'
t=open(p).read()
old="70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
assert t.count(old)==1
new=old+("2026-11-08 about 03:20 UTC: 265 files/min, disk free 57 GB, local DB 62 GB; Soccer 2023-03 at 45,120 of 56,192 files, "
"2023-05 still PARTIAL with 1 left, 26 stale months (18 LISTFAIL Nov 2024 to Apr 2026, 8 PARTIAL a few files short); "
"CORRECT_SCORE now 106,422 markets 2023-03 to 2026-09 (reports/finder_2026-11-08_item439.md). ")
t=t.replace(old,new); open(p,'w').write(t); print('ok')
