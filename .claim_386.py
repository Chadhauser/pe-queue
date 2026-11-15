import re
RES = ("385. DONE 2026-11-07 — nothing passes; 0 of 40. MO back negative at every level on a real book: Q 1.1 6 s n 590 -0.526 t by game -3.65 h1 -0.550 h2 -0.502, won 0.885 v 0.918; Q 1.2 n 649 -0.782 t -4.52; Q 2 n 626 -1.574 t -5.64. Best MO lay Q 2 6 s n 636 +0.657 t 1.10 h1 +1.152 h2 +0.162, 7% of it on the goal row, resolved +0.454. Results are noisy: goal row and 1.03 differ on 4 of 50, and only 54 of 650 games had a goal row, so the size of the back's loss is not exact; OU25 only 29-56 entries, no read, item 386 reads it; jobs/499_tick_touch_clean.sh (reports/finder_2026-11-07_item384.md) — ")
q = open('watchman/FINDER_QUEUE.md').read()
q, n = re.subn(r"\n385\. RUNNING 2026-11-07 — ", lambda m: "\n" + RES, q)
assert n == 1
RULE = ("386. RUNNING 2026-11-07 — (Finder's own, source a; tables stream_ticks, liq_sample, Railway goal_timeline; job 499_tick_touch_ou25; from item 385, whose OU25 lines had 33-56 entries because the goal row covers 8% of games) "
        "**First in-play touch on football OU25, settled from the market.** Rule fixed now, entries and costs exactly as item 385's OU25, 20 lines; only the result changes: Under won if Under's last OPEN back is at or under 1.03; Over won if the OU25 market's last OPEN tick is 5 minutes or more before that game's MO last OPEN tick, as a market won by Over closes at the third goal; anything else not scored, counted. Games joined by liq_sample event name and first-seen date. Agreement with the goal row printed; below 95% or under 30 checked, the line is not a read. Standard bar, t by game; same 5 days, so a pass earns an unseen re-read, not a stake.")
if '\n386. ' not in q:
    q = q.rstrip('\n') + '\n' + RULE + '\n'
open('watchman/FINDER_QUEUE.md', 'w').write(q)
print('ok')
