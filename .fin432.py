p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "432. RUNNING 2026-11-07 (lane A; "
assert s.count(old) == 1
s = s.replace(old, "432. DONE 2026-11-07 — nothing passes; PRICED DRAW back n 335 -0.104 t -0.23 h1 +0.338 h2 -0.581; NOT_PRICED +4.277 t 3.64 n 227 is prints the equaliser had not yet moved, a clock artefact; jobs/499_equaliser_draw_unseen.sh (reports/finder_2026-11-07_item430.md) — (lane A; ", 1)
assert '\n433. ' not in s
s = s.rstrip('\n') + '\n' + ("433. TODO (from 8 Nov; Finder's own, source d, from items 430-432; tables af_events, bf_hist_price, bf_hist_other; jobs 499_goal_type, 499_let_off, 499_var_off_unseen, 499_goal_timing unchanged except the guard) "
    "**A priced-in guard on every older lead that enters on an af goal minute.** "
    "Rationale: tonight the profit on af-minute entries sat in prints the goal had not yet moved: item 430 FIRST lay +0.664 t 3.52 fell to +0.237 t 1.53 without the top 1%, entries under 2.0 won 0.344 v implied 0.570; item 432 NOT_PRICED Draw back +4.277 t 3.64 v PRICED -0.104. "
    "Older near misses built the same way may be the same artefact: item 179 PEN OTHER back n 565 +4.948 t 1.64 (one 1,068 win), item 84 VAR_GOAL_OFF lay n 348 +0.759, item 130 CL_SAME TRAIL lay +0.128. "
    "Rule fixed now: re-run each job unchanged, adding only a split by whether the entry print has moved at least 20% from the runner's last print in the 6 match minutes before the event, in the direction the event should move it; a lead whose profit is only in the unmoved prints is struck and its queue line marked so. Not a money line itself; it stops the next goal-entry lead fooling us.") + '\n'
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old_h = "2026-11-07 | a (bf_hist_other, af_events, from 430) | lay the first scorer once a second-half equaliser is priced in, unseen games, rule fixed | TODO (item 431, from 8 Nov) | -\n"
assert t.count(old_h) == 1
t = t.replace(old_h, "2026-11-07 | a (bf_hist_other, af_events, from 430) | lay the first scorer once a second-half equaliser is priced in, unseen games (499_equaliser_unseen, item 431) | DONE | nothing passes; PRICED n 960 +0.184 t 1.06, less top 1% +0.084\n")
t = t.rstrip('\n') + '\n'
t += "2026-11-07 | a (bf_hist_other, af_events, from 430) | back the Draw after a 66-80 equaliser to 1-1, unseen games (499_equaliser_draw_unseen, item 432) | DONE | nothing passes; PRICED n 335 -0.104 t -0.23; NOT_PRICED +4.277 t 3.64 is unmoved prints\n"
t += "2026-11-07 | d (af_events, bf_hist_price, bf_hist_other, from 430-432) | priced-in guard on older af-minute goal-entry leads (items 179, 84, 130) | TODO (item 433, from 8 Nov) | -\n"
open(h, 'w').write(t)
print('ok')
