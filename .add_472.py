p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n')
item = ("472. TODO (from 9 Nov; Finder's own, source c structural, an exact price bound read in-play on the full tape; checked 8 Nov: HYPOTHESES.md and queue for BTTS in-play, bound, 1-0 BTTS, "
"no-arb: item 51 read Poisson residuals on 6 days of liq_sample, items 132, 136, 142 BTTS cheap before the off only, never the in-play bound; tables bf_hist_other (BOTH_TEAMS_TO_SCORE, MATCH_ODDS, OVER_UNDER_05, OVER_UNDER_15), "
"bf_hist_result; one week of Mar 2023 holds BTTS in-play prints on 773 markets, about 14 each, so books are thin; job 499_btts_bound to write from jobs/499_nogoal_move.sh) "
"**Back BTTS Yes at 1-0 or 0-1 when its price breaks the Match Odds bound.** Rationale: at 1-0 BTTS Yes needs only the trailer to score, and the trailer cannot draw or win without scoring, "
"so P(BTTS Yes) >= P(Draw) + P(trailer wins) exactly; a BTTS Yes print implying less than that sum is cheap against the MO book in the same game, and a thin BTTS book may lag a liquid MO book. "
"Rule fixed now, before any BTTS price is read: one goal on the tape (an OU0.5 Over print at 1.05 or under, no OU1.5 Over print at 1.10 or under at or before entry), scorer = the side whose MO implied rose at that goal; "
"minute 20-80 after the first in-play MO print; bound B = MO Draw + MO trailer implied from each runner's last print in the 60 s before the BTTS Yes print (no forward fill, both must exist); "
"GAP = B - 1/p; GAP2 (GAP >= 0.02) back BTTS Yes at the worse of the print and the next within 120 s, one tick adverse, GBP 10, 2% on profit, held to the official BTTS result, never dropped; one entry per game (the first qualifying print); "
"scored line GAP2 back; printed for reading: GAP 0-0.02 back (control), GAP2 by minute band 20-45 and 46-80, and GAP2 lay (mirror); standard bar, halves by date median.")
t += '\n' + item + '\n'
open(p, 'w').write(t)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
s = open(h).read().rstrip('\n')
s += ("\n2026-11-08 | c structural (bf_hist_other, bf_hist_result, new) | back BTTS Yes at 1-0 when its print implies less than MO Draw + MO trailer, an exact bound "
      "(499_btts_bound, item 472) | TODO (from 9 Nov) | Mar 2023 week: BTTS in-play prints on 773 markets, about 14 each, thin\n")
open(h, 'w').write(s)
print('ok')
