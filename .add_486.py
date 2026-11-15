p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n486. ' not in s
item = ("486. RUNNING 2026-11-09 (claimed about 07:50 UTC, lane default/top; every queue TODO is gated on data or a date this morning; "
"Finder's own, data-led per the COO decision of 9 Nov (fair-price map residuals); checked: queue, HYPOTHESES and jobs for calib + unseen, none; "
"tables fair_price_calib (built 8 Nov 21:03-21:10 UTC), fair_price_passed, bf_hist_other_files.loaded_at, bf_hist_other, bf_hist_result; "
"job 499_calib_unseen, new, engine copied from /root/pe-sports/team/fairprice_v0.py) "
"**The pre-off fair-price map (H1) and bookie v2's passed cells, scored on football markets the map never saw: files loaded after the map was built.** "
"Rationale: the map's IS/OOS halves were cut from the same months it was fitted on; the loader has since added about 167,000 files "
"(Sep 2022 59.7k, Aug 2022 55.5k, Jul, Jun and May 2022), each stamped with loaded_at and named by market id, so 'unseen' is exact. "
"Bookie v2 (paper, 538) quotes only on fair_price_passed cells, so this is the first out-of-time check on the cells a running bot uses. "
"Rule fixed now, before any unseen price is read: snapshot both tables first (the map rebuilds nightly and would swallow these months); "
"Soccer markets whose file loaded after max(built_at) and before the job's start; fairprice_v0's filters unchanged (complete books, "
"overround 0.95-1.25, one official winner, p normalised, same 18 bands, multi-line types out); side per cell = toward the IS fair rate; "
"last pre-off LTP one tick adverse, £10 stake or liability, 2% on profit, held to the official result. "
"PRIMARY: PASSED pooled (every runner in a fair_price_passed H1 cell, the cell's side), standard bar, t also by market (sum per market), "
"halves by unseen date median. Lines: each passed cell, each map cell n_is>=300; random-side control; edge in points unseen v edge_is; "
"reading only: same at the print with no tick (the bot is a maker).")
s = s.rstrip('\n') + '\n' + item + '\n'
open(p, 'w').write(s)
print('ok')
