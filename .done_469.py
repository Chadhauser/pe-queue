Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read()
a = ("468. DONE 2026-11-08 — nothing passes; 0 of 36; 42,787 runners in 5,722 races on racing_bsp; best LAY k1.25 ALL n 2,715 +0.161 t 2.52 (race 2.64) h1 +0.122 h2 +0.205, "
     "won 0.085 v 0.102, sent to item 469 where it reversed; controls BACK at BSP -0.343, LAY -0.062, won 0.132 v 0.132 implied; jobs/499_bsp_loc.sh, reports/finder_2026-11-08_items468-469.md — (")
b = ("469. DONE 2026-11-08 — nothing passes; PRIMARY LAY k1.25 ALL on 98,888 unseen runners (13,809 races, bfsp_history) n 5,877 -0.099 t -2.01 h1 -0.110 h2 -0.087, won 0.113 v 0.109; "
     "item 468's lean was chance; bfsp_history and racing_bsp agree on 27,638 of 27,638 shared runners; reading: BACK k1.25 6-12 positive in all four halves (pooled n 2,778 about +0.69, t under 1); "
     "first run parsed no dates, fixed once; jobs/499_bsp_loc_unseen.sh, reports/finder_2026-11-08_items468-469.md — (")
assert q.count('468. RUNNING 2026-11-08 (') == 1 and q.count('469. RUNNING 2026-11-08 (') == 1
q = q.replace('468. RUNNING 2026-11-08 (', a).replace('469. RUNNING 2026-11-08 (', b)
open(Q, 'w').write(q)
h = open(H).read()
h = h.replace("(499_bsp_loc, item 468) | RUNNING | rule fixed before prices",
              "(499_bsp_loc, item 468) | DONE | nothing passes; 0 of 36; best LAY k1.25 ALL n 2,715 +0.161 t 2.52, reversed in 469; BSP won at implied in every band")
h = h.replace("(499_bsp_loc_unseen, item 469) | RUNNING | rule fixed before prices",
              "(499_bsp_loc_unseen, item 469) | DONE | nothing passes; n 5,877 -0.099 t -2.01 on 98,888 unseen runners")
open(H, 'w').write(h)
print('ok')
