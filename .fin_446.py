import os
J = '/root/pe-queue/jobs/'
src = open(J + '499_ht_state_thin.sh.wip').read()
open(J + '499_ht_state_thin.sh', 'w').write(src)
os.chmod(J + '499_ht_state_thin.sh', 0o755)
Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
s = open(Q).read()
a = "447. RUNNING 2026-11-08 (Finder's own"
assert s.count(a) == 1
s = s.replace(a, "447. DONE 2026-11-08 — nothing passes, 0 of 82 lines; 13,930 trades on 8,947 games item 446 could not time; Under won within 1-5 points of implied; best n>=300 N2 G1 lay U MID n 305 +0.655 t 1.15; lean N1 G2 lay U NOT_LEVEL n 230 +0.468 t 2.06 (h1 +0.608 h2 +0.350) sent to item 448; jobs/499_ht_state_thin.sh, reports/finder_2026-11-08_items446-447.md (Finder's own", 1)
assert '\n448.' not in s
s += ("448. TODO (re-check 12 Nov 2026, when Soccer 2023-02 reads DONE, then each older month; Finder's own, source c thin books, from item 447; tables bf_hist_other, bf_hist_result; job 499_ht_two_up_lay to write from jobs/499_ht_state_thin.sh) "
"**Lay Under 2.5 at a 2-0 or 0-2 half-time in a thin book, on months no read has used.** Rationale: item 447, games whose half-time markets stop printing early, "
"N1 G2 NOT_LEVEL lay U n 230 +0.468 t 2.06, h1 +0.608, h2 +0.350, Under won 0.096 v 0.142 implied; the back is the mirror, -3.762 t -2.92. On the liquid games item 446 read, the same line is +0.080 n 230 t 0.31, "
"so if it is real it lives in thin books. One of 82 lines, so expect it to shrink. Rule fixed now: item 447's code unchanged (window 55-62 min after the first in-play print, both goal guards, "
"official result, worse of print and next within 120 s, one tick adverse, GBP 10 liability, 2%), scored only on N1 G2 NOT_LEVEL lay U, UNSEEN games, months before Mar 2023. "
"About 10 trades a month at this rate, so n 300 needs about 30 older months; read each block as it loads and say n each time.\n")
open(Q, 'w').write(s)
h = open(H).read()
b = "window from the first in-play print (499_ht_state_thin, item 447) | RUNNING | -"
assert h.count(b) == 1
h = h.replace(b, "window from the first in-play print (499_ht_state_thin, item 447) | DONE | nothing passes; 0 of 82; n 13,930; lean N1 G2 NOT_LEVEL lay U n 230 +0.468 t 2.06")
h += "2026-11-08 | c thin books (bf_hist_other, bf_hist_result, from 447) | lay Under 2.5 at 2-0 or 0-2 HT in a thin book, months before Mar 2023, rule fixed | TODO (item 448, re-check 12 Nov) | -\n"
open(H, 'w').write(h)
print('ok')
