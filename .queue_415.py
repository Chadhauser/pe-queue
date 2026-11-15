p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
item = ("415. RUNNING 2026-11-07 (Finder's own, source a, from item 414; tables stream_ticks, liq_sample, Railway goal_timeline; job 499_jump_up_ticks; pilot, cannot pass) "
        "**Item 414 on the stream: where is the book when that print happens?** Rationale: item 414's prints read ONE E1 n 1,500 +1.321 t 3.21 and +1.795 on Jun-Dec 2023 alone, E2 next print n 833 +1.618, three ticks +1.026, controls negative; but its touch read n 24 -7.819, and a print above the last price is likely a layer hitting the offer, which a taking back cannot reach. "
        "Rule fixed before this job reads a price: football MO on stream_ticks; first print is the first in-play tick within 180 s where runner traded volume rises over its last pre-off tick, pre-off tick within 600 s before the market's first in-play tick; gap 2 to under 4 points; largest gap per market; women and youth out. "
        "Lines, all to one result, one tick adverse, 2%, £10: at the print; back_px on that tick; back_px 3, 6, 10 s on, lapsed on a suspension; rested at the print, filled only if a print within 60 s goes strictly over it. Results as job 499_tick_touch_clean: goal row, else last back at or under 1.03, else last-print odds. "
        "Printed: spread, share of prints at the lay and at the back, back_px against the print. No bar; if taking loses and the print sits at the lay, the taker form closes and only resting stays open.")
assert '\n415. ' not in t
t = t.rstrip('\n') + '\n' + item + '\n'
open(p, 'w').write(t)
print('queued 415')
