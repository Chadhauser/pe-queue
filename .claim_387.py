import re
RES = ("386. DONE 2026-11-07 — NOT a pass, 2 numeric passes struck by me: Q 1.1 back 6 s n 340 +0.407 t by game 3.86 h1 +0.439 h2 +0.375 won 0.965 v 0.918, 10 s n 344 +0.392 t 3.66. The rule drops 58 of 448 touches, and a third goal in the last 5 minutes is what lands a market there: a late loser on the Under, the bias the honesty rules name. Counted as losers, about -1.11. Item 387 settles them; jobs/499_tick_touch_ou25.sh (reports/finder_2026-11-07_item384.md) — ")
q = open('watchman/FINDER_QUEUE.md').read()
q, n = re.subn(r"\n386\. RUNNING 2026-11-07 — ", lambda m: "\n" + RES, q)
assert n == 1
RULE = ("387. RUNNING 2026-11-07 — (Finder's own, source a; tables stream_ticks, liq_sample, Railway goal_timeline; job 499_tick_touch_cs; from items 385 and 386, whose prints I have seen, so a pass here still needs item 388 on unseen games) "
        "**First in-play touch, football MO and OU25, settled from the correct-score market.** Rule fixed now, entries and costs as item 385, 40 lines; only the result changes: the last liq_sample CS row of the game at minute 85 or later with a selection at back_px <= 1.2 and lay_px <= 1.3 on that row gives the score; ANYOTHER counts as 4 or more goals, and its side for MO. OU25 conflict: CS says Under but Under's last OPEN back on the stream is over 1.05, as a goal after the last CS row looks like this, unresolved. Unresolved entries are not dropped: every line is graded with them as a -£10 loser, the worst case, and the middle read with them left out is printed beside it. A line passes only on the worst case. Agreement with the goal row printed; below 95% or under 30 checked, no pass.")
if '\n387. ' not in q:
    q = q.rstrip('\n') + '\n' + RULE + '\n'
open('watchman/FINDER_QUEUE.md', 'w').write(q)
print('ok')
