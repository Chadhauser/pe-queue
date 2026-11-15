p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "489. RUNNING 2026-11-09 (claimed about 08:35 UTC,"
assert s.count(old) == 1
s = s.replace(old, ("489. DONE 2026-11-09 — nothing passes; MAKER PASSED ALL (resting at the fresh cell price, trade-through fills, no tick) n 111,404 on 50,632 "
"markets, 16,558 games, -0.712 per £10, t_game -19.18, h1 -0.693 h2 -0.731; fill rate 0.354; adverse selection: filled lays won 0.353 v 0.313 implied "
"(unfilled 0.241), filled backs won 0.657 v 0.694 (unfilled 0.743); random-side control -1.075; 34 of 324 cells n>=300 positive, best OU0.5@m4 "
"p0.80-0.90 BACK n 386 +0.359 t 1.76; third door of the fair-price map family after 486 (pre-off unseen) and 488 (in-play taker), all negative "
"out of time; jobs/499_inplay_map_maker.sh, reports/finder_2026-11-09_items488-489.md (claimed about 08:35 UTC,"))
assert '\n490. ' not in s
item = ("490. RUNNING 2026-11-09 (claimed about 08:50 UTC, same run as 488-489; Finder's own, source a (the biggest predictable moves), born from item "
"489's fill asymmetry: a runner whose price traded through the fresh price in the next 3 min won 0.353 v 0.313 implied on lays and 0.657 v 0.694 "
"on backs, i.e. the 3-min move carried information beyond the old price; checked: HYPOTHESES rows 10, 13, 19 and items 0g, 23, 469 test momentum on "
"liq_sample, goal_stats or pre-match only, none on the 1-min BASIC tape in play across market types with official results; tables bf_hist_other, "
"bf_hist_result, finder_ipunseen_mk_1109 (as a fixed market list); job 499_inplay_follow_move, new, from jobs/499_inplay_map_maker.sh) "
"**Follow a 3-minute in-play move on the football tape, entered at the NEXT print after the move is seen.** Rule fixed now, before any price is read: "
"the 15 in-play map types, T = market_time + 16/31/46/61/76/91 min; P = runner's last print in [T-5, T); L = its last print in [T, T+3); SHORTENED if "
"L <= 0.95 P, DRIFTED if L >= 1.05 P; FOLLOW = back a shortener, lay a drifter, at the runner's first print in [T+3, T+6) one tick adverse (no print, "
"no trade); back £10 stake, lay £10 liability, 2% on profit, official result, exactly one winner. PRIMARY: FOLLOW pooled; lines per market type x "
"direction and per band; FADE (the other side, same entry) as the control; reading only: the 10% threshold. Bar with t on per-GAME sums, halves by "
"market_time median.\n")
s = s.rstrip('\n') + '\n' + item
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
o2 = "in-play map passed cells as a resting order at the fresh cell price, trade-through fills (489) | RUNNING | "
assert t.count(o2) == 1
t = t.replace(o2, "in-play map passed cells as a resting order at the fresh cell price, trade-through fills (489) | DONE | nothing passes; n 111,404 -0.712 t_game -19.2 both halves negative; adverse selection, filled lays won 0.353 v 0.313")
t = t.rstrip('\n') + "\n2026-11-09 | a moves (bf_hist_other, from 489's fill asymmetry) | follow a 5% in-play move seen over 3 min, entered at the next print, 15 football types (490) | RUNNING | \n"
open(h, 'w').write(t)
print('ok')
