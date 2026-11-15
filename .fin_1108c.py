import re
p = 'watchman/FINDER_QUEUE.md'
t = open(p).read()
R = 'reports/finder_2026-11-08_items448-452.md'
NOTE = {
 '451': f"TODO (UPDATE 2026-11-08: Jan 2023, scored UNSEEN FAV E1 n 92 +0.198 t 0.17 h1 +0.676 h2 -0.279, won 0.489 v 0.475 implied; ONE E1 n 198 +0.226; under n, interim; Dec 2022 not yet on the loader; re-check as each older month loads; jobs/499_jump_up_fav_unseen.sh, {R}) ",
 '448': f"TODO (UPDATE 2026-11-08: Jan-Feb 2023 UNSEEN, scored N1 G2 NOT_LEVEL lay U n 14 +0.870 t 1.03 h1 +1.666 h2 +0.075, Under won 0.071 v 0.154 implied; same sign as item 447, under n, interim; re-check as each older month loads; jobs/499_ht_two_up_lay.sh, {R}) ",
 '450': f"TODO (UPDATE 2026-11-08: Jan-Feb 2023, scored ONE FAV back n 29 -0.065 t -0.07 h1 -0.157 h2 +0.034, won 0.636 of non-draws v 0.615 implied; NEAR n 21 +0.816, STRONG n 8 -2.378; entry taken at the first 75-103 min print where LEVEL_G holds with the draw shortest; under n, interim; re-check as each older month loads; jobs/499_level_fav_dnb_unseen.sh, {R}) ",
}
for k, v in NOTE.items():
    a = f"\n{k}. RUNNING 2026-11-08 (lane A, Soccer 2023-01 and 2023-02 read DONE at 11:00 DB clock) "
    assert t.count(a) == 1, k
    t = t.replace(a, f"\n{k}. " + v)
a = "\n452. RUNNING 2026-11-08 (lane A; "
assert t.count(a) == 1
t = t.replace(a, f"\n452. DONE 2026-11-08 — nothing passes, 0 of 6; G4 564 trades on 290 games, Under 4.5 within 1-2 points of fair at E60/70/80; best G4 E60 back n 141 +0.322 t 0.18 h1 +1.055 h2 -0.442; G3 control E70 back U3.5 n 725 +0.928 t 1.47 both halves positive, sent to item 453; jobs/499_four_goal_under.sh, {R} — (lane A; ")
assert '\n453. ' not in t
t = t.rstrip('\n') + '\n' + ("453. TODO (re-check 12 Nov 2026, when Soccer 2022 months read DONE, then each older month as the loader adds it; Finder's own, source a, from item 452's control; tables bf_hist_other, bf_hist_result; job 499_three_goal_under_unseen to write from jobs/499_four_goal_under.sh) "
  "**Back Under 3.5 at 70 min in a game holding three goals, on months no read has used.** Rationale: item 452's control, G3 E70 back U3.5 n 725 +0.928 t 1.47, h1 +1.041, h2 +0.815, Under won 0.389 v 0.351 implied; E80 back +0.431, lay mirrors -0.804 t -2.54 and -1.299 t -3.44; chosen after seeing it, and grid v2 read OU3.5 states on bf_hist_price, so expect it to shrink. "
  "Rule fixed now: item 452's code unchanged, G = 3 (OU2.5 Over at 1.05 or under 3+ min before entry, OU3.5 Over not before entry), E70 only (first Under 3.5 print 70-73 min after the first in-play OU print), back, worse of print and next within 120 s, one tick adverse, GBP 10, 2%, prices over 50 not traded, official result, never dropped, one bet a game, women and youth out; scored only on markets before 2023-01-01; standard bar, halves by date; E60 and E80 printed for reading. About 17 trades a month at item 452's rate (725 over 42 months), so n 300 needs about 18 older months.\n")
open(p, 'w').write(t)
h = 'watchman/HYPOTHESES.md'
s = open(h).read()
old = "| back or lay Under 4.5 late (60/70/80 min) in a game already holding four goals, full tape (499_four_goal_under, item 452) | RUNNING | -"
assert s.count(old) == 1
s = s.replace(old, "| back or lay Under 4.5 late (60/70/80 min) in a game already holding four goals, full tape (499_four_goal_under, item 452) | DONE | nothing passes; 0 of 6; n 290 games, U4.5 fair; G3 E70 back U3.5 control n 725 +0.928 t 1.47")
s = s.rstrip('\n') + '\n'
s += "2026-11-08 | re-reads (bf_hist_other, bf_hist_result, items 448, 450, 451) | Jan-Feb 2023, months no read had used (499_jump_up_fav_unseen, 499_ht_two_up_lay, 499_level_fav_dnb_unseen) | DONE, interim | nothing passes; 451 FAV E1 n 92 +0.198; 448 n 14 +0.870; 450 n 29 -0.065; all stay TODO\n"
s += "2026-11-08 | a (bf_hist_other, bf_hist_result, from 452) | back Under 3.5 at 70 min at three goals, months before 2023, rule fixed | TODO (item 453, re-check 12 Nov) | item 452 control n 725 +0.928 t 1.47 both halves positive\n"
open(h, 'w').write(s)
print('updated', list(NOTE), '452 DONE, 453 added')
