p = 'watchman/FINDER_QUEUE.md'
t = open(p).read()
assert '\n403. ' not in t
item = ("403. RUNNING 2026-11-07 (Finder's own, source a, from items 84 and 86; tables af_events, af_fixtures, bf_hist_other, season 2023 not read by item 84; job 499_goal_type_unseen) "
        "**Back Over 2.5 after a missed penalty, on games item 84 never read.** Rationale: item 84, MISSED_PEN Over back settle E5 n 227 +3.246 t 1.69, nearly all 2024, parked by item 86 because af_events lost the 2025 rows; season 2023 now has a tape, so the door opens without any re-pull if its rows are there. "
        "Rule fixed now, no new cuts: first missed penalty of the game at minute 85 or before, under three goals by then, games not in af_price_map, Aug 2023 to Sep 2026; first print match minute c+5 to c+7, second half +19 on the clock, worse of it and the next within 120 s, one tick adverse, held to the result, 2%, £10. Standard bar, halves by date; a pass earns a real-touch read on liq_sample, not a stake.")
open(p, 'w').write(t.rstrip('\n') + '\n' + item + '\n')
print('added')
