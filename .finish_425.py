import os, re
R = '/root/pe-queue/'
Q = R + 'watchman/FINDER_QUEUE.md'; H = R + 'watchman/HYPOTHESES.md'
REP = 'reports/finder_2026-11-07_items406-425.md'
q = open(Q).read().split('\n')
CLAIM = re.compile(r'^(\d+)\. RUNNING 2026-11-07 \(first read, Soccer 2023-05 holds 47,356 of 47,357 files, PARTIAL with 1 left\) TODO-after ')
NOTE = {
 '406': f"(UPDATE 2026-11-07: May-Jul 2023 RULE G0 Y4 back n 9 -4.424 t -0.79, Soccer 2023-05 one file short; jobs/499_ht_cards_older.sh, {REP}; re-check 14 Nov) ",
 '420': f"(UPDATE 2026-11-07: May 2023 n 32 -2.235 t -1.21 h1 -0.307 h2 -4.714, won 0.406 v 0.440, Soccer 2023-05 one file short; jobs/499_ht_identity_may23.sh, {REP}; re-check 14 Nov) ",
 '421': f"(UPDATE 2026-11-07: May 2023 n 13 +2.316 t 0.69 h1 +4.916 h2 -1.844, Soccer 2023-05 one file short; jobs/499_ht_youth_may23.sh, {REP}; re-check 14 Nov) ",
}
done = set()
for i, l in enumerate(q):
    m = CLAIM.match(l)
    if m:
        n = m.group(1); q[i] = f"{n}. TODO {NOTE[n]}" + l[m.end():]; done.add(n); continue
    if l.startswith('342. TODO '):
        q[i] = l.replace('342. TODO ', f"342. TODO (UPDATE 2026-11-07: May 2023 n 13 +0.728 t 0.16, control all Draws won 0.162 v 0.255 on n 74, again low; results are not the cause, af agrees with official 0.999; the fall comes at the print filter and item 425 reads it as chance, so still do not pool May-Jul 2023; jobs/499_may23_rereads.sh, {REP}) ", 1); done.add('342')
    elif l.startswith('352. TODO '):
        q[i] = l.replace('352. TODO ', f"352. TODO (UPDATE 2026-11-07: May 2023 BOTH home lay n 5 -10.000, RALLY under 2.0 n 2 +5.889; jobs/499_may23_rereads.sh, {REP}) ", 1); done.add('352')
    elif l.startswith('292. TODO '):
        q[i] = l.replace('292. TODO ', f"292. TODO (NOTE 2026-11-07: May 2023 cannot be read, league class needs 60 days of earlier games and the tape starts in May, 967 games unclassed, no DIVS game; waits for older months; {REP}) ", 1); done.add('292')
    elif l.startswith('137. TODO '):
        q[i] = l.replace('137. TODO ', f"137. TODO (NOTE 2026-11-07: May 2023 alone not read, its first 300 games are burn-in; {REP}) ", 1); done.add('137')
    elif l.startswith('70. TODO (recurring'):
        q[i] = l.replace('every run: timeout 590 bash jobs/499_loader_progress.sh) — ', 'every run: timeout 590 bash jobs/499_loader_progress.sh) — 2026-11-07 about 19:45 UTC: 265 files/min, disk free 58 GB, local DB 59 GB; Soccer 2023-05 47,356 of 47,357 PARTIAL, 2023-04 loading. ', 1); done.add('70')
    elif l.startswith('422. RUNNING 2026-11-07 '):
        q[i] = l.replace('422. RUNNING 2026-11-07 ', f"422. TODO (UPDATE 2026-11-07: May 2023 ONE E1 n 132 +0.346 t 0.26 h1 +2.399 h2 -1.707, less top win -0.056, won 0.371 v 0.353; E2 n 87 +0.869; E3 n 131 +0.085; re-check 14 Nov as older months load; jobs/499_jump_up_delay.sh, {REP}) ", 1); done.add('422')
    elif l.startswith('423. RUNNING 2026-11-07 '):
        q[i] = l.replace('423. RUNNING 2026-11-07 ', f"423. TODO (UPDATE 2026-11-07: scored May 2023 D5 n 114 +0.277 t 0.20 h1 +3.168 h2 -2.614; audit, months that chose the signal, D5 n 1,214 +1.076 t 2.36, D10 +0.706, D15 +0.837, controls negative; by year D5 2023 +1.550, 2024 +0.672, 2026 -0.180 n 125; re-check 14 Nov; jobs/499_jump_up_delay.sh, {REP}) ", 1); done.add('423')
    elif l.startswith('424. RUNNING 2026-11-07 '):
        q[i] = l.replace('424. RUNNING 2026-11-07 ', f"424. TODO (from 26 Nov with item 417; NO RESULT 2026-11-07: first run hit the 2 GB cap, the one allowed fix ran a full scan of 8.4 GB stream_ticks per market, about 100 min, stopped at the harness limit; before any re-run, read the later ticks in one scan through a temp table; jobs/499_jump_up_delay_touch.sh.wip, kept as .wip so the runner cannot start it; {REP}) ", 1); done.add('424')
    elif l.startswith('425. RUNNING 2026-11-07 '):
        q[i] = l.replace('425. RUNNING 2026-11-07 ', f"425. DONE 2026-11-07 — nothing passes; THREE lay n 727 +0.191 t 0.93 h1 +0.328 h2 +0.052, won 0.226 v 0.251; near-print split 0.226 v 0.240 on later months against 0.135 v 0.303 on May-Jul 2023, so chance in those months; 2026 +0.753 n 158; audit +0.800 t 3.06; control -0.259; next door item 426; jobs/499_draw_early_print.sh, {REP} — ", 1); done.add('425')
