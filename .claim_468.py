Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read()
assert '\n468. ' not in q and not q.startswith('468. ')
item = ("468. RUNNING 2026-11-08 (lane A, about 20:45 UTC; every queue TODO is gated on data or a date tonight; checked: queue and HYPOTHESES for limit on close, LOC, BSP v last print; "
 "item 170 traded last print to a BSP exit, item 463 morning WAP to BSP, no read has ENTERED at BSP conditional on BSP against the last print; Finder's own, source c structural, "
 "a real Betfair order type; tables bf_hist_other Horse Racing WIN GB/IE, racing_bsp; job 499_bsp_loc, new, from jobs/499_racing_preoff_tape.sh) "
 "**Limit-on-close at BSP: back only if BSP drifts to k x the last pre-off print, lay only if it shortens to the print / k, held to the result.** "
 "Rationale: a limit-on-close order is placed before the off and fills only when the BSP clears its limit, so it buys exactly the runners whose price was pushed out (back) or in (lay) by "
 "the late SP money; if that money is uninformed (SP punters, each-way, place hedges), the filled side is a bargain; if it is informed, it is a trap; no read has priced it. "
 "Rule fixed now, before any price is read: GB/IE WIN markets on the tape Sep 2024-Sep 2026; p = runner's last pre-off print in T-5 to T-1 min (scheduled off T), 1.01-1000; "
 "bands on p <3, 3-6, 6-12, 12-20, 20-50, ALL; BSP and win_lose from racing_bsp on date and folded name, unique name a day, event within 2 h; "
 "BACK LOC fills iff BSP >= k*p, LAY LOC fills iff BSP <= p/k, k = 1.0, 1.1, 1.25 (k=1.0 strict: > or <); entry at BSP one tick adverse (house rule), GBP 10 stake or liability, 2% on profit, "
 "held to win_lose, a runner with no BSP row is not priced and counted; every runner that fills is a trade (several a race), so t is also read by race (race sums) and the gate uses the smaller; "
 "control (not gated) every runner at BSP, k=0; 36 gated lines; halves by date median; standard bar; full fill assumed at BSP, an upper bound as a LOC at the limit can part-fill.")
q = q.rstrip('\n') + '\n' + item + '\n'
open(Q, 'w').write(q)
h = open(H).read().rstrip('\n') + '\n' + ("2026-11-08 | c structural (bf_hist_other, racing_bsp, new) | limit-on-close at BSP, back if BSP >= k x last pre-off print, lay if <= print/k, "
 "held to the result (499_bsp_loc, item 468) | RUNNING | rule fixed before prices") + '\n'
open(H, 'w').write(h)
print('ok')
