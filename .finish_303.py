import os
R = 'reports/finder_2026-11-07_items303-417.md'
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
def sub(a, b):
    global t
    assert t.count(a) == 1, a
    t = t.replace(a, b)
sub("303. RUNNING 2026-11-07 (needs data",
    f"303. DONE 2026-11-07 — nothing passes; Jun-Dec 2023 FAV SELL ALL lay n 471 -0.343 t -0.72 h1 -0.201 h2 -0.521, without the largest win -0.418, so item 295's line is closed; jobs/499_flip_flow_unseen.sh, {R} (was: needs data")
sub("137. TODO (needs data",
    f"137. TODO (UPDATE 2026-11-07: Jun 2023 to Jul 2024 interim, CHEAP back Yes n 200 +0.202 t 0.35 h1 -0.112 h2 +0.443, won 0.620 v 0.598; RICH back Yes, mirror, n 189 -2.200 t -3.16, against +1.423 at lay on item 132, so not a lead; jobs/499_btts_cheap_older.sh, {R}) (needs data")
sub("292. TODO (needs data",
    f"292. TODO (UPDATE 2026-11-07: Jun-Dec 2023 interim, DIVS lower at home HIGHER back n 35 -0.069, KNOWN_AWAY KNOWN back n 87 -0.461; pooled with the first reads by hand n 249 about +0.61; jobs/499_cup_older.sh, {R}) (needs data")
sub("342. TODO (UPDATE 2026-11-07: Aug 2023 n 5",
    f"342. TODO (UPDATE 2026-11-07: Jun-Jul 2023 n 3 +1.827, control all Draws won 0.118 v 0.246 on n 119, unexplained, do not pool these months; jobs/499_jun23_rereads.sh, {R}) (UPDATE 2026-11-07: Aug 2023 n 5")
sub("352. TODO (UPDATE 2026-11-07: Aug 2023 BOTH",
    f"352. TODO (UPDATE 2026-11-07: Jun-Jul 2023 BOTH n 2 +11.698, RALLY n 5 -4.678; jobs/499_jun23_rereads.sh, {R}) (UPDATE 2026-11-07: Aug 2023 BOTH")
sub("413. RUNNING 2026-11-07 (Finder's own",
    f"413. DONE 2026-11-07 — nothing passes; 0 of 48, 5,272 races; G1 FAV lay n 866 +0.428 t 1.61 h1 +0.475 h2 +0.381, item 416 read it; {R} (Finder's own")
sub("414. RUNNING 2026-11-07 (Finder's own",
    f"414. DONE 2026-11-07 — audit, cannot pass; prints hold, ONE E1 n 1,500 +1.321 t 3.21, E2 n 833 +1.618, E3 +1.026, 2023 +1.795, 2024 +0.943, 2026 +1.131, controls negative; touch n 24 -7.819, so the keep rule fails and the taker form closes on this read; next door item 417; {R} (Finder's own")
sub("415. RUNNING 2026-11-07 (Finder's own",
    f"415. DONE 2026-11-07 — pilot; 69 games, 2-7 Nov: at the print -1.393 t -0.89, back_px 6 s on -1.925 t -1.34, rested and filled through n 17 +3.348; 54% of prints at or over the lay, 22% at or under the back, spread 1.40 points, so by its rule the taker form closes; n 69 cannot reject the tape's +1.3, so item 417 re-reads forward; {R} (Finder's own")
sub("416. RUNNING 2026-11-07 (Finder's own",
    f"416. DONE 2026-11-07 — closed; SECOND DAY lay n 63 -1.826 t -1.82 h1 -2.433 h2 -1.238, won 0.460 v 0.374, control +0.013; racing_bsp holds few consecutive days, so small, and the wrong way; {R} (Finder's own")
a = "70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
sub(a, a + f"2026-11-07 about 16:45 UTC: 264 files/min, disk free 63 GB, local DB 58 GB; Soccer 2023-06 DONE, 2023-05 at 9,600 of 47,357 files ({R}). ")
item = ("417. TODO (from 26 Nov, about 12.5 of these games a day on the stream, so n 300 about then if the local stream_ticks keeps them; Finder's own, source a, from items 414 and 415; tables stream_ticks, liq_sample, Railway goal_timeline; job 499_jump_up_ticks unchanged except games after 7 Nov 16:00 UTC) "
        "**Back a Match Odds runner after a first in-play print 2-4 points over the last pre-off print, on games after 7 Nov, at the real touch.** Rationale: item 414's prints hold across three years, but its two touch reads are n 24 and n 69, too few to tell a real cost from chance, and the spread of 1.40 points costs far less than the tape's edge. "
        "Rule fixed now, no new cuts: scored lines back_px 6 s on, and rested at the print filled through; standard bar on each, halves by date, read without the largest win. Also print the first-print timing split, as the tape's lead sits at 60 s or later. A pass earns a paper test with real fills, not a stake.\n")
assert '\n417. ' not in t
t = t.rstrip('\n') + '\n' + item
open(p, 'w').write(t)

h = '/root/pe-queue/watchman/HYPOTHESES.md'
x = open(h).read().rstrip('\n') + '\n'
x += ("2026-11-07 | b (bf_hist_other, from 499_flip_flow) | lay a favourite drifting before the off, Jun-Dec 2023 (499_flip_flow_unseen, item 303) | DONE | closed; n 471 -0.343 t -0.72\n"
      "2026-11-07 | c (bf_hist_other schedule, racing_bsp) | a course's first meeting after a gap, at BSP (499_course_gap, item 413) | DONE | nothing passes; 0 of 48; G1 FAV lay n 866 +0.428 t 1.61\n"
      "2026-11-07 | c (racing_bsp, from 499_course_gap) | lay the favourite on a course's second day, races 413 did not read (499_course_gap_unseen, item 416) | DONE | closed; n 63 -1.826 t -1.82\n"
      "2026-11-07 | a (bf_hist_other, bf_hist_result, from items 294, 303) | back MO runner after first in-play print 2-4 points up (499_jump_up_back, item 414) | DONE, audit | prints hold, n 1,500 +1.321 t 3.21, all three years; touch n 24 -7.819\n"
      "2026-11-07 | a (stream_ticks, from item 414) | where the book sits at that print (499_jump_up_ticks, item 415) | DONE, pilot | n 69 at print -1.393, back_px 6 s -1.925; 54% of prints at the lay, spread 1.40\n"
      "2026-11-07 | a (stream_ticks, from items 414, 415) | item 414 forward at the touch and resting, rule fixed | TODO (item 417, from 26 Nov) | -\n")
open(h, 'w').write(x)
print('queue and ledger updated')
J = '/root/pe-queue/jobs/'
for n in ('499_flip_flow_unseen', '499_btts_cheap_older', '499_cup_older', '499_jun23_rereads', '499_course_gap', '499_course_gap_unseen', '499_jump_up_back', '499_jump_up_ticks'):
    assert not os.path.exists(J + n + '.sh'), n
    os.rename(J + n + '.sh.wip', J + n + '.sh')
    print('renamed', n)
