p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n459. ' not in s
item = ("459. RUNNING 2026-11-08 (lane A, 14:25 UTC) (Finder's own, source c structural; tables bf_hist_other, bf_hist_result; "
"job 499_ht_break_drift, from jobs/499_ht_state_lines.sh) **Trade across the half-time break: enter at the first print after the whistle, "
"out at the last print before the restart, no result exposure.** Rationale: no game time passes during the break, so a fair price should not move, "
"but money arrives in the break (punters watching the scores) and nobody has read whether it pushes MO or OU2.5 one way; every half-time read so far "
"(items 409, 410, 420, 446, 447) held to the result. Rule fixed before any price is read: half-time = last in-play print on HALF_TIME and "
"FIRST_HALF_GOALS markets, 46-60 min after the first in-play print, with 3+ such prints in the 5 min before it (so a thin book stopping is not read as the whistle); "
"entry = first MO or OU2.5 print 1-4 min after half-time, filled at the worse of it and the next within 120 s; exit = last print 3+ min after entry and "
"no later than half-time + 12 min; one tick adverse each side, GBP 10 stake or liability, 2% on profit, out by the hedge (no result). "
"State from the official HALF_TIME_SCORE: S00, LEVEL (1-1 up), LEAD1, LEAD2+; MO roles LEADER, TRAILER, DRAW (HOME, AWAY, DRAW when level); "
"OU2.5 OVER, UNDER (only where 2.5 is not passed at half-time); back and lay; 40 scored lines, one trade per game per line; women and youth out; "
"halves by date median; standard bar. Months Nov 2022 to Sep 2026 as loaded (Nov 2022 part-loaded, Nov 2024 to Apr 2026 LISTFAIL read as no rows). "
"Prints only, so a pass earns a real-touch read on liq_sample, not a stake.\n")
if not s.endswith('\n'): s += '\n'
open(p, 'w').write(s + item)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
if not t.endswith('\n'): t += '\n'
t += "2026-11-08 | c structural (bf_hist_other, bf_hist_result) | trade MO and OU2.5 across the half-time break, first print after the whistle to the last before the restart, by HT state (499_ht_break_drift, item 459) | RUNNING | -\n"
open(h, 'w').write(t)
print('ok')
