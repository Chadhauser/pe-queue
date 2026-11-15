p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n390. ' not in s and not s.endswith('\n\n')
if not s.endswith('\n'): s += '\n'
s += ("390. RUNNING 2026-11-07 — (Finder's own, source a; tables finder_rlog from Railway bf_racing_log, racing_bsp; job 499_touch_log_racing; number 388 left for item 387's unseen read) "
      "**Morning money by resting, at the real touch.** Rationale: job 463's R<0.5 lay made +0.20 on morning WAP and item 17 tests it crossing, where the spread is expected to kill it; a resting order does not pay the spread but gets adverse fills, as 492, 494, 496 found on football. "
      "Rule fixed now, before any price: R as job 463, R<0.5, at 11:30 and 13:00 UK; offer the lay at that row's best back, filled only on a later print strictly below it by T-5; no entry tick; out at the last pre-off touch, one tick adverse; unfilled = no trade, counted. R 0.8-1.25 as control, not scored. Standard bar, t by race. Prints between 30 s rows are unseen, so fills are undercounted.\n")
open(p, 'w').write(s)
j = '/root/pe-queue/jobs/499_touch_log_racing.sh.wip'
t = open(j).read()
assert 'fixed in the queue as item 388' in t
open(j, 'w').write(t.replace('fixed in the queue as item 388', 'fixed in the queue as item 390'))
print('ok')
