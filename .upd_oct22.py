import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
tag = '(RUNNING 2026-11-08 22:05 UTC: Oct 2022 re-read, lane A, jobs/499_oct22_rereads.sh) '
assert t.count(tag) == 5, t.count(tag)
R = 'reports/finder_2026-11-08_oct22-rereads.md'
upd = {
 '445': f"(UPDATE 2026-11-08 22:20 UTC: Oct 2022 loaded, PARTIAL 78,999 of 79,017 files, Sep 2022 still loading, read as loaded; UNSEEN Aug 2022-Feb 2023 MO ONE lay n 971 +0.365 t 1.21 h1 +0.127 h2 +0.605, shrinking from +0.511 on 690; MO FAV lay n 488 +0.817 t 1.52 h1 +0.331 h2 +1.304; OU25 OVER lay n 348 +0.194 t 0.33; re-check when Sep 2022 reads DONE; jobs/499_jump_down_lay.sh unchanged, {R}) ",
 '448': f"(UPDATE 2026-11-08 22:10 UTC: Oct 2022 N1 G2 NOT_LEVEL lay U n 19 +0.950 t 1.55 h1 +1.646 h2 +0.630, Under won 0.053 v 0.142 implied; pooled Oct-Feb n 49 about +0.96, interim; jobs/499_oct22_rereads.sh, {R}) ",
 '450': f"(UPDATE 2026-11-08 22:10 UTC: Oct 2022 ONE FAV back n 37 -0.610 t -0.61 h1 -0.811 h2 -0.398, won 0.591 of non-draws v 0.668 implied; pooled Oct-Feb n 94 about +0.24, weakening; jobs/499_oct22_rereads.sh, {R}) ",
 '465': f"(UPDATE 2026-11-08 22:10 UTC: Oct 2022 SH4 back HOLD one a game n 4 +1.836 (3 of 4 won, 0.601 implied), E85 n 1; af_events does not reach 2022, so the red-card share cannot be read on these months; jobs/499_oct22_rereads.sh, {R}) ",
}
lines = t.split('\n')
for i, l in enumerate(lines):
    m = re.match(r'^(445|448|450|451|465)\. TODO ', l)
    if not m: continue
    k = m.group(1)
    l = l.replace(tag, '', 1)
    if k == '451':
        l = l.replace('451. TODO ', f"451. DONE 2026-11-08 — nothing passes; unseen months now reach n: Oct 2022 FAV E1 n 95 +0.046 t 0.04 h1 -0.284 h2 +0.382 (won 0.516 v 0.506), pooled unseen Oct 2022-Jan 2023 n 334 about +0.11 (monthly t 0.04, 0.73, -0.50, 0.17; trade-weighted, not a fresh t), so the Feb-May 2023 lean (+0.686) has not held on months that did not choose it; jobs/499_oct22_rereads.sh, {R} — ", 1)
    else:
        l = l.replace(f'{k}. TODO ', f'{k}. TODO ' + upd[k], 1)
    lines[i] = l
t = '\n'.join(lines)
# loader line, item 70
a = '70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — '
assert t.count(a) == 1
t = t.replace(a, a + f"2026-11-08 about 22:00 UTC (light read, .lp1108q.py): Soccer 2022-10 PARTIAL 78,999 of 79,017 files (18 short, last file DB clock 21:46, about 20:46 UTC), 2022-11 to 2023-03 DONE, Sep 2022 loading, 2,640 files in 10 min ({R}). ", 1)
open(p, 'w').write(t)
print('ok')
