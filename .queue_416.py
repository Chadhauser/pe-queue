p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
item = ("416. RUNNING 2026-11-07 (Finder's own, source c, from item 413; table racing_bsp; job 499_course_gap_unseen) "
        "**Lay the favourite on a course's second day running, on races item 413 did not read.** Rationale: item 413's one line with both halves positive and a losing mirror, G1 FAV lay n 866 +0.428 t 1.61 h1 +0.475 h2 +0.381, won 0.301 v 0.331, back -1.202 t -2.35, control G2_7 lay -0.004; best of 48, so likely chance. "
        "Rule fixed before this job reads a price: racing_bsp win, races before 1 Sep 2024 or from 1 Oct 2026; a second day is a course with a race on the box the day before, since no schedule covers these dates, so some controls are really second days, which can only blur it; clear favourite by ppwap, lay at BSP, one tick adverse, 2%, £10 risk, books 1.00-1.40. Standard bar, halves by date. Only SECOND DAY lay is scored. ppwap runs to the off, so a pass is an upper bound and earns a real-touch read on finder_rlog, not a stake.")
assert '\n416. ' not in t
t = t.rstrip('\n') + '\n' + item + '\n'
open(p, 'w').write(t)
print('queued 416')
