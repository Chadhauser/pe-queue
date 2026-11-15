p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
R = 'reports/finder_2026-11-08_items339-436.md'
old = '437. TODO (first step,'
assert s.count(old) == 1
s = s.replace(old, '437. BLOCKED 2026-11-08 — xx_tape holds no Matchbook ltp: 0 of 105,093 pre-off rows, 635 markets, 4-8 Nov, pulled to local xx_pre_437, so a print-through fill cannot be read; '
              'needs the xx recorder to save Matchbook\'s last matched price or traded volume by price (strategy chat, not Finder); touch-through version is item 438; ' + R + ' (first step,')
s = s.rstrip('\n')
assert '\n438. ' not in s
s += ('\n438. TODO (Finder\'s own, source c, from item 437; tables local xx_pre_437, liq_sample; job 499_xx_rest, mode trade-touch) **Rest on the wide book, filled when its own touch moves through.** '
      'Rationale: item 437 cannot read a fill, as Matchbook ltp is null on every row; a later Matchbook touch strictly through a resting price means an order there would have been matched, a fill that misses market orders and so undercounts fills but not their cost. '
      'Rule fixed now, before any outcome is read: everything as item 437, except a resting BACK at P fills at the first later Matchbook row within 120 s whose back touch is strictly above P, and a resting LAY at Q at the first whose lay touch is strictly below Q. '
      'Standard bar, halves by date, t by game; CONTROL cannot pass. A pass earns a recorder ask for Matchbook traded prices, not a stake.\n')
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old = '| TODO (needs xx_tape re-pull with ltp and sizes, Railway quiet) | -'
assert t.count(old) == 1
t = t.replace(old, '| BLOCKED | Matchbook ltp null on all 105,093 pre-off rows pulled; touch-through version is item 438')
t = t.rstrip('\n') + '\n2026-11-08 | c (xx_pre_437, liq_sample, from 437) | rest inside Matchbook\'s spread, filled when its own touch moves through, hedge on Betfair (499_xx_rest trade-touch, item 438) | TODO | -\n'
open(h, 'w').write(t)
print('438 added')
