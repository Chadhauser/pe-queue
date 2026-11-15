Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read()
assert '\n469. ' not in q
item = ("469. RUNNING 2026-11-08 (lane A, about 20:35 UTC; Finder's own, source c, second door of item 468 on runners it could not price; tables bf_hist_other Horse Racing WIN GB/IE, "
 "Railway bfsp_history (389,556 rows, win and place, Jan 2024-Sep 2026, read only, pulled into the job), racing_bsp; job 499_bsp_loc_unseen, item 468's code with one change) "
 "**Lay the BSP steamer (limit-on-close, BSP at or under the last pre-off print / 1.25) on runners item 468 never saw.** "
 "Rationale: item 468, LAY k=1.25 ALL n 2,715 +0.161 t 2.52 (t by race 2.64) h1 +0.122 h2 +0.205, won 0.085 v 0.102 implied, monotone in k (k 1.0 -0.034, 1.1 +0.020, 1.25 +0.161); "
 "best of 36 so expect it to shrink; item 468 priced only 42,787 tape runners, 158,905 had no racing_bsp row. "
 "Rule fixed now, before any bfsp_history price is read: item 468's engine unchanged (p, bands, fills, BSP one tick adverse, GBP 10, 2%, win_lose, halves by date median); "
 "BSP and win_lose from bfsp_history market_type win on the event_dt date and folded name, unique, within 2 h; scored ONLY on runners with no racing_bsp row (UNSEEN); "
 "primary line LAY k=1.25 ALL, standard bar with t the smaller of trade and race; the other 35 lines printed for reading; also printed: on runners in both tables, the share whose BSPs agree within 1%.")
open(Q, 'w').write(q.rstrip('\n') + '\n' + item + '\n')
h = open(H).read().rstrip('\n') + '\n' + ("2026-11-08 | c structural (bf_hist_other, bfsp_history, from 468) | lay the BSP steamer (BSP <= last pre-off print / 1.25) on runners item 468 could not price "
 "(499_bsp_loc_unseen, item 469) | RUNNING | rule fixed before prices") + '\n'
open(H, 'w').write(h)
print('ok')
