p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "488. RUNNING 2026-11-09 (claimed about 08:30 UTC,"
assert s.count(old) == 1
new = ("488. DONE 2026-11-09 — nothing passes; FRESH PASSED ALL (380 passed cells, fresh book, entry at the next print one tick adverse) n 228,089 on "
"86,235 unseen markets, 17,674 games, -0.112 per £10, t_game -5.15, h1 -0.115 h2 -0.108, at the print with no tick -0.035, so the map is fair at a "
"tradable price; 82 of 221 passed cells positive, best OU4.5@m5 p0.06-0.10 LAY n 550 +0.284 t 2.60; the map's OWN engine (last print in band, entered "
"at it) reads +0.677 t_game 43.2 on the same cells, all from old prints (>5 min old +2.101 n 127,730; <=5 min +0.173), so its in-play cells are a stale-"
"print artefact and bookie v2 should not quote off fair_price_calib_inplay; 284,791 unseen Soccer markets, Apr 2022-Jan 2023, loaded after 8 Nov 09:26 UTC; "
"jobs/499_inplay_map_unseen.sh, reports/finder_2026-11-09_items488-489.md (claimed about 08:30 UTC,")
s = s.replace(old, new)
assert '\n489. ' not in s
item = ("489. RUNNING 2026-11-09 (claimed about 08:35 UTC, same run as 488; next door of item 488, maker side, which is how bookie v2 trades; Finder's own, "
"data-led, fair-price map residuals; tables as 488, finder_ipcal_snap_1109, finder_ipunseen_mk_1109; job 499_inplay_map_maker, new, from "
"jobs/499_inplay_map_unseen.sh) **The in-play map's passed cells as a RESTING order at the fresh cell price, filled only when a later print trades "
"through it.** Rationale: item 488's taker loses -0.112 but at the print with no tick it is -0.035, so the spread is most of the cost; a maker earns "
"the tick but meets adverse selection, and only real fills can say which wins. Rule fixed now, before any price is read: 488's fresh book and cells "
"unchanged; at T rest a BACK (or LAY, the cell's side) at the runner's last print P in [T-5, T); FILLED only if a print in [T, T+3 min) is strictly "
"above P for a back, strictly below P for a lay (trade-through, as the queue may not reach us at P); fill at P, no tick; back £10 stake, lay £10 "
"liability, 2% on profit, official result; unfilled = no trade, fill rate and the unfilled won-rate printed. PRIMARY: PASSED pooled, bar with t on "
"per-GAME sums, halves by market_time median; lines: per side, per band, every cell n>=300 top 15 by t_game; random-side control on the same fill rule.\n")
s = s.rstrip('\n') + '\n' + item
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
o2 = "in-play fair-price map (fair_price_calib_inplay) on unseen markets, fresh book, next-print entry (488) | RUNNING | "
assert t.count(o2) == 1
t = t.replace(o2, "in-play fair-price map (fair_price_calib_inplay) on unseen markets, fresh book, next-print entry (488) | DONE | nothing passes; passed n 228,089 -0.112 t_game -5.15 both halves negative; map's own engine +0.677 is stale prints")
t = t.rstrip('\n') + "\n2026-11-09 | data-led map | in-play map passed cells as a resting order at the fresh cell price, trade-through fills (489) | RUNNING | \n"
open(h, 'w').write(t)
print('ok')
