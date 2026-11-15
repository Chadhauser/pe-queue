Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read()
assert '\n463. ' not in q
item = ("463. RUNNING 2026-11-08 (lane A, 16:55 UTC; Finder's own, source a biggest predictable moves, breadth door of item 325 which read coach_path at "
"15-min rows on 1,581 games, n 229; every queue TODO is gated on data or a date tonight; tables bf_hist_other, bf_hist_result; job 499_nogoal_move, new, "
"from jobs/499_ht_break_drift.sh) **A Match Odds side that shortens 2-10 implied points in five minutes at 0-0, with no goal: follow or fade, on the "
"full print tape.** Rationale: at 0-0 both sides drift every minute as the Draw shortens, so a side that shortens with the score unchanged was moved by "
"something on the pitch (red card, pressure, injury); item 325 found the touch fades it on 229 trades (SHORT lay next row -0.632 t -3.16, back -0.570), "
"too few and too coarse; the 1-min print tape holds about 40,000 games. Rule fixed now, before any MO price is read: first MO market per game, senior men "
"(women and youth out), official MO result; ip0 = first in-play MO print; windows E = 25, 40, 70, 85 min after ip0 (wall clock, about match minutes 25, "
"40, 55, 70); t1 = ip0+E, t0 = t1-5 min; for HOME and AWAY, p0 = last print in [t0-60 s, t0], p1 = last print in [t1-60 s, t1], both needed (no forward "
"fill); D = 1/p1 - 1/p0; SH2 = 0.02 <= D < 0.04, SH4 = 0.04 <= D < 0.10 (10+ points is a goal), DR = D <= -0.04 and FLAT = |D| < 0.01 for reading; "
"no-goal guard: an Over 0.5 print above 1.05 in [t0, t1] and no Over 0.5 print at 1.05 or under at or before the entry print, a game with no in-play "
"OU0.5 print is dropped and counted; entry = the runner's first print in (t1, t1+120 s], worse of it and the next within 120 s, one tick adverse, prices "
"1.01-50; exits: HEDGE = out at the runner's last print in [entry+8 min, entry+12 min], one tick adverse, 2% on a green profit, settled at the official "
"result if no print there (never dropped); HOLD = to the official MO result; GBP 10 stake or liability. One entry per game per window per runner. Scored: "
"SH2 and SH4 x 4 windows x back/lay x HEDGE/HOLD = 32 lines, halves by date median, standard bar; windows pooled (correlated) and DR/FLAT controls "
"printed for reading only. Months Nov 2022 to Oct 2026 as loaded (Nov 2024 to Apr 2026 LISTFAIL read as no rows). Prints only, so a pass earns a "
"real-touch read on liq_sample, not a stake.")
q = q.rstrip('\n') + '\n' + item + '\n'
open(Q, 'w').write(q)
h = open(H).read().rstrip('\n') + '\n' + ("2026-11-08 | a moves (bf_hist_other, bf_hist_result, from 325) | MO side shortening 2-10 points in 5 min at 0-0 "
"with no goal, follow or fade, hedge out 10 min or hold (499_nogoal_move, item 463) | RUNNING | -") + '\n'
open(H, 'w').write(h)
print('ok')
