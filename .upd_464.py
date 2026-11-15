Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read()
old = "464. RUNNING 2026-11-08 (lane A, 16:58 UTC;"
assert q.count(old) == 1
new = ("464. DONE 2026-11-08 — nothing passes; 0 of 32; 16,257 UNSEEN trades on 10,412 games; best n>=300 SH2 E25 lay HOLD n 390 +0.122 t 0.29; "
"lean SH4 E85 back HOLD n 30 +6.051 t 2.00 h1 +5.826 h2 +6.277, won 0.533 v 0.318 implied, positive each year, mirror lay -3.710 t -2.91, liquid "
"books (item 463) n 10 -0.111, so thin books only, sent to item 465; jobs/499_nogoal_move_wide.sh, reports/finder_2026-11-08_items463-464.md (lane A, 16:58 UTC;")
q = q.replace(old, new)
assert '\n465. ' not in q
item = ("465. TODO (re-check 12 Nov 2026 as Soccer Oct 2022 and older months load, then each month; Finder's own, source a, from item 464's lean; tables "
"bf_hist_other, bf_hist_result, af_events (reading only); job 499_thin_shorten_unseen to write from jobs/499_nogoal_move_wide.sh) **Back a Match "
"Odds side that shortens 4-10 implied points in 5 min at 0-0 with no goal, in a thin book, to the result, on months no read has used.** Rationale: "
"item 464, books with no MO print in the 60 s before t0 or t1, SH4 E85 back HOLD n 30 +6.051 t 2.00 (h1 +5.826 h2 +6.277), won 0.533 v 0.318 "
"implied; all windows pooled n 122 +2.368 t 1.57; in liquid books (item 463) n 10 -0.111, so it lives in thin books; best of 32 after a second look, "
"so expect it to shrink. Rule fixed now: item 464's code unchanged (180 s slots, not priced at 60 s, guard, entry, costs, official result, never "
"dropped), class SH4 only, back HOLD, all four windows, ONE bet a game (the earliest qualifying window), scored only on markets before 2022-11-01; "
"standard bar, halves by date; printed for reading: E85 alone, and the share with an af_events red card to the other side in the 10 min before t1 "
"where the game maps. About 4 trades a month at item 464's rate, so n 300 needs about 75 older months, which the loader may never reach on prints, so the job's real use is whether the sign holds: read each block as it loads and say n each time.")
q = q.rstrip('\n') + '\n' + item + '\n'
open(Q, 'w').write(q)
h = open(H).read()
oh = "prints from the last 180 s (499_nogoal_move_wide, item 464) | RUNNING | -"
assert h.count(oh) == 1
h = h.replace(oh, "prints from the last 180 s (499_nogoal_move_wide, item 464) | DONE | nothing passes; 0 of 32; lean SH4 E85 back HOLD n 30 "
"+6.051 t 2.00 both halves positive, thin books only")
h = h.rstrip('\n') + '\n' + ("2026-11-08 | a moves (bf_hist_other, bf_hist_result, from 464) | back a thin-book side shortening 4-10 points in 5 min "
"at 0-0, no goal, to the result, months before Nov 2022 (item 465) | TODO (re-check 12 Nov) | item 464 SH4 E85 n 30 +6.051 t 2.00") + '\n'
open(H, 'w').write(h)
print('ok')
