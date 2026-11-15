p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
L = s.split('\n')
i = [k for k, l in enumerate(L) if l.startswith('428. RUNNING 2026-11-07 22:05 UTC lane A')]
assert len(i) == 1
i = i[0]
L[i] = L[i].replace('428. RUNNING 2026-11-07 22:05 UTC lane A (NO RESULT 2026-11-07',
    '428. DONE 2026-11-07 — nothing passes, 0 of 10; 348 G1 games tied (2023 176, 2024 171, 2026 1), best Under back n 326 +0.457 t 0.77 h1 -0.787 h2 +1.701, Over lay n 322 +0.360 t 0.59; CONTROL all ten lines t under 0.4; the header fix Y[\'div\'] was the one fix, rule unchanged; jobs/499_season_open.sh, reports/finder_2026-11-07_item428.md; next door item 429 (earlier: NO RESULT 2026-11-07', 1)
new = ("429. TODO (re-check 12 Nov 2026, when Soccer 2022-08 to 2022-10 read DONE, then each older season; Finder's own, source c, from items 83, 427, 428; tables bf_hist_other, bf_hist_result, fd_matches; job 499_early_over_unseen to write from jobs/499_season_open.sh) "
       "**Lay Over 2.5 in a season's first three rounds, on months no read has used.** Rationale: every early-season read leans the same way on goals, each under t 1.6 and sharing games: item 83 OPEN3 lay Over n 890 +0.449 t 1.25; item 427 Pinnacle close G1 Over lay n 1,295 +0.413 (h1 +0.468, h2 +0.361), G2_3 n 2,538 +0.264 (h1 +0.266, h2 +0.261); item 428 tape G1 Over lay n 322 +0.360, Under back n 326 +0.457. "
       "Rule fixed now, no new cuts: fd_matches same div and season, games played before that date counted per side, same-date games not history; EARLY = both sides on 0, 1 or 2 games; CONTROL = both on 10 or more, same months, cannot pass. OVER_UNDER_25 'Over 2.5 Goals' only, last pre-off print T-20 to T-2 min, never earlier, lay at the worse of it and the next print within 120 s, one tick adverse, £10 liability, 2%, prices over 50 not traded, official bf_hist_result winner, never dropped for an early settle, one bet a game, women and youth out, events tied as item 428 (lib_cand.loose on date and team words). "
       "Months: market_time before 2023-04-01 only, as items 83, 427 (closes from 2019-20, so seasons 2019-20 to 2022-23 overlap the close read but not the tape), 428 read Apr 2023 on. Score once n >= 300 on the tape, standard bar, halves by date, plus beat CONTROL by 0.15 per £10. About 500 tied EARLY games a season at item 428's rate, so one season should reach n 300.")
L.insert(i + 1, new)
s = '\n'.join(L)
old70 = '70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — '
assert s.count(old70) == 1
s = s.replace(old70, old70 + '2026-11-07 about 22:15 UTC: 266 files/min, disk free 58 GB, local DB 61 GB; Soccer 2023-05 PARTIAL with 1 left, 2023-04 loading, Nov 2024 to Apr 2026 still LISTFAIL (reports/finder_2026-11-07_item428.md). ')
open(p, 'w').write(s)

h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
o = "2026-11-07 | c (fd_matches, bf_hist_other, from item 427) | a league's opening round on the tape (499_season_open, item 428) | TODO | no result, job crashed before any tape price"
assert t.count(o) == 1
t = t.replace(o, "2026-11-07 | c (fd_matches, bf_hist_other, from item 427) | a league's opening round on the tape (499_season_open, item 428) | DONE | nothing passes, 0 of 10; best Under back n 326 +0.457 t 0.77, h1 negative")
t = t.rstrip('\n') + "\n2026-11-07 | c (bf_hist_other, fd_matches, from items 83, 427, 428) | lay Over 2.5 in a season's first three rounds, months before Apr 2023 only (item 429) | TODO (re-check 12 Nov) | -\n"
open(h, 'w').write(t)
print('ok')
