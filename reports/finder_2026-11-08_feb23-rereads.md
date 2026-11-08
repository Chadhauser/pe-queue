# Finder 2026-11-08: February 2023 re-reads of eight leads (items 342, 352, 406, 420-423, 435)

Money: £0 this month; no line passes the bar tonight. Tier one (trading).
Data health (local DB, bf_hist_months): Soccer 2023-02 DONE 06:22 UTC 8 Nov, 51,782 of 51,782 files, earlier than the 12 Nov estimate; 2023-03 and 2023-04 DONE. Item 445 (also opened by Feb 2023) is the other lane's, untouched.

Job: jobs/499_feb23_rereads.sh, each lead's job unchanged except the date window (the window text is asserted to exist before it is swapped, as in jobs/499_mar23_rereads.sh), then items 422/423 read Feb to May 2023 in one read. Read only, 6 min total, exit 0. Tables: bf_hist_other, bf_hist_result, af_fixtures, af_events.

| item | scored line | Feb 2023 | earlier unseen reads | status |
|---|---|---|---|---|
| 422 | jump-up ONE E1 (item 414's signal) | **Feb-May pooled n 647 (647 games) -0.245 t -0.43, h1 -0.183, h2 -0.307, won 0.366 v 0.360** | Mar-May n 515 +0.220 | scored at n >= 300: fails |
| 423 | jump-up ONE D5 (entry 5 min later) | **Feb-May pooled n 538 -0.197 t -0.30, h1 +0.090, h2 -0.484** | Mar-May n 438 +0.187 | scored at n >= 300: fails |
| 420 | HT/FT G2 CHEAP back | n 31 -0.837 t -0.38 | Mar n 26 -0.364, Apr n 28 +1.227, May n 32 -2.235 | four months n 117, under the bar |
| 421 | YOUTH G1 O2.5 lay | n 29 -3.302 t -1.73 | Mar n 28 -1.121, Apr n 21 +0.445, May n 13 +2.316 | n 91, three of four flat or negative |
| 406 | RULE G0 Y4 O2.5 back | n 9 -5.949 (less top win -10.000) | Mar n 14 -10.000, Apr n 16 -0.910 | n 48 over four reads, all negative |
| 435 | PEN conceder back MOVED | n 34 -1.796 t -0.32, h1 -6.558, h2 +2.436 | Mar n 29 -5.525 | negative again, not pooled with 433/434 |
| 342 | FOUL_HIGH Draw back | n 0 (no game has five earlier games that season) | Mar n 0 | job then raised KeyError on the empty table; caught, result is n 0 |
| 352 | BOTH home lay / RALLY <2 lay | n 1 +13.067 / n 0 | Mar n 0 / n 1 | |

Jump-up Feb-May lines printed, not scored: FAV E1 n 261 +0.686 t 1.07 (h1 +0.437, h2 +0.938, won 0.548 v 0.517); OUT E1 n 190 -0.975; DRAW E1 n 196 -0.777; D15 n 524 +0.103. Controls: DOWN 2-4 back D10 n 527 -1.796 t -3.17 (h1 -1.976, h2 -1.616); FLAT DRAW back D5 n 3,654 -0.907 t -3.31.

Verdict: nothing passes. Item 414's jump-up back, +1.321 on the 1,500 games whose months chose it, reads -0.245 on 647 games of four months no read chose: the signal print is priced fair (won 0.366 v 0.360). Items 422 and 423 are scored and closed. What it still supports is the favourite leg, positive in both halves on the unseen months (n 261 +0.686), filed as item 451 to be scored only on months before Feb 2023. The jump-up family has now had three doors (414 signal unseen, 444 OU25, 423 delayed entry) and every scored line is flat; this is a drop of the signal as a back, with the FAV leg and the shortened-at-the-off lay (item 445, the other lane's; tonight's DOWN 2-4 control at t -3.17 on unseen months points the same way) the two doors left. Items 420, 421, 406, 435, 342, 352 stay TODO, re-check 14 Nov as Jan 2023 and older load.

## Sceptical review (problems found, and what was done)
1. Item 342's job crashes on zero trades (`sort_values` on a frame with no `t` column). Not a window fault; Mar read n 0 as well. Left unfixed, as the job is shared; noted in the queue so a later read isn't mistaken for a code error.
2. FAV E1 is one of six printed jump-up lines, chosen after seeing them; item 451 is post hoc and is scored only on months no read has used, with the rule fixed in the queue first.
3. The 422 pool overlaps the Mar-May read (515 of 647 games) by design: it is one computed read, not a new independent sample; the new games are Feb's 132.
4. Item 406's four reads add to n 48: at about 12 a month it cannot reach n 300 for about two more years of older data; said in the queue.
5. Item 421's table shows a senior control G0 OU1.5 back n 559 +0.879 t 1.59; item 446 already reads that state on all months, so not filed again.

Scratch files, untracked, not committed: .q1108.py, .q1108b.py, .q1108c.py, .claim_feb23.py, .feb23chk.py, .chk_feb23.py, .maxitem.py, .cols1108.py, .mt1108.py, .fin_feb23.py.
