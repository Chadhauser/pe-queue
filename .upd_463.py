Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read()
old = "463. RUNNING 2026-11-08 (lane A, 16:55 UTC;"
assert q.count(old) == 1
new = ("463. DONE 2026-11-08 — nothing passes; 0 of 32; 10,717 trades on 7,248 games (of 50,664 read), SH2 n 451, SH4 n 72, too rare; best n>=300 "
"SH2 E25 back HEDGE n 310 -0.259 t -1.00; shortened sides won 0.339 v 0.350 implied (a slight overreaction), but the fade lay HEDGE n 449 -0.454 "
"t -3.50 pays the ticks; FLAT lay HOLD n 8,280 +0.014, MO prints fair at 0-0; 86% of game-windows have no MO print in a 60 s slot at t0 or t1, "
"so item 464 reads those; jobs/499_nogoal_move.sh, reports/finder_2026-11-08_items463-464.md (lane A, 16:41 UTC;")
q = q.replace(old, new)
assert '\n464. ' not in q
item = ("464. RUNNING 2026-11-08 (lane A, 16:58 UTC; Finder's own, source a, second door of item 463 on the windows it could not read; tables "
"bf_hist_other, bf_hist_result; job 499_nogoal_move_wide, item 463's code with one change) **Item 463's 0-0 no-goal shortening on the game-windows "
"463 could not price: the t0 and t1 prints taken from the last 180 s, not 60 s.** Rationale: item 463 dropped 72,000-79,000 game-windows a window for "
"no MO print in the 60 s before t0 or t1, so it read the liquid games only (7,248 of 50,664); a thinner book may react more slowly to whatever "
"moved it. Rule fixed now, before any price: item 463 unchanged (classes, guard, entry, HEDGE and HOLD exits, settlement, costs, one per game per "
"window per runner) except p0, p1 = last print in [t0-180 s, t0], [t1-180 s, t1]; scored ONLY on windows where item 463 found no 60 s print at t0 "
"or t1 (UNSEEN); the same 32 lines, standard bar, halves by date median; ALL windows at 180 s printed for reading, not scored.")
q = q.rstrip('\n') + '\n' + item + '\n'
open(Q, 'w').write(q)
h = open(H).read()
oh = "with no goal, follow or fade, hedge out 10 min or hold (499_nogoal_move, item 463) | RUNNING | -"
assert h.count(oh) == 1
h = h.replace(oh, "with no goal, follow or fade, hedge out 10 min or hold (499_nogoal_move, item 463) | DONE | nothing passes; 0 of 32; "
"SH2 n 451, SH4 n 72; best n>=300 SH2 E25 back HEDGE -0.259 t -1.00; fade lay HEDGE pooled -0.454 t -3.50; 86% of windows unpriced at 60 s")
h = h.rstrip('\n') + '\n' + ("2026-11-08 | a moves (bf_hist_other, bf_hist_result, from 463) | item 463 on the windows it could not price, "
"prints from the last 180 s (499_nogoal_move_wide, item 464) | RUNNING | -") + '\n'
open(H, 'w').write(h)
print('ok')