need = {'406','420','421','342','352','292','137','70','422','423','424','425'}
assert done == need, need - done
assert not any('TODO-after' in l or l.startswith(('422. RUNNING','423. RUNNING','424. RUNNING','425. RUNNING')) for l in q)
t = '\n'.join(q).rstrip('\n')
assert '\n426. ' not in t
t += f"""
426. TODO (re-check 1 Dec 2026, then when the 18 LISTFAIL months Nov 2024 to Apr 2026 clear, loader not Finder; about 30 games a month in season, and n 300 of new games needs those months; Finder's own, source c, from item 425; tables bf_hist_other, af_fixtures; job 499_draw_early_print unchanged except the window) **Lay the Draw at its first in-play print near kick-off, Allsvenskan, J1 League, Eliteserien, games item 425 did not read.** Rationale: item 425 n 727 +0.191 t 0.93, h1 +0.328 h2 +0.052, against -0.259 on other leagues; 2026 n 158 +0.753, 2024 n 528 +0.039. Post hoc from an unexplained control, so likely chance. Rule fixed now, no new cuts: item 425's rule, games kicked off Nov 2024 to Apr 2026 or after Sep 2026 only, standard bar, halves by date. A pass earns a real-touch read, not a stake.
"""
open(Q, 'w').write(t)
h = open(H).read()
subs = [
 ("| TODO (item 406, first read about 8 Nov) | -", "| TODO (item 406, re-check 14 Nov) | May-Jul 2023 n 9 -4.424 t -0.79"),
 ("| TODO (item 420, about 8 Nov) | -", "| TODO (item 420, re-check 14 Nov) | May 2023 n 32 -2.235 t -1.21"),
 ("| TODO (item 421, about 8 Nov) | -", "| TODO (item 421, re-check 14 Nov) | May 2023 n 13 +2.316 t 0.69"),
 ("| RUNNING (item 422, 499_jump_up_delay) | -", "| TODO (item 422, 499_jump_up_delay, re-check 14 Nov) | May 2023 n 132 +0.346 t 0.26, h2 negative"),
 ("| RUNNING (item 423, 499_jump_up_delay) | -", "| TODO (item 423, 499_jump_up_delay, re-check 14 Nov) | May 2023 D5 n 114 +0.277; audit D5 n 1,214 +1.076 t 2.36; 2026 -0.180 n 125"),
 ("| RUNNING (item 424, 499_jump_up_delay_touch) | -", "| TODO (item 424, from 26 Nov) | no result; job too slow on stream_ticks, stopped"),
 ("| RUNNING (item 425, 499_draw_early_print) | -", "| DONE | nothing passes; n 727 +0.191 t 0.93; near-print split reads as chance"),
]
for a, b in subs:
    assert h.count(a) == 1, a
    h = h.replace(a, b)
h = h.rstrip('\n') + "\n2026-11-07 | c (bf_hist_other, af_fixtures, from item 425) | item 425's Draw lay on games it did not read, rule fixed | TODO (item 426, re-check 1 Dec) | -\n"
open(H, 'w').write(h)
for b in ('499_ht_identity_may23', '499_ht_youth_may23', '499_ht_cards_older', '499_jump_up_delay', '499_may23_rereads', '499_draw_early_print'):
    a = f'{R}jobs/{b}.sh'
    assert not os.path.exists(a), a
    os.rename(a + '.wip', a)
print('ok')
