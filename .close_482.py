import re
P = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(P).read()
R = 'reports/finder_2026-11-09_items482-484.md'
a = "482. RUNNING 2026-11-09 04:50 UTC ("
b = "484. RUNNING 2026-11-09 05:10 UTC ("
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, "482. DONE 2026-11-09 — nothing passes, 0 of 4; MO ROUND back n 11,067 -0.437 t -2.51, MO ROUND lay -0.011, OU2.5 ROUND back n 4,122 -0.413, lay -0.068; "
              "rounds won 0.269 v 0.276 implied (MO), the crossing tick eats it; reading MO 2.0 lay n 845 +0.581 t 1.73; next door item 485; jobs/499_round_number_preoff.sh, " + R + " — (")
s = s.replace(b, "484. DONE 2026-11-09 — nothing passes, 0 of 2; WIN ROUND back n 2,643 -0.172 t -0.31, lay -0.151 t -1.86, won 0.142 v 0.137; "
              "jobs/499_round_number_racing.sh, " + R + " — (")
assert not re.search(r'^485\. ', s, re.M), 'item 485 exists'
s = s.rstrip('\n') + '\n' + ("485. TODO (re-check 22 Nov 2026 with items 455, 460, 462, when local liq_sample holds about four weeks of MO books from 27 Oct; first count markets "
     "whose last pre-off lay touch sits on a round price; Finder's own, source c structural, third door of items 482, 484; tables liq_sample (MATCH_ODDS, real touch), "
     "bf_hist_result or Railway results) **Rest a lay AT a round price on the football MO book before the off.** Rationale: item 482, MO runners whose last pre-off "
     "print is a round price won 0.269 v 0.276 implied (n 11,067), but crossing one tick (2.0 to 2.02) left the lay flat (-0.011); a lay resting at the round "
     "itself keeps the tick. Rule fixed now: last pre-off liq_sample row within 30 min of the off whose best back price is a round price (set as item 482); "
     "lay rests at that price, filled only if a later pre-off row shows traded volume at or above it or the back touch moving through it, no fill no trade; "
     "£10 liability, 2% on profit, held to the result; one bet a market; standard bar.") + '\n'
open(P, 'w').write(s)
H = '/root/pe-queue/watchman/HYPOTHESES.md'
h = open(H).read()
h = h.replace("(499_round_number_preoff, item 482) | RUNNING | -", "(499_round_number_preoff, item 482) | DONE | nothing passes; 0 of 4; MO ROUND back n 11,067 -0.437 t -2.51, lay -0.011; won 0.269 v 0.276 implied")
h = h.replace("(499_round_number_racing, item 484) | RUNNING | -", "(499_round_number_racing, item 484) | DONE | nothing passes; 0 of 2; ROUND back n 2,643 -0.172, lay -0.151 t -1.86")
assert 'item 482) | DONE' in h and 'item 484) | DONE' in h
h = h.rstrip('\n') + '\n' + "2026-11-09 | c structural (liq_sample, from 482) | rest a lay AT a round price on football MO before the off, real touch (item 485) | TODO (re-check 22 Nov) | 482 rounds won 0.269 v 0.276, the crossing tick eats it" + '\n'
open(H, 'w').write(h)
print('closed 482 484, added 485')
