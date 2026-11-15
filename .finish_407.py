import os
R = '/root/pe-queue/'
RP = 'reports/finder_2026-11-07_items407-412.md'
for j in ('499_ht_identity', '499_ht_women_youth', '499_ht_identity_audit', '499_ht_identity_touch', '499_ht_quote_hedge'):
    a, b = R + 'jobs/' + j + '.sh.wip', R + 'jobs/' + j + '.sh'
    assert not os.path.exists(b), b
    s = open(a).read()
    s = s.replace('print("largest-gap share by group")', 'print("signals by group, G2")')
    open(a, 'w').write(s)
    os.rename(a, b)
p = R + 'watchman/FINDER_QUEUE.md'
s = open(p).read()
done = {
 407: f"nothing passes; first print, HTFT G2 CHEAP back n 354 +2.333 t 1.43 h1 +4.104 h2 +0.280, won 0.427 v implied HT/FT 0.396 v MO 0.437; first read's +2.785 t 1.70 kept the largest gap, a look-ahead, item 410; goes on as item 413; jobs/499_ht_identity.sh, {RP}",
 408: f"nothing passes, 0 of 29 lines on first print; DC G4 CHEAP back n 27 +1.799 t 1.13, DNB G2 CHEAP back n 58 +2.191 t 1.63, U15 G2 CHEAP back n 251 +0.676 t 1.13; first run read no DC, as DC has two winners, fixed; jobs/499_ht_identity.sh, {RP}",
 409: f"nothing passes, 0 of 16; YOUTH G1 O2.5 lay n 396 +0.880 t 1.40 h1 +0.610 h2 +1.214, won 0.553 v 0.589, goes on as item 414; senior control -0.136; jobs/499_ht_women_youth.sh, {RP}",
 410: f"kept as a lean, cannot pass, the months chose it; win rate follows MO, not the HT/FT print, G4 CHEAP won 0.542 v HT/FT 0.365 v MO 0.514; jobs/499_ht_identity_audit.sh, {RP}",
 411: f"read; HT/FT spread median 6.94 points v MO 0.85; 18 locks of 16,898 snapshots, 9 on one game, so a taker cannot reach item 407's gap; about 3% of inferred half-time winners look wrong; jobs/499_ht_identity_touch.sh, {RP}",
 412: f"nothing passes, pilot; 37 fills from about 49,600 quoted snapshots, LAYQ K2 n 10 -0.231, BACKQ K2 n 13 -1.313, all four negative; fills inferred from sampled prints, so it reads the worst fills, not a real fill rate; jobs/499_ht_quote_hedge.sh, {RP}",
}
for n, txt in done.items():
    old = f"{n}. RUNNING 2026-11-07 ("
    assert s.count(old) == 1, n
    s = s.replace(old, f"{n}. DONE 2026-11-07 — {txt} — (")
if not s.endswith('\n'):
    s += '\n'
s += """413. TODO (first read when Soccer 2023-05 reads DONE, about 8 Nov, re-check 14 Nov as older seasons load; about 18 trades a month, so n 300 is about 17 months of the older seasons; Finder's own, source c, from items 407 and 410; tables bf_hist_other, bf_hist_result; job 499_ht_identity_audit unchanged except the window) **Back the HT/FT runner at half-time when it prints 2 points or more under Match Odds, older months.** Rationale: item 410 n 354 +2.333 t 1.43 h1 +4.261 h2 +0.337, won 0.427 v implied HT/FT 0.396 v MO 0.437, +1.034 less its largest win; the months chose it, so only games before Jun 2023 count. Rule fixed now, no new cuts: item 410's HTFT G2 CHEAP back, first print, standard bar, halves by date. Item 411 says a taker cannot reach this at the touch, spread 6.94 points, so a pass earns a real-touch read, not a stake.
414. TODO (first read when Soccer 2023-05 reads DONE, about 8 Nov, re-check 14 Nov as older seasons load; about 20 trades a month, so n 300 is about 15 months; Finder's own, source c, from item 409; tables bf_hist_other, bf_hist_result; job 499_ht_women_youth unchanged except the window) **Lay Over 2.5 in a youth game with one goal at half-time, older months.** Rationale: item 409 n 396 +0.880 t 1.40 h1 +0.610 h2 +1.214, won 0.553 v 0.589, best of 16, senior control -0.136. Rule fixed now, no new cuts: YOUTH G1 O2.5 lay as item 409, games before Jun 2023 only, standard bar, halves by date. A pass earns a real-touch read on liq_sample, not a stake.
"""
open(p, 'w').write(s)
p = R + 'watchman/HYPOTHESES.md'
s = open(p).read()
if not s.endswith('\n'):
    s += '\n'
s += """2026-11-07 | c (bf_hist_other, bf_hist_result) | at half-time, HT/FT X/F against MO F (499_ht_identity, item 407) | DONE | nothing passes; first print G2 CHEAP back n 354 +2.333 t 1.43; first read kept the largest gap, a look-ahead
2026-11-07 | c (bf_hist_other, bf_hist_result) | at half-time, DC, DNB, U0.5, CS 0-0, U1.5 same-bet pairs (499_ht_identity, item 408) | DONE | nothing passes; 0 of 29; DNB G2 CHEAP back n 58 +2.191 t 1.63
2026-11-07 | c (bf_hist_other, bf_hist_result) | women's and youth goal lines at the break (499_ht_women_youth, item 409) | DONE | nothing passes; 0 of 16; YOUTH G1 O2.5 lay n 396 +0.880 t 1.40
2026-11-07 | audit (bf_hist_other) | item 407 on the first qualifying print (499_ht_identity_audit, item 410) | DONE | lean kept, cannot pass; win rate follows MO, not the HT/FT print
2026-11-07 | a (liq_sample) | item 407 at the real touch, spread and locks (499_ht_identity_touch, item 411) | DONE | spread 6.94 v 0.85 points; 18 locks of 16,898 snapshots, 9 on one game
2026-11-07 | a (liq_sample) | quote inside HT/FT, hedge on MO (499_ht_quote_hedge, item 412) | DONE | nothing passes, pilot; 37 fills, all four lines negative; fills inferred from sampled prints
2026-11-07 | c (bf_hist_other, from 410) | back HT/FT 2 points under MO at the break, older months, rule fixed | TODO (item 413, about 8 Nov) | -
2026-11-07 | c (bf_hist_other, from 409) | lay Over 2.5 in a youth game with one goal at half-time, older months, rule fixed | TODO (item 414, about 8 Nov) | -
"""
open(p, 'w').write(s)
print('ok')
