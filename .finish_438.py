p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = '438. TODO (Finder'
assert s.count(old) == 1
s = s.replace(old, '438. DONE 2026-11-08 — nothing passes: 297 games, 392 posts, 2 touch-through fills in 120 s, 1 traded -0.793, n 1; Matchbook\'s touch almost never moves through a price inside its spread in 2 min; '
              'third door of the cross-exchange family, so the report carries a drop recommendation for items 329-339, 436-438; jobs/499_xx_rest.sh trade-touch, reports/finder_2026-11-08_items339-436.md (Finder')
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old = '(499_xx_rest trade-touch, item 438) | TODO | -'
assert t.count(old) == 1
t = t.replace(old, '(499_xx_rest trade-touch, item 438) | DONE | nothing passes; 392 posts, 2 fills, n 1 -0.793; family to Peter as a drop recommendation')
open(h, 'w').write(t)
print('ok')
