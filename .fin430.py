p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "430. RUNNING 2026-11-07 (lane A; "
assert s.count(old) == 1
s = s.replace(old, "430. DONE 2026-11-07 — nothing passes; 1 of 54 numeric, struck: FIRST lay n 1,683 +0.664 t 3.52 h1 +0.776 h2 +0.564 rests on about 150 stale prints under 2.0, less top 1% +0.237 t 1.53, L10 +0.154; PRICED FIRST lay n 1,140 +0.392 t 2.43 both halves positive, 3 ticks +0.292; jobs/499_equaliser_side.sh, jobs/499_equaliser_stress.sh (reports/finder_2026-11-07_item430.md) — (lane A; ", 1)
old70 = "70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
assert s.count(old70) == 1
s = s.replace(old70, old70 + "2026-11-07 about 22:45 UTC: 266 files/min, disk free 58 GB, local DB 61 GB; Soccer 2023-05 PARTIAL with 1 left, 2023-04 at 57,600 of 70,704 files, Nov 2024 to Apr 2026 still LISTFAIL (reports/finder_2026-11-07_item430.md). ", 1)
assert '\n431. ' not in s
s = s.rstrip('\n') + '\n' + ("431. TODO (from 8 Nov; Finder's own, source a, from item 430; tables bf_hist_other, af_events, af_fixtures; job 499_equaliser_unseen to write from jobs/499_equaliser_stress.sh, events tied as item 404's jobs/499_var_off_unseen.sh) "
    "**Lay the side that scored first once a second-half equaliser is priced in, games item 430 never saw.** "
    "Rationale: item 430's numeric pass was stale prints, but the priced-in cut kept a lean, PRICED FIRST lay n 1,140 +0.392 t 2.43, h1 +0.344 h2 +0.435, 3 ticks +0.292, won 0.196 v implied 0.232, control first-half equalisers -0.169. "
    "Rule fixed now, no new cuts: second goal makes it 1-1 at af minute E 46-80, no third goal by E+3, lay the first scorer at its first MATCH_ODDS print in E+4..E+6 tape minutes on bf_hist_other (minute from kick-off by market_time), only if that print is at least 1.25 x its last print in E-6..E-1, prices 2-50, one tick adverse, £10 liability, 2%, held to the af FT score, never dropped, one bet a game; "
    "games not in af_price_map only (bf_hist_other MO Apr 2023 to Oct 2024 and May to Sep 2026); standard bar, halves by date; read the price-band table and the top 1% before any verdict. A pass earns a real-touch read on liq_sample with goal_timeline, not a stake.") + '\n'
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read().rstrip('\n') + '\n'
t += "2026-11-07 | a (af_events, bf_hist_price) | after a second-half equaliser to 1-1, back or lay the equaliser, the first scorer, the Draw (499_equaliser_side, 499_equaliser_stress, item 430) | DONE | nothing passes; 1 of 54 numeric, struck: FIRST lay n 1,683 +0.664 t 3.52 on stale prints, less top 1% t 1.53; PRICED n 1,140 +0.392 t 2.43\n"
t += "2026-11-07 | a (bf_hist_other, af_events, from 430) | lay the first scorer once a second-half equaliser is priced in, unseen games, rule fixed | TODO (item 431, from 8 Nov) | -\n"
open(h, 'w').write(t)
print('ok')
