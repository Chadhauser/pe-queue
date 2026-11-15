p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "431. TODO (from 8 Nov; "
assert s.count(old) == 1
s = s.replace(old, "431. DONE 2026-11-07 — nothing passes; PRICED FIRST lay n 960 +0.184 t 1.06 h1 +0.041 h2 +0.339, less top 1% +0.084, control PRICED -0.018; same sign as item 430, far weaker; jobs/499_equaliser_unseen.sh (reports/finder_2026-11-07_item430.md) — (run 7 Nov, not 8 Nov, as time allowed; ", 1)
assert '\n432. ' not in s
s = s.rstrip('\n') + '\n' + ("432. RUNNING 2026-11-07 (lane A; Finder's own, source a, from item 430; tables bf_hist_other, af_events, af_fixtures; job 499_equaliser_draw_unseen from jobs/499_equaliser_unseen.sh) "
    "**Back the Draw after a late equaliser to 1-1, games item 430 never saw.** "
    "Rationale: item 430 DRAW back E 66-80 n 598 +1.042 t 2.21 h1 +1.325 h2 +0.784, won 0.605 v implied 0.557; item 431 found the first-scorer lay fades on unseen games, so this is the other side of the same price. "
    "Rule fixed now, no new cuts: second goal makes it 1-1 at af minute E 66-80, no third goal by E+3, back 'The Draw' at its first MATCH_ODDS print in match minutes E+4..E+6 (lib_afmatch clock, worse of it and the next print within 120 s, one tick adverse), "
    "scored only if PRICED: that raw print <= 0.8 x the Draw's last print in E-6..E-1; prices 1.01-50, £10 stake, 2%, held to the af FT score, never dropped, one bet a game; games not in af_price_map, Apr 2023 to Sep 2026; "
    "CONTROL E 46-65 and first-half E 10-40, cannot pass; standard bar, halves by date median; read the top 1% and price bands before any verdict.") + '\n'
open(p, 'w').write(s)
print('ok')
