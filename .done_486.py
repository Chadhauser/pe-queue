p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "486. RUNNING 2026-11-09 (claimed about 07:50 UTC"
assert s.count(old) == 1
new = ("486. DONE 2026-11-09 — nothing passes; PASSED ALL (job 538's 20 cells, applied to the map snapshot as fair_price_passed does not exist yet) "
"n 8,567 on 6,513 unseen markets +1.101 t 3.93, t by market 3.15, h1 +0.617 h2 +1.489, under the bar; the two OU4.5 tail cells carry it "
"(Under p0.90-1.00 LAY n 1,639 +3.751 t 3.38, Over p0.03-0.06 BACK n 351 +11.629 t 3.22), and the other 18 passed cells are about -0.12 per £10 on n 6,577; "
"12 of 20 cells keep their in-sample sign; MO p0.55-0.60 LAY (a bookie v2 cell) -0.602 n 836 both halves negative; MAP ALL -0.195, at print -0.027, "
"so the map is fair overall; diagnostic: 64.5% of the Over 4.5 tail's last pre-off prints are over 60 min old (Sep 2022 median 1,083 min), "
"fresh prints within 10 min fair (won 0.0833 v 0.0811, n 348), stale won 0.1093 v 0.0665, so the OU4.5 lead is stale closes, sent to item 487; "
"79,380 complete-book markets 30 Apr-30 Sep 2022 loaded after the map's build; jobs/499_calib_unseen.sh, reports/finder_2026-11-09_item486.md "
"(claimed about 07:40 UTC")
s = s.replace(old, new)
assert '\n487. ' not in s
item = ("487. TODO (next door of item 486; Finder's own, data-led, fair-price map residuals; tables bf_hist_other, bf_hist_result, bf_hist_other_files, "
"finder_unseen_mk_1109; job 499_calib_fresh_unseen to write from jobs/499_calib_unseen.sh) "
"**The pre-off fair-price map rebuilt on FRESH closes only (last pre-off print within 10 min of market_time on every runner), fitted on markets loaded before 8 Nov 21:10 UTC, scored on item 486's unseen markets.** "
"Rationale: item 486 found the map's close is the last print however old; on the Over 4.5 tail 64.5% of closes are over an hour old and those win 0.109 v 0.067 implied, "
"while fresh closes are fair (0.083 v 0.081); a stale close is not a price on offer at the off, so cells built on it misstate what bookie v2 can trade. "
"Rule fixed now: fairprice_v0 unchanged except every runner's last pre-off print must be within 10 min of market_time; IS/OOS by date median of the fit set; "
"cells passed by job 538's Verifier rule; scored on the unseen fresh-close markets as item 486 (back £10, lay liability £10, one tick adverse, 2%, official result, t by market, halves by date); "
"PRIMARY PASSED ALL; also the share of each market type's closes that are stale, for the map owner.")
s = s.rstrip('\n') + '\n' + item + '\n'
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read().rstrip('\n')
t += ("\n2026-11-09 | data-led (fair_price_calib, bf_hist_other_files.loaded_at, from the COO decision) | pre-off fair-price map and bookie v2's passed cells scored on markets loaded after the map was built (499_calib_unseen, item 486) | DONE | nothing passes; PASSED ALL n 8,567 +1.101 t by market 3.15; OU4.5 tail cells carry it on stale closes, other 18 cells about -0.12; map fair at print -0.027"
      "\n2026-11-09 | data-led (from 486) | fair-price map rebuilt on fresh closes only (last print within 10 min of the off), scored on 486's unseen markets (item 487) | TODO | 486 stale Over 4.5 closes won 0.109 v 0.067, fresh 0.083 v 0.081\n")
open(h, 'w').write(t)
print('ok')
