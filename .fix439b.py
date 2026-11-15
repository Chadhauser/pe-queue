for p,old,new in [('watchman/FINDER_QUEUE.md','2026-11-08 about 03:20 UTC: 265','2026-11-08 about 02:25 UTC: 265'),
                  ('reports/finder_2026-11-08_item439.md','## Item 70, loader progress (jobs/499_loader_progress.sh, read-only)','## Item 70, loader progress, about 02:25 UTC (jobs/499_loader_progress.sh, read-only; the DB clock reads an hour ahead)')]:
    s=open(p).read(); assert s.count(old)==1, (p,old); open(p,'w').write(s.replace(old,new))
print('ok')
