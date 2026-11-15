Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
item = ("446. RUNNING 2026-11-08 (Finder's own, source a/c; tables bf_hist_other, bf_hist_result; job 499_ht_state_lines, new) "
"**At the break, hold the goal line one and two goals above the half-time score to the result.** Rationale: every queue item is waiting on data tonight; "
"item 296 traded across the break and out, item 408 read same-bet pairs at the break, grid v4 read 45-minute states on bf_hist_price (Aug 2024 to Jun 2026, no OU4.5); "
"no read has held OU G+0.5 and G+1.5 to the official result by half-time goal total G on the print tape from Mar 2023, with OU4.5 in it. "
"Rule fixed now, before any OU price is read: G = goals in the official HALF_TIME_SCORE (Any unquoted out, women and youth out); "
"half-time = last print of HALF_TIME, FIRST_HALF_GOALS_05/15/25 and HALF_TIME_SCORE, must be at least 46 min after the first in-play print of the game; "
"entry = first print of the line at least 2 min after half-time, at least 55 min after the first in-play print, at most 13 min after half-time; "
"for G >= 1 the Over (G-0.5) must have printed at 1.05 or under before entry (the G-th goal was seen); fill at the worse of the print and the next within 120 s, one tick adverse, "
"GBP 10 stake or liability, 2% on profit, prices over 50 not traded, official OU result, never dropped. "
"Lines: N1 = OU(G+0.5), N2 = OU(G+1.5), G 0-4, back Under and lay Under, one bet a game a line; by pre-off OU2.5 Over band (LOW over 2.2, MID 1.7-2.2, HIGH under 1.7) and HT level or not. "
"Halves by date median; standard bar. Printed, not scored: entry at least 60 min after the first in-play print, as a timing check.\n")
s = open(Q).read()
assert '\n446.' not in s
if not s.endswith('\n'):
    s += '\n'
open(Q, 'w').write(s + item)
h = open(H).read()
if not h.endswith('\n'):
    h += '\n'
open(H, 'w').write(h + "2026-11-08 | a/c (bf_hist_other, bf_hist_result) | at the break, hold OU G+0.5 and G+1.5 to the result by half-time goal total G, OU4.5 included (499_ht_state_lines, item 446) | RUNNING | -\n")
print('ok')
