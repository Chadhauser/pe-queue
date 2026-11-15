import re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
R = 'reports/finder_2026-11-08_items444-apr-mar23.md'
CLAIM = re.compile(r"^(\s*)(\d+)\. RUNNING 2026-11-08 \(Finder, (?:April|March) 2023 (?:re-)?read:[^)]*\) (.*)$")
upd = {
    '422': f"(UPDATE 2026-11-08: Mar 2023 ONE E1 n 192 +1.105 t 1.05, Apr 2023 n 191 -0.757; Mar-May 2023 pooled in one read n 515 +0.220 t 0.33 h1 +0.399 h2 +0.039, over n 300 and fails t; FAV E1 n 208 +0.885 t 1.24, not scored; re-check 14 Nov with Feb 2023; jobs/499_jump_up_unseen_pool.sh, {R})",
    '423': f"(UPDATE 2026-11-08: Mar 2023 D5 n 166 +1.459, Apr 2023 n 158 -1.214; Mar-May pooled D5 n 438 +0.187 t 0.25 h1 +0.407 h2 -0.033, fails; re-check 14 Nov; jobs/499_jump_up_unseen_pool.sh, {R})",
    '420': f"(UPDATE 2026-11-08: Mar 2023 n 26 -0.364, Apr 2023 n 28 +1.227; with May n 86 over three months, under the bar; re-check 14 Nov; jobs/499_apr23_rereads.sh, jobs/499_mar23_rereads.sh, {R})",
    '421': f"(UPDATE 2026-11-08: Mar 2023 n 28 -1.121, Apr 2023 n 21 +0.445; re-check 14 Nov; {R})",
    '406': f"(UPDATE 2026-11-08: Mar 2023 RULE G0 Y4 back n 14 -10.000, none won; Apr 2023 n 16 -0.910; re-check 14 Nov; {R})",
    '342': f"(UPDATE 2026-11-08: Apr 2023 FOUL_HIGH n 5 -2.904; Mar 2023 no trade, 1 game matched, as calendar leagues have under five games by March; re-check 14 Nov; {R})",
    '352': f"(UPDATE 2026-11-08: Apr 2023 BOTH home lay n 2 -10.000, RALLY n 1 -10.000; Mar 2023 BOTH n 0, RALLY n 1 +9.899; re-check 14 Nov; {R})",
    '435': f"(UPDATE 2026-11-08: Mar 2023, the first pre-Apr-2023 month, PEN MOVED n 29 -5.525 t -1.95, 3 winners, open-play control n 320 -3.306; negative, so not pooled; re-check as Feb 2023 and older load, about 12-14 Nov; jobs/499_mar23_rereads.sh, {R})",
}
seen = set()
for i, l in enumerate(L):
    m = CLAIM.match(l)
    if m and m.group(2) in upd:
        L[i] = f"{m.group(1)}{m.group(2)}. TODO {upd[m.group(2)]} {m.group(3)}"
        seen.add(m.group(2))
    m2 = re.match(r'^(\s*)444\. RUNNING 2026-11-08 (.*)$', l)
    if m2:
        L[i] = f"{m2.group(1)}444. DONE 2026-11-08 — nothing passes: ONE E1 n 1,365 -0.019 t -0.06 h1 +0.404 h2 -0.501, won 0.504 v implied 0.497; UNDER n 486 +0.218, 2023 n 681 +0.556 t 1.02, 2026 n 150 -1.573; DOWN 2-4 OVER back n 631 -0.718 t -2.06, filed as item 445; jobs/499_jump_up_ou25.sh, {R}. {m2.group(2)}"
        seen.add('444')
    m3 = re.match(r'^(\s*)70\. TODO \(recurring, every run: timeout 590 bash jobs/499_loader_progress.sh\) — (.*)$', l)
    if m3:
        L[i] = f"{m3.group(1)}70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — 2026-11-08 about 04:05 UTC: 262 files/min, disk free 57 GB, local DB 63 GB; Soccer 2023-03 DONE (56,192 files), 2023-02 loading at 15,360 of 51,782, 2023-05 still PARTIAL with 1 left, 26 stale months unchanged; the job's full bf_hist_other scan took several minutes of disk ({R}). {m3.group(2)}"
        seen.add('70')
need = set(upd) | {'444', '70'}
assert seen == need, sorted(need - seen)
open(p, 'w').write('\n'.join(L))
print('updated', sorted(seen, key=int))
