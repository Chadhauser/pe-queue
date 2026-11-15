import os
R = '/root/pe-queue/'
for j in ('499_oct23_feb24_262_265', '499_race_distance', '499_xmas_football', '499_cricket_women', '499_cricket_women_stress', '499_cricket_men_thin', '499_cricket_rematch'):
    a, b = R + 'jobs/' + j + '.sh.wip', R + 'jobs/' + j + '.sh'
    assert os.path.exists(a) and not os.path.exists(b), j
    os.rename(a, b)
REP = 'reports/finder_2026-11-07_items262_363-370.md'
p = R + 'watchman/FINDER_QUEUE.md'
L = open(p).read().rstrip('\n').split('\n')
def sub(prefix, fn):
    k = [i for i, l in enumerate(L) if l.startswith(prefix)]
    assert len(k) == 1, prefix
    L[k[0]] = fn(L[k[0]])
RUN = ' RUNNING 2026-11-07 '
def done(res):
    return lambda l: l.replace(RUN, ' DONE 2026-11-07 — ' + res + ' (' + REP + ') — ', 1)
sub('262. RUNNING', done('nothing passes, scored at n 387 on unseen months, Oct 2023 to Feb 2024: MO 3 AT back -0.071 t -0.10 h1 +0.690 h2 -0.820, won 0.339 v 0.336, jobs/499_oct23_feb24_262_265.sh; earlier +1.251 did not hold, closed'))
sub('265. RUNNING', lambda l: l.replace(RUN, ' TODO (UPDATE 2026-11-07: Oct 2023 to Feb 2024 read as one window, CHEAP back n 99 -0.959 t -1.13, DEAR lay n 154 +1.399 t 1.52, pooled by hand n 253 about +0.476, down from about +0.959 at n 211, still under n 300, jobs/499_oct23_feb24_262_265.sh, ' + REP + '; re-read when Soccer 2023-09 is DONE) ', 1))
sub('363. RUNNING', done('nothing passes, 0 of 56; best FLAT 1m1f-1m4f <=5 lay n 3,313 +0.213 t 1.62 h1 +0.184 h2 +0.245 -> item 371; jobs/499_race_distance.sh'))
sub('364. RUNNING', done('nothing passes, 0 of 8; 508 races on 19 days, 18 of them Kempton 27 Dec festival races; best HOLIDAY >15 back n 2,151 +2.106 t 0.89 h1 -0.979; jobs/499_race_distance.sh'))
sub('365. RUNNING', done('nothing passes, 0 of 10; best OVER lay n 337 +0.150 t 0.28; closes DRAW lay n 2,487 +0.294 t 2.48 collects the margin and the tape leans the other way; jobs/499_xmas_football.sh'))
sub('366. RUNNING', done('nothing passes, 0 of 10, a re-slice; W 6-20 lay n 181 +0.722 t 4.42, last-print +0.530 t 3.07, fails n; W <1.5 back n 710 +0.466 t 2.65, last-print n 748 +0.350 t 2.06, fails t; men nothing -> item 369; jobs/499_cricket_women.sh'))
sub('367. RUNNING', done('cannot pass; W 6-20 lay at 5 ticks n 191 +0.393 t 2.31; W <1.5 back at 5 ticks n 678 +0.047 t 0.26; official only 36 games, April 2026, too few to read; THIN carries both; jobs/499_cricket_women_stress.sh'))
sub('368. RUNNING', done('nothing passes, not thinness; M 6-20 lay THIN n 185 +0.042 t 0.19, M <1.5 back THIN n 867 +0.057 t 0.35; jobs/499_cricket_men_thin.sh'))
sub('370. RUNNING', done('nothing passes, 0 of 8, a re-slice; best previous LOSER lay n 885 +0.260 t 0.83, last-print +0.210 t 0.73; winner again won 0.634 v 0.613; 1,209 rematches, 146 skipped; jobs/499_cricket_rematch.sh'))
OLD = 'about 12 W 6-20 and 45 W <1.5 games a month, so n 300 on the back about 7 months on, re-check 1 Dec 2026'
sub('369. TODO', lambda l: (l.replace(OLD, 'about 8 W 6-20 and 30 W <1.5 games a month, 191 and 748 over 25 months, so n 300 on the back about 10 months on and over 3 years on the lay, re-check 1 Dec 2026', 1) if OLD in l else 1 / 0))
i = [k for k, l in enumerate(L) if l.startswith('370. ')][0]
assert not any(l.startswith('371. ') for l in L)
L[i + 1:i + 1] = ["371. TODO (needs data — complete UK/IE win races after 4 Nov 2026, from the Betfair historical files, as items 94 and 105; about 56 trades a month on the box, so n 300 in about 6 months if that rate holds; Finder's own, source d; table racing_bsp; job 499_race_distance unchanged except the window) **Lay a short price over 1m1f-1m4f on the flat, unseen races.** Rationale: best of item 363's 56 lines, n 3,313 +0.213 t 1.62 t per race 1.87 h1 +0.184 h2 +0.245, won 0.260 v implied 0.274, against -0.050 for all <=5 lays; best of 56, so likely chance. Rule fixed now, no new cuts: FLAT 1m1f-1m4f, morning WAP at or under 5, lay at BSP one tick adverse, 2%, GBP 10 risk, races after 4 Nov 2026 only, standard bar and t per race >= 3.5."]
PFX = '70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — '
sub(PFX, lambda l: l.replace(PFX, PFX + '2026-11-07 about 07:40 UTC: 264 files/min, disk 75 GB, local DB 50 GB; Soccer 2023-10 DONE, 2023-09 at 8,160 of 62,031 files, 18 months still LISTFAIL, 25 stale (' + REP + '). ', 1))
open(p, 'w').write('\n'.join(L) + '\n')
H = R + 'watchman/HYPOTHESES.md'
A = [
 "2026-11-07 | c (bf_hist_other, bf_hist_result, from 499_ladder_slot) | back an MO runner printing exactly 3.0, unseen months, scored (499_oct23_feb24_262_265, item 262) | DONE | did not hold; n 387 -0.071 t -0.10 h1 +0.690 h2 -0.820",
 "2026-11-07 | d (racing_bsp) | race distance by price band at BSP (499_race_distance, item 363) | DONE | nothing passes; 0 of 56; FLAT 1m1f-1m4f <=5 lay n 3,313 +0.213 t 1.62",
 "2026-11-07 | c (racing_bsp) | bank-holiday cards at BSP (499_race_distance, item 364) | DONE | nothing passes; 0 of 8; HOLIDAY >15 back n 2,151 +2.106 t 0.89 h1 -0.979",
 "2026-11-07 | c (af_fixtures, bf_hist_price, fd_matches) | the Christmas football programme, 26 Dec to 2 Jan (499_xmas_football, item 365) | DONE | nothing passes; 0 of 10; OVER lay n 337 +0.150 t 0.28",
 "2026-11-07 | c (bf_hist_other) | women's cricket before the off, by band (499_cricket_women, item 366) | DONE | nothing passes; 0 of 10; W 6-20 lay n 181 +0.722 t 4.42 fails n; W <1.5 back n 710 +0.466 t 2.65",
 "2026-11-07 | a (bf_hist_other, cricket_matches) | item 366's two lines at 1, 3, 5 ticks, official, thin v thick (499_cricket_women_stress, item 367) | DONE | cannot pass; W 6-20 lay 5 ticks +0.393 t 2.31; W <1.5 back 5 ticks +0.047 t 0.26; official 36 games only",
 "2026-11-07 | c (bf_hist_other) | is item 367 thinness, men's thin games (499_cricket_men_thin, item 368) | DONE | no; M 6-20 lay THIN n 185 +0.042 t 0.19; M <1.5 back THIN n 867 +0.057 t 0.35",
 "2026-11-07 | c (bf_hist_other) | women's cricket favourite and outsider lay, unseen months, rule fixed | TODO (item 369, needs data, re-check 1 Dec 2026) | -",
 "2026-11-07 | c (bf_hist_other) | cricket, the same two teams again within 3 days (499_cricket_rematch, item 370) | DONE | nothing passes; 0 of 8; previous LOSER lay n 885 +0.260 t 0.83",
 "2026-11-07 | d (racing_bsp, from 499_race_distance) | lay a short price over 1m1f-1m4f on the flat, unseen races, rule fixed | TODO (item 371, needs data) | -",
]
t = open(H).read()
open(H, 'w').write(t.rstrip('\n') + '\n' + '\n'.join(A) + '\n')
print('finished')
