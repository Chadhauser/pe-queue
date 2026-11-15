p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
item = ("414. RUNNING 2026-11-07 (Finder's own, source a, from items 294 and 303; tables bf_hist_other, bf_hist_result, local liq_sample; job 499_jump_up_back; audit, these months chose it, so it cannot pass, it only keeps or kills) "
        "**Back a Match Odds runner whose first in-play print sits 2-4 points over its last pre-off print.** Rationale: item 294's UP 2-4 back read FAV n 400 +0.492, OUT n 204 +0.886, DRAW n 292 +1.586; item 303's job read Jun-Dec 2023, months item 294 never saw, and all three came up positive again: FAV n 259 +1.133 t 1.88, OUT n 140 +5.287 t 2.81, DRAW n 255 +0.291; both halves positive on all six reads. Against that, item 301 at the real touch read a mixed fade at -1.946 on n 108, so the print may not be takeable. "
        "Rule fixed before this job reads a price: entry, roles and costs as item 294, MO only. One bet per game, the largest gap; ties by role name. E1 worse of the print and the next within 120 s, one tick; E2 the next print only, no next print no trade, one tick; E3 as E1 at three ticks. "
        "Printed, not cut on: role, era, price under 3, 3-8, 8-50, age of the pre-off print, seconds from market time. Controls UP 1-2 and DOWN 2-4 back, not scored. "
        "Touch: local liq_sample MO, item 301's rows, UP 2-4 by ltp, largest gap per market, back at back_px, one tick, results as item 301; printed also the spread and how far back_px sits from the print. "
        "A goal cannot flatter the back: a goal against a runner gives the UP, a goal for it does not. Keep it only if E2 stays positive in both eras and the touch is not plainly negative; a kept line gets May 2023 and later loads as unseen months under the standard bar.")
assert '\n414. ' not in t
t = t.rstrip('\n') + '\n' + item + '\n'
open(p, 'w').write(t)
print('queued 414')
