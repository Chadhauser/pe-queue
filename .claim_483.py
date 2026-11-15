import re
P = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(P).read()
assert not re.search(r'^483\. ', s, re.M), 'item 483 exists'
item = ("483. RUNNING 2026-11-09 05:10 UTC (Finder's own, source c structural, adjacent door of item 482 on racing; tables bf_hist_other, racing_bsp; "
        "join and settlement as jobs/499_bsp_loc.sh; job 499_round_number_racing) **Round-number prices before the off on GB and IE racing WIN markets.** "
        "Rationale: item 482 on football found ROUND backs worse than ALL backs and ROUND lays close to flat (MO 2.0 lay n 845 +0.581 t 1.73, a reading line); "
        "racing books are thinner before the off, so anchoring at round prices may be stronger. Rule fixed now: each runner's last pre-off print T-5 to T-1 min, "
        "price 1.2-20.5, ROUND and NEAR sets as item 482; one bet a race, the qualifying runner with the latest print; entry at that print one tick adverse, "
        "£10 stake or liability, 2% on profit, held to racing_bsp win_lose (same-day name match, one row, within 2 h, as job 468), never dropped; halves by date "
        "median; t is the smaller of per-trade and per-race. Scored lines (2): WIN ROUND back, WIN ROUND lay; standard bar. Reading only: NEAR, ALL, each round price. "
        "Read cut to a 1,500 s budget if the tape is slow, said so in the report.")
s = s.rstrip('\n') + '\n' + item + '\n'
open(P, 'w').write(s)
H = '/root/pe-queue/watchman/HYPOTHESES.md'
h = open(H).read().rstrip('\n') + '\n' + ("2026-11-09 | c structural (bf_hist_other, racing_bsp, from 482) | racing WIN runner whose last pre-off print is a round number, "
     "back or lay, held to win_lose (499_round_number_racing, item 483) | RUNNING | -") + '\n'
open(H, 'w').write(h)
print('claimed 483')
