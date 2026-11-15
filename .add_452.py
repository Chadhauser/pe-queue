p = 'watchman/FINDER_QUEUE.md'
t = open(p).read()
assert '\n452. ' not in t
item = ("452. RUNNING 2026-11-08 (lane A; Finder's own, source a/c, from items 446 and 113; checked 8 Nov: HYPOTHESES.md and queue for 4.5, OU45, goal-fest, high-scoring, three goals, and job names; grid v2-v4 stop at OU3.5, item 446 read OU4.5 at the break only, item 113 on Sep 2026 only; "
        "tables bf_hist_other, bf_hist_result; job 499_four_goal_under, new, from jobs/499_ht_state_thin.sh) "
        "**Back or lay Under 4.5 late in a game that already holds four goals.** Rationale: in an open game the crowd may extrapolate the goal rate and overprice a fifth goal (Under too long), or the opposite; "
        "item 446 found the next line fair at the break (Under won v implied within 1-4 points), but no read has held a four-goal game late on the full tape. "
        "Rule fixed now, before any OU4.5 price is read: state G4 = OU3.5 Over printed at 1.05 or under 3+ min before entry and OU4.5 Over not at 1.05 or under before entry; "
        "entry = the first Under 4.5 print from E to E+3 min after the first in-play OU print, E = 60, 70, 80 (each window scored apart, one entry per game per window); "
        "back at the worse of the print and the next within 120 s, lay likewise, one tick adverse, GBP 10 stake or liability, 2%, prices over 50 not traded; "
        "official bf_hist_result OU4.5 winner, never dropped for an early settle; women and youth out; months Jan 2023 to Oct 2026 as the loader holds them; "
        "halves by date median; standard bar. Six scored lines (E x back/lay); pre-off OU2.5 band (LOW/MID/HIGH) and G3 Under 3.5 (a grid state, a control) printed for reading only.\n")
t = t.rstrip('\n') + '\n' + item
open(p, 'w').write(t)
h = 'watchman/HYPOTHESES.md'
s = open(h).read().rstrip('\n') + '\n'
s += "2026-11-08 | a/c (bf_hist_other, bf_hist_result, from 446, 113) | back or lay Under 4.5 late (60/70/80 min) in a game already holding four goals, full tape (499_four_goal_under, item 452) | RUNNING | -\n"
open(h, 'w').write(s)
print('added 452')
