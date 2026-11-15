import re
RES = ("384. DONE 2026-11-07 — nothing passes; 0 of 60. Tennis reads clean, every line negative: Q 1.1 back 5 s n 606 -0.487 t by game -2.52, won 0.762 v 0.791; Q 1.2 back 5 s n 605 -0.526 t -2.57; lay best Q 1.2 10 s n 623 -0.086 t -0.13. Football CANNOT BE READ on this rule, a fault in my rule found after the run: at Q 1.1 football MO the median lay at the signal is 29 and only 29 of 200 sampled have a lay within 5%, so a 'touch' is mostly a junk back at 1.01 on an empty book, median fill 1.41, t to -13.4; OU25 only 43.7% resolve, as a market won by Over closes at the third goal before it prints low, so OU25 2.0 back +0.766 t 1.86 is not a read; goal_timeline check never ran, as it holds no FT row; item 385 reads football again; jobs/499_tick_touch_other.sh (reports/finder_2026-11-07_item384.md) — ")
q = open('watchman/FINDER_QUEUE.md').read()
q, n = re.subn(r"\n384\. RUNNING 2026-11-07 — ", lambda m: "\n" + RES, q)
assert n == 1
RULE = ("385. RUNNING 2026-11-07 — (Finder's own, source a; tables stream_ticks, liq_sample, Railway goal_timeline; job 499_tick_touch_clean; from item 384, whose football prints I have seen, so this rule is not blind to them and a pass needs an unseen re-read in any case) "
        "**First in-play touch of a price, football, on a real book.** Rationale: item 384's football signal was junk backs on empty books. Rule fixed now: football MO and OU25, as item 384, except the signal is the first in-play tick with back_px <= Q and lay_px on the same tick <= Q x 1.05, after a first in-play tick above Q; Q 2, 1.5, 1.3, 1.2, 1.1; D 6 and 10 s; fill, lapse, costs and halves as item 384; back and lay, 40 lines. "
        "Result: the last goal_timeline row of the game at minute 85 or later in status 2H, joined on team names by lib_cand.loose within a day, ET games not used; else for MO the last OPEN back at or under 1.03, else last-print odds; for OU25 no fall-back, unmatched not scored and counted, as a market won by Over never prints low. Agreement of the two MO results printed. Standard bar, t by game; same 5 days, so a pass earns an unseen re-read, not a stake.")
if '\n385. ' not in q:
    q = q.rstrip('\n') + '\n' + RULE + '\n'
open('watchman/FINDER_QUEUE.md', 'w').write(q)
print('ok')
