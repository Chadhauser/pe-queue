import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
R = 'reports/finder_2026-11-08_feb23-rereads.md'
CL = 'RUNNING 2026-11-08 (Feb 2023 re-read, jobs/499_feb23_rereads.sh; back to TODO after) ('
notes = {
 342: 'TODO (UPDATE 2026-11-08: Feb 2023 n 0, no game has five earlier games that season, and the job raises KeyError on an empty table, so a crash here means n 0, not a window fault; re-check 14 Nov; jobs/499_feb23_rereads.sh, %s) (' % R,
 352: 'TODO (UPDATE 2026-11-08: Feb 2023 BOTH home lay n 1 +13.067, RALLY n 0; re-check 14 Nov; jobs/499_feb23_rereads.sh, %s) (' % R,
 406: 'TODO (UPDATE 2026-11-08: Feb 2023 RULE G0 Y4 back n 9 -5.949, less top win -10.000; four unseen reads n 48, all negative; re-check 14 Nov; jobs/499_feb23_rereads.sh, %s) (' % R,
 420: 'TODO (UPDATE 2026-11-08: Feb 2023 n 31 -0.837 t -0.38; Feb-May n 117 over four months, under the bar; re-check 14 Nov; jobs/499_feb23_rereads.sh, %s) (' % R,
 421: 'TODO (UPDATE 2026-11-08: Feb 2023 n 29 -3.302 t -1.73; Feb-May n 91, three of four months flat or negative; re-check 14 Nov; jobs/499_feb23_rereads.sh, %s) (' % R,
 422: 'DONE 2026-11-08 — nothing passes: Feb-May 2023 pooled in one read, the four months no read chose, ONE E1 n 647 (647 games) -0.245 t -0.43 h1 -0.183 h2 -0.307, won 0.366 v 0.360; signal print priced fair; FAV E1 n 261 +0.686 t 1.07 printed, not scored, sent to item 451; jobs/499_feb23_rereads.sh, %s (' % R,
 423: 'DONE 2026-11-08 — nothing passes: Feb-May 2023 pooled, ONE D5 n 538 -0.197 t -0.30 h1 +0.090 h2 -0.484; D3 -0.276, D10 -0.314, D15 +0.103; jobs/499_feb23_rereads.sh, %s (' % R,
 435: 'TODO (UPDATE 2026-11-08: Feb 2023 PEN MOVED n 34 -1.796 t -0.32 h1 -6.558 h2 +2.436, open-play control n 386 -0.617; negative again, not pooled; re-check as Jan 2023 and older load; jobs/499_feb23_rereads.sh, %s) (' % R,
}
for n, new in notes.items():
    a = '\n%d. %s' % (n, CL)
    assert t.count(a) == 1, n
    t = t.replace(a, '\n%d. %s' % (n, new))
assert '\n451. ' not in t
t = t.rstrip('\n') + '\n451. TODO (re-check 14 Nov 2026, when Soccer 2023-01 reads DONE, then each older month as the loader adds it; Finder\'s own, source a, from items 414, 422; tables bf_hist_other, bf_hist_result; job 499_jump_up_fav_unseen to write from jobs/499_jump_up_delay.sh) **Back the pre-off favourite on item 414\'s jump-up signal (first in-play print 2-4 points up on its last pre-off print, as item 414 defines it), on months no read has used.** Rationale: item 414\'s signal is fair on unseen months (item 422 ONE E1 n 647 -0.245), but its favourite leg is positive in both halves there, Feb-May 2023 FAV E1 n 261 +0.686 t 1.07, h1 +0.437, h2 +0.938, won 0.548 v 0.517 implied (Mar-May n 208 +0.885); outsiders -0.975 and draws -0.777 carry the loss. One of six printed lines, chosen after seeing them, so expect it to shrink. Rule fixed now, no new cuts: item 414/422 code unchanged, role FAV only (shortest MO runner at the last pre-off print), E1 entry (worse of the first in-play print and the next within 120 s), one tick adverse, GBP 10, 2%, prices over 50 not traded, one bet a game, official bf_hist_result winner, women and youth out; scored only on markets before 2023-02-01; standard bar, halves by date, also read without the largest win. About 65 trades a month at the Feb-May rate, so n 300 needs about five older months.\n'
open(p, 'w').write(t)

h = '/root/pe-queue/watchman/HYPOTHESES.md'
s = open(h).read().rstrip('\n') + '\n'
s += '2026-11-08 | re-reads (bf_hist_other, af_*, from 342, 352, 406, 420-423, 435) | February 2023, a month no read had used, and items 422/423 pooled Feb-May 2023 (499_feb23_rereads) | DONE | nothing passes; 422 ONE E1 n 647 -0.245 t -0.43 and 423 D5 n 538 -0.197 closed; the rest interim, all under n 300\n'
s += '2026-11-08 | a (bf_hist_other, bf_hist_result, from 414, 422) | back the favourite on item 414 jump-up signal (2-4 points up at the off), months before Feb 2023, rule fixed | TODO (item 451, re-check 14 Nov) | Feb-May 2023 FAV E1 n 261 +0.686 t 1.07 both halves positive\n'
open(h, 'w').write(s)
print('ok')
