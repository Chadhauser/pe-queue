p='watchman/FINDER_QUEUE.md'
s=open(p).read()
old='70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — '
assert s.count(old)==1
s=s.replace(old,old+'2026-11-09 about 02:35 UTC (light read): loader active, 15,840 files last hour, newest DB clock 02:59 (about 01:59 UTC), loading 2022-Aug/Sep with Oct 2022-Mar 2023 files in the last 24 h; 26 stale months unchanged (18 LISTFAIL Nov 2024-Apr 2026, 2026-08/09 PARTIAL); the job crashed at its rows-by-market section on "SSL connection has been closed unexpectedly", not a Finder fault, not fixed (shared job). ')
open(p,'w').write(s); print('ok')
