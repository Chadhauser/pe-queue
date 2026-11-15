p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
R = 'reports/finder_2026-11-08_items339-436.md'
old = '339. RUNNING 2026-11-08 (from 8 Nov;'
assert s.count(old) == 1
s = s.replace(old, '339. DONE 2026-11-08 — nothing passes: STALE in play Matchbook n 639 -1.496 t -14.96 h1 -1.354 h2 -1.638, Smarkets n 658 -1.459 t -16.68; pre-off n 6 -1.178; '
              'the other book had repriced by its next row (median 17 s) on 83-88% of signals, and where still stale it lost more (-2.20, -2.65), its spread wider than the move; '
              'in play read without the £10 size check, as Railway was busy (14 long queries) and xx_ip_331 has no sizes; jobs/499_xx_stale.sh, ' + R + ' (from 8 Nov;')
old = '436. TODO (Finder'
assert s.count(old) == 1
s = s.replace(old, '436. DONE 2026-11-08 — nothing passes: UNCONFIRMED FADE Matchbook n 171 -0.909 t -1.78, FOLLOW -0.940; Smarkets FADE n 116 -1.411, FOLLOW -0.983; '
              'both directions lose about the round-trip spread, so neither book knew the next move; control CONFIRMED -0.49 to -1.03; jobs/499_xx_unconfirmed.sh, ' + R + ' (Finder')
old = '70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — '
assert s.count(old) == 1
s = s.replace(old, old + '2026-11-08 about 01:50 UTC: 265 files/min, disk free 57 GB, local DB 62 GB; Soccer 2023-04 DONE, 2023-05 still PARTIAL with 1 left, 2023-03 at 36,960 of 56,192 files (' + R + '). ')
s = s.rstrip('\n')
assert '\n437. ' not in s
s += ('\n437. TODO (first step, re-pull xx_tape pre-off football with ltp, back_sz and lay_sz, 4 Nov on, one day at a time, only when Railway shows 3 or fewer queries over 5 min; it showed 14 on 8 Nov 01:41 UTC; '
      'Finder\'s own, source c, from items 330, 339, 436; tables xx_tape, local liq_sample; job 499_xx_rest to write from jobs/499_xx_stale.sh) **Rest on the wide book, hedge on Betfair.** '
      'Rationale: item 339, Matchbook and Smarkets spreads are wider than a 5% Betfair move, so taking their touch loses (-1.50, -1.46 per £10), and item 436 shows Betfair\'s own round trip costs about £1 after a jump; '
      'a resting order inside the wide book\'s spread is the one route left that pays the spread instead of crossing it. '
      'Rule fixed now, before any price is read: Matchbook football match odds, T-30 to T-2, at each Betfair row; post a back on Matchbook one tick inside its best back (or a lay one tick inside its best lay) '
      'only if that price is at least 1% better than Betfair\'s touch for the hedge, plus one tick; filled only when a later Matchbook row within 120 s prints an ltp strictly through the posted price, '
      'with size at least £10 at the touch; on a fill, hedge on Betfair at its first row at or after the fill, one tick adverse, greened, worse outcome, 2% each side; unfilled orders counted, not traded. '
      'One order per runner per game per side. Control: the same post at the touch Betfair is moving away from (Betfair mid moved 1% or more toward the posted price over the last 60 s) cannot pass. '
      'Standard bar, halves by date, t by game. If this fails too, the cross-exchange family (329-339, 436, 437) goes to Peter as a drop recommendation.')
open(p, 'w').write(s + '\n')
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old = '| fade a Betfair in-play 5% jump the other book does not confirm (499_xx_unconfirmed, item 436) | TODO | -'
assert t.count(old) == 1
t = t.replace(old, '| fade a Betfair in-play 5% jump the other book does not confirm (499_xx_unconfirmed, item 436) | DONE | nothing passes; FADE Matchbook n 171 -0.909 t -1.78, FOLLOW -0.940; Smarkets FADE -1.411, FOLLOW -0.983')
t = t.rstrip('\n')
t += '\n2026-11-08 | c (xx_tape, liq_sample, from 339) | take the other book\'s stale touch after a Betfair 5% move (499_xx_stale, item 339) | DONE | nothing passes; Matchbook IP n 639 -1.496 t -14.96, Smarkets n 658 -1.459; repriced by next row 83-88%'
t += '\n2026-11-08 | c (xx_tape, liq_sample, from 339, 436) | rest inside the wide book\'s spread pre-off, fill on a print through, hedge on Betfair (499_xx_rest, item 437) | TODO (needs xx_tape re-pull with ltp and sizes, Railway quiet) | -\n'
open(h, 'w').write(t)
print('ok')
