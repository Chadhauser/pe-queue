p = 'watchman/FINDER_QUEUE.md'
t = open(p).read()
assert '\n405. ' not in t
item = ("405. TODO (Finder's own, source c, from items 124, 138, 139; tables bf_hist_other, af_events, af_fixtures; job 499_fh3_lay_older; item 124's own rule stays open) "
        "**Lay three-plus first-half goals at 15 minutes at 0-0, Aug 2023 to Oct 2024.** Rationale: item 139 this run, back on two Augusts and two Septembers won 0.049 v implied 0.068 on n 1,514; Sep 2026's lay n 1,558 +0.135 t 2.33 chose the line and Jun-Aug 2026 went against it, n 775 -0.197 t -1.88, so 15 older months settle whether anything is there. Item 139 showed the win rate on four of the months, so those are not blind; the other 11 are printed apart. "
        "Rule fixed now, no new cuts: FH25 Over, senior games matched to af_fixtures by name, first in-play print 15 to 19 min after market time, no goal with af minute at or before the print's clock minute + 2, lay at the worse of it and the next print within 120 s, one tick adverse, over 200 not traded, 2%, £10 liability, to the af half-time score, checked against official. Standard bar on all 15 months, halves by date, and it must also be positive on the 11.")
open(p, 'w').write(t.rstrip('\n') + '\n' + item + '\n')
print('added')
