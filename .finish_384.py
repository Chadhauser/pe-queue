import os, re
q = open('watchman/FINDER_QUEUE.md').read()
RES = ("388. DONE 2026-11-07 — the lead holds, cannot pass, same races. Item 380's lines reproduce exactly; with a real book at the signal Q 1.1 back 1 s n 97 +0.565 t by race 4.82 h1 +0.459 h2 +0.668, 1 loser; Q 1.2 n 120 +1.088 t 5.44 h1 +1.205 h2 +0.970, 5 losers; 3 s Q 1.1 n 57 +0.445 t 2.24, Q 1.2 n 101 +0.681 t 2.56; jobs/499_tick_touch_racing_clean.sh (reports/finder_2026-11-07_item384.md) — ")
q, n = re.subn(r"\n388\. RUNNING 2026-11-07 — ", lambda m: "\n" + RES, q)
assert n == 1
old = "382. TODO (needs data — the stream restarted first: its market list has been frozen since 21:20 UTC 6 Nov, Peter's yes outstanding, so no new race reaches stream_ticks and the dates here move day for day until it is fixed; then stream_ticks racing after 7 Nov 09:00 UTC,"
new = "382. TODO (UPDATE 2026-11-07: stream back since 08:37 UTC, Watchman report 2026-11-07_11, so no longer blocked; item 388 kept the lead with a real book at the signal, the rule here is unchanged) (needs data — stream_ticks racing after 7 Nov 09:00 UTC,"
assert old in q
q = q.replace(old, new, 1)
q = q.replace("had 33-56 entries because the goal row covers 8% of games", "had 29-56 entries because the goal row covers 8% of games", 1)
open('watchman/FINDER_QUEUE.md', 'w').write(q)
LED = [
 "2026-11-07 | a (stream_ticks) | first in-play touch, football MO and OU25, tennis MO (499_tick_touch_other, item 384) | DONE | nothing passes; 0 of 60; tennis Q 1.1 back n 606 -0.487 t -2.52; football signal junk, no read",
 "2026-11-07 | a (stream_ticks, goal_timeline) | first touch, football, real book at the signal (499_tick_touch_clean, item 385) | DONE | nothing passes; 0 of 40; MO Q 1.1 back n 590 -0.526 t -3.65; OU25 too few results",
 "2026-11-07 | a (stream_ticks, goal_timeline) | first touch, OU25, result from the market (499_tick_touch_ou25, item 386) | DONE, struck | 2 numeric passes, Q 1.1 back n 340 +0.407 t 3.86, struck: late third goals dropped",
 "2026-11-07 | a (stream_ticks, liq_sample CS) | first touch, football, settled from correct score (499_tick_touch_cs, item 387) | DONE | nothing passes; 0 of 40; OU25 Q 1.1 back +0.087 t 0.59 n 326; 18.5% unresolved",
 "2026-11-07 | a (stream_ticks, racing_results) | item 380's lines with a real book at the signal (499_tick_touch_racing_clean, item 388) | DONE | lead holds, same races; Q 1.1 n 97 +0.565 t 4.82; Q 1.2 n 120 +1.088 t 5.44",
 "2026-11-07 | a (stream_ticks, racing_bsp, from 499_tick_touch_level) | first touch on the racing place market, rule fixed | TODO (item 389, needs the recorder) | -",
]
h = open('watchman/HYPOTHESES.md').read().rstrip('\n')
if 'item 384)' not in h:
    h += '\n' + '\n'.join(LED) + '\n'
    open('watchman/HYPOTHESES.md', 'w').write(h)
for s in ('other', 'clean', 'ou25', 'cs', 'racing_clean'):
    a, b = f'jobs/499_tick_touch_{s}.sh.wip', f'jobs/499_tick_touch_{s}.sh'
    assert not os.path.exists(b), b
    os.rename(a, b)
print('ok')
