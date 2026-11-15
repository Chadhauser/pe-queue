import re
P = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(P).read()
assert not re.search(r'^482\. ', s, re.M), 'item 482 exists'
item = ("482. RUNNING 2026-11-09 04:50 UTC (Finder's own, source c structural, new: no ledger, queue or job line has read round-number prices; "
        "tables bf_hist_other, bf_hist_result; job 499_round_number_preoff) **Round-number prices before the off: does a runner whose last pre-off print sits "
        "exactly on 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 15 or 20 win at a different rate from its implied price?** Rationale: resting money clusters at round prices, "
        "so a book can sit on a round number while the fair price has moved through it; the direction is not known, so both sides are scored. Rule fixed now: "
        "Soccer MATCH_ODDS (3 runners) and OVER_UNDER_25 (2 runners), last pre-off print of each runner within 30 min before market_time, price 1.2-20.5; "
        "ROUND = print on the set above, NEAR = one tick either side of a round (reading control); one bet a market, the runner with the latest print if several "
        "qualify; one tick adverse, £10 stake or liability, 2% on profit, held to the market's official result (bf_hist_result, one winner), never dropped; "
        "women and youth out; halves by date median. Scored lines (4): MO ROUND back, MO ROUND lay, OU25 ROUND back, OU25 ROUND lay; standard bar. "
        "Reading only: NEAR, ALL-runner control, each round price, each year.")
s = s.rstrip('\n') + '\n' + item + '\n'
open(P, 'w').write(s)
H = '/root/pe-queue/watchman/HYPOTHESES.md'
h = open(H).read().rstrip('\n') + '\n' + ("2026-11-09 | c structural (bf_hist_other, bf_hist_result, new) | runner whose last pre-off print is a round number "
     "(2, 3, 5, 10 ...), back or lay, MO and OU2.5, held to the result (499_round_number_preoff, item 482) | RUNNING | -") + '\n'
open(H, 'w').write(h)
print('claimed 482')
