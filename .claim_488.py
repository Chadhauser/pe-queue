p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n488. ' not in s, 'item 488 exists'
item = ("488. RUNNING 2026-11-09 (claimed about 08:30 UTC, lane default/top; every other TODO is gated on data or a date and 487 is RUNNING in another run; "
"Finder's own, data-led per the COO decision of 9 Nov (fair-price map residuals, the in-play calibration table); checked: queue, HYPOTHESES and jobs for "
"calib_inplay, only 525 (the builder), 538 and 543 (bookie readers), 533, none score it on unseen markets; tables fair_price_calib_inplay (built 8 Nov "
"09:21-09:26 UTC), bf_hist_other_files.loaded_at, bf_hist_other, bf_hist_result; job 499_inplay_map_unseen, new, engine from jobs/525_h1b_inplay.sh and "
"jobs/499_calib_unseen.sh) **The in-play fair-price map (H1b) scored on football markets it never saw, trading only at a fresh book and entering at the "
"next real print.** Rationale: item 486 scored the pre-off map out of time and found stale closes carry its tail cells; the in-play map (928 cells n_is>=300) "
"has never been scored out of time, and its price is the last print in a 15-min band however old, which may be pre-goal. Rule fixed now, before any unseen "
"price is read: snapshot the map; Soccer markets whose file loaded after its max(built_at) and before the job's start, not loaded earlier; at each band end "
"T = market_time + 16/31/46/61/76/91 min, each runner's last in-play print in [T-5 min, T); complete book (every runner with an official WINNER/LOSER priced), "
">=2 runners, raw book 0.90-1.30, exactly one winner; p normalised, cell = type@band x the map's 18 bands; side toward the IS rate; ENTRY at the runner's "
"first print in [T, T+3 min) one tick adverse (no print, no trade, count and won-rate of these printed); back £10 stake, lay £10 liability, 2% on profit, "
"held to the official result. PRIMARY: PASSED pooled (job 538's rule on the snapshot: n_is>=300, n_oos>=100, same sign IS/OOS, |e_is|>=0.01, |e_oos|>=0.005); "
"standard bar with t on per-GAME sums (event_id), t per market and per trade also printed; halves by unseen market_time median. Lines: each passed cell, top 15 "
"cells n_is>=300 by t_game; random-side control; reading only: the map's own engine (last print in band, no freshness, enter at it), and the share of entries "
"whose cell print is over 5 min old.\n")
if not s.endswith('\n'):
    s += '\n'
s += item
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
if '488' not in t[-3000:]:
    if not t.endswith('\n'):
        t += '\n'
    t += "- 2026-11-09 | item 488 | in-play fair-price map (fair_price_calib_inplay) on unseen markets, fresh book, next-print entry | RUNNING\n"
    open(h, 'w').write(t)
print('ok')
