p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "433. RUNNING 2026-11-07 (lane A, first part: item 179 via job 499_goal_type_guard; "
assert s.count(old) == 1
s = s.replace(old, "433. DONE 2026-11-07, first part (item 179) — item 179's lead is not a clock artefact: PEN OTHER back E5 settle MOVED n 456 +6.321 t 1.72 h1 +7.476 h2 +5.326, less top win +3.987; UNMOVED n 106 -0.532; across all 96 line pairs MOVED -0.430 v UNMOVED -0.412, so at c+5 the stale-print effect is not general; items 84 and 130 not re-read yet, TODO next run; jobs/499_goal_type_guard.sh (reports/finder_2026-11-07_item430.md) — (", 1)
assert '\n434. ' not in s
s = s.rstrip('\n') + '\n' + ("434. RUNNING 2026-11-07 (lane A; Finder's own, source a, from items 179 and 433; tables bf_hist_other, af_events, af_fixtures; job 499_pen_other_unseen from jobs/499_equaliser_unseen.sh) "
    "**Back the side that conceded a first-goal penalty, once the price has moved, games item 179 never saw.** "
    "Rationale: item 433 PEN OTHER back E5 settle MOVED n 456 +6.321 t 1.72, both seasons positive, +3.987 without its largest win; UNMOVED negative; open-play first goals NORMAL OTHER back flat. "
    "Rule fixed now, no new cuts: first goal of the game a Penalty (af detail) at af minute c 1-39 or 46-80, no second goal at or before c+7; back the side that conceded at its first MATCH_ODDS print in match minutes c+5..c+7 (lib_afmatch clock, worse of it and the next print within 120 s, one tick adverse), "
    "scored only if MOVED: the raw print >= 1.25 x that side's last print in c-6..c-1; prices up to 1000 as item 179, £10 stake, 2%, held to the af FT score, never dropped, one bet a game; games not in af_price_map, Apr 2023 to Sep 2026; "
    "CONTROL open-play first goals, same rule, cannot pass; standard bar, halves by date median, and read it without the largest win.") + '\n'
open(p, 'w').write(s)
print('ok')
