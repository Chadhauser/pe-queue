import os
q = 'watchman/FINDER_QUEUE.md'
s = open(q).read()

a = "427. RUNNING 2026-11-07 ("
assert s.count(a) == 1
s = s.replace(a, "427. DONE 2026-11-07 — nothing passes, 0 of 20; BFEC Away lay n 555 +0.724 t 1.57 h1 +0.267 h2 +1.083, but +0.372 without one £196 win on a junk close, and Pinnacle Away won 0.295 v 0.297 on n 2,627; PIN Over lay n 1,295 +0.413 t 1.42 h1 +0.468 h2 +0.361; the opening round is priced about right; jobs/499_season_open.sh, reports/finder_2026-11-07_items427-428.md (")

b = "428. RUNNING 2026-11-07 ("
assert s.count(b) == 1
s = s.replace(b, "428. TODO (NO RESULT 2026-11-07: job crashed twice on code errors before any tape price, on L.xs, then Y.div, a pandas method, and the brief allows one fix a run; rule unread and unchanged; fix in the job's header, take on the 8 Nov run; reports/finder_2026-11-07_items427-428.md) (")

c = "70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
assert s.count(c) == 1
s = s.replace(c, c + "2026-11-07 about 20:25 UTC: 261 files/min, disk free 58 GB, local DB 60 GB; Soccer 2023-05 PARTIAL with 1 left, 2023-04 loading (reports/finder_2026-11-07_items427-428.md). ")

d = "140. TODO ("
assert s.count(d) == 1
s = s.replace(d, "140. TODO (NOTE 2026-11-07: Soccer 2026-08 still PARTIAL, 40,148 of 40,151, unchanged since 5 Nov, so this gate may never open; reports/finder_2026-11-07_items427-428.md) (")
open(q, 'w').write(s)

h = 'watchman/HYPOTHESES.md'
s = open(h).read()
x = "a league's opening round at the closes (499_season_open, item 427) | RUNNING"
y = "a league's opening round on the tape (499_season_open, item 428) | RUNNING"
assert s.count(x) == 1 and s.count(y) == 1
s = s.replace(x, "a league's opening round at the closes (499_season_open, item 427) | DONE | nothing passes, 0 of 20")
s = s.replace(y, "a league's opening round on the tape (499_season_open, item 428) | TODO | no result, job crashed before any tape price")
open(h, 'w').write(s)

w = 'jobs/499_season_open.sh.wip'
j = 'jobs/499_season_open.sh'
assert not os.path.exists(j)
s = open(w).read()
m = "Prints only, so a pass is an upper bound.\n"
assert s.count(m) == 1
s = s.replace(m, m + "# NOTE 2026-11-07: crashes at the top-five print, before the tape section. Y.div is the DataFrame method, not the column. Fix for the next run: Y['div'].isin(TOP). Item 427's 20 scored lines print before this line.\n")
open(w, 'w').write(s)
os.rename(w, j)
print('ok')
