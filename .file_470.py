Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'; H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read(); assert '\n470. ' not in q and '\n471. ' not in q
i470 = ("470. BLOCKED 2026-11-08 — needs PLACE markets on the racing tape: bf_hist_other Horse Racing holds market_type WIN only (71,058 of 71,058 rows sampled 1-3 Mar 2025), "
 "the loader (347, not Finder) would have to read the PLACE files; place BSP and results are already on Railway bfsp_history; then run item 468's engine unchanged on PLACE (job 499_bsp_loc_place to write from jobs/499_bsp_loc_unseen.sh) — "
 "(Finder's own, source c, third door of items 468-469) **Limit-on-close on the PLACE market: back if place BSP >= k x the last pre-off place print, lay if <= print / k, held to the place result.** "
 "Rationale: each-way and place money is SP-heavy and thin, so the place BSP may sit further from fair than the win BSP, which items 468-469 found fair in every band on 141,675 runners.")
i471 = ("471. TODO (re-check when loader 347 adds Horse Racing WIN months outside Sep 2024 to Sep 2026 AND bfsp_history or racing_bsp holds their BSP; bfsp_history stops 17 Sep 2026, racing_bsp 6 Nov 2026, so first look 1 Dec 2026; "
 "Finder's own, source c, from items 468-469; tables bf_hist_other, bfsp_history, racing_bsp; job 499_bsp_drifter_unseen to write from jobs/499_bsp_loc_unseen.sh) "
 "**Back a 6-12 runner at BSP only when the BSP has drifted 25%+ past its last pre-off print (limit-on-close back at 1.25 x p), on months no read has used.** "
 "Rationale: the only cell of items 468-469 positive in all four halves: 468 n 883 +0.597 (h1 +1.056 h2 +0.064), 469 n 1,895 +0.734 (h1 +0.382 h2 +1.148), pooled n 2,778 about +0.69, "
 "won 0.094-0.097 v 0.087 implied; t under 1 in each, best-looking of 72 lines, so expect it to shrink; at this variance n 300 cannot reach t 3.5, so the job reports the sign and n on each new block only. "
 "Rule fixed now: item 468's engine unchanged, BACK k=1.25 band 6-12 only, scored only on markets outside Sep 2024 to Sep 2026; standard bar; never pooled with 468-469.")
open(Q, 'w').write(q.rstrip('\n') + '\n' + i470 + '\n' + i471 + '\n')
h = open(H).read().rstrip('\n') + '\n'
h += "2026-11-08 | c structural (bf_hist_other, bfsp_history, from 468-469) | limit-on-close at BSP on the PLACE market (item 470) | BLOCKED | tape holds racing WIN only; loader would need PLACE files\n"
h += "2026-11-08 | c structural (bf_hist_other, bfsp_history, from 468-469) | back a 6-12 BSP drifter (BSP >= 1.25 x last print), months no read has used (item 471) | TODO (first look 1 Dec) | four halves positive, pooled n 2,778 about +0.69, t under 1\n"
open(H, 'w').write(h)
R = '/root/pe-queue/reports/finder_2026-11-08_items468-469.md'
r = open(R).read()
r = r.replace("Next door: item 470, the same order on the PLACE market, where each-way money pools at SP (run tonight if time allows, below).",
 "Next door: item 470, the same order on the PLACE market, where each-way money pools at SP: BLOCKED, as bf_hist_other Horse Racing holds WIN only (71,058 of 71,058 rows sampled), so the loader would have to read PLACE files. The drifter cell is queued as item 471, first look 1 Dec 2026, on months no read has used.")
r = r.replace(".claim_468.py, .claim_469.py, .done_469.py.", ".claim_468.py, .claim_469.py, .claim_470.py, .done_469.py, .file_470.py.")
open(R, 'w').write(r)
print('ok', r.count('BLOCKED'))
