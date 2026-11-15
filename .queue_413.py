p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
item = ("413. RUNNING 2026-11-07 (Finder's own, source c; tables bf_hist_other schedule, racing_bsp; job 499_course_gap) "
        "**A course's first meeting after a gap, at BSP.** Rationale: no ledger line reads how long a course has been idle; items 90, 116, 120, 204, 218 and 373 read the card, the meeting so far, the course's record, race type, clashes and the last race. "
        "After a long gap there is no recent form on that going and no recent course line, so the market may lean harder on the favourite. "
        "Rule fixed before any price: course from the schedule's event name, date stripped; gap is days since that course's last day on the schedule, with any month under 500 races counted as off the schedule, so a gap across it is unknown, not long, and the first day seen is out. "
        "States on every race of that day: G1, G2_7 (control, cannot pass), G8_30, G31_120, G121+. "
        "Lines: ppwap bands <=3, 3-6, 6-12, 12-30, 30+, and the clear favourite, back and lay at BSP, one tick adverse, 2%, £10 risk, to result, dead heats as job 499_last_race. "
        "Books 1.00-1.40 as job 499_last_race. Standard bar on t by race, halves by date. ppwap runs to the off, so a pass is an upper bound and earns unseen races, not a stake.")
assert '\n413. ' not in t
t = t.rstrip('\n') + '\n' + item + '\n'
open(p, 'w').write(t)
print('queued 413')
