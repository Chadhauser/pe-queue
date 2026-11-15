p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
R='reports/finder_2026-11-08_nov22-rereads.md'
o='\n461. RUNNING 2026-11-08 16:25 UTC ('
assert s.count(o)==1
s=s.replace(o,'\n461. DONE 2026-11-08 — nothing passes; 0 of 2; U3 STALE back n 195 -0.360 t -0.28 h1 -1.490 h2 +0.782, U1 STALE back n 2,062 +0.029 t 0.05; 98% of U3 entries came in-play and the stale leg had already shortened in 76% of them (median -4.5% v -1.3% in FAIR books), so the gap closes at the off before a taker can reach it; FAIR control back n 18,195 -0.406; jobs/499_mo_underround_ko.sh, '+R+' — (',1)
o70='\n70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — '
assert s.count(o70)==1
s=s.replace(o70,o70+'2026-11-08 about 16:01 UTC (light read, .lp1108q.py): Soccer 2022-11 DONE (53,502 files, DB clock 16:48), 2022-12 to 2023-03 DONE, Oct 2022 no row yet, 2,688 files in 10 min ('+R+'). ',1)
assert '\n462. ' not in s
s+=("462. TODO (re-check 22 Nov 2026, when local liq_sample holds about four weeks of MO books from 27 Oct; first count games whose three last pre-off LTPs sum under 0.99 with a real touch at t*; Finder's own, source c, second door of item 461; "
"tables liq_sample (MATCH_ODDS, real touch), bf_hist_result or the MO result; job 499_underround_touch to write from jobs/499_mo_underround_ko.sh) "
"**Item 461's under-100% book at the real touch: is the stale leg's value ever offered before the off?** Rationale: item 461, U3 books (sum < 0.97) put the stale leg 4.5% too long at its last print and 76% of the time it next trades shorter, but 98% of next prints come in-play, so at prints a taker never reaches it (U3 back n 195 -0.360, U1 n 2,062 +0.029). "
"If the touch at t* still offers the stale price, the edge is in the book and not just the LTP; if the touch has already moved, the family is shut. Rule fixed now: item 461's S bands and STALE leg; at t* read the stale leg's best back on liq_sample; "
"back at that touch (no extra tick, it is the touch) only when it is at or above the stale print, held to the result, GBP 10, 2%; one per game; U1 and U3 scored; the share of games where the touch is at or above the stale print is reported first; halves by date; standard bar.\n")
open(p,'w').write(s); print('ok')
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
if not t.endswith('\n'): t+='\n'
t+=("2026-11-08 | re-reads (bf_hist_other, bf_hist_result, items 448, 450, 451) | Nov 2022, a month no read had used (499_nov22_rereads) | DONE, interim | nothing passes; 451 FAV E1 n 70 +0.904, pooled Nov-Jan n 239 about +0.14; 448 n 13 +0.796; 450 n 22 +1.412; all stay TODO\n"
"2026-11-08 | re-read (bf_hist_other, bf_hist_result, item 445) | jump-down lay with Nov 2022 DONE (499_jump_down_lay unchanged) | DONE, interim | nothing passes; MO ONE lay n 690 +0.511 t 1.43 h1 +0.835 h2 +0.188; audit after Feb 2023 +0.076; stays TODO\n"
"2026-11-08 | c structural (bf_hist_other, bf_hist_result, mirror of item 31) | back the stale leg of an MO book whose last pre-off prints sum under 100% (499_mo_underround_ko, item 461) | DONE | nothing passes; 0 of 2; U3 n 195 -0.360, U1 n 2,062 +0.029; stale leg shortens 4.5% at the off, 98% of next prints in-play\n"
"2026-11-08 | c structural (liq_sample, from 461) | item 461's under-100% book at the real touch: is the stale price offered at t* | TODO (item 462, re-check 22 Nov) | item 461 at prints the gap closes at the off\n")
open(h,'w').write(t); print('ok h')
