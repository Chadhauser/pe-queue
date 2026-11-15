p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n').split('\n')
assert not any(l.startswith('380. ') for l in t)
t.append("380. RUNNING 2026-11-07 (Finder's own, source a, from items 372, 379; tables stream_ticks, racing_results; job 499_tick_touch_level; a grep of jobs finds racing on stream_ticks read before the off only)**A horse's first in-play touch of a level, tick by tick.** Rationale: item 379's frames are about 34 s apart in a race, so it could not read the idea; stream_ticks holds every tick for about 35 races a day. Rule fixed before any price is scored: as item 379, first in-play tick with back_px <= Q after a tick above it, Q in 3, 2, 1.5, 1.3, 1.2, 1.1, fill at the runner's first tick at least 1 s, or 3 s, later with a touch on that side, back at back_px or lay at lay_px, one tick adverse, 2%, £10, one winner on racing_results. Lines ALL and MOVE, by delay. Halves by date median, standard bar on the t by race. A pass still rests on a thin book, sizes not read here.")
open(p, 'w').write('\n'.join(t) + '\n')
print('ok')
