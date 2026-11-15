q='/root/pe-queue/watchman/FINDER_QUEUE.md'; h='/root/pe-queue/watchman/HYPOTHESES.md'
item=("\n473. RUNNING 2026-11-08 22:55 UTC (Finder, lane default/top; top TODOs all date-gated and 472 held by lane A) (Finder's own, source c structural, an exact price bound; "
"checked 8 Nov: HYPOTHESES.md and queue for bound, Under v Draw, related-market arb: the 3 Nov arb on liq_sample was LP worst-outcome on 5 pairs at the next snapshot, item 19/403 a tick lead-lag at 0-0, item 472 BTTS v MO; "
"the Under v current-result bound on the two-season tape is unread; tables bf_hist_price (MO, OU15, OU25, OU35), af_price_map, af_fixtures, af_events; job 499_under_bound to write from jobs/315_grid_v2.sh) "
"**Back the current result on Match Odds when Under (goals+0.5) prints shorter than it.** Rationale: with g goals scored, Under g+0.5 wins only if no more goals, and then the current result stands, "
"so P(Under g+0.5) <= P(current result on MO) exactly (Draw if level, leader if not); a print breaking that is a stale or mispriced leg. Rule fixed now, before any price is read: "
"states g = 1, 2, 3 (lines 1.5, 2.5, 3.5), score from af_events, entry minute 10-87 and at least 3 min after the last goal (minute + extra), both prints at the entry minute must differ from their last print before that goal "
"and the current-result MO price must be shorter than before it (a stale pre-goal print cannot pass); GAP = 1/U - 1/M; classes V2 GAP >= 0.02, V0 0-0.02, C2 -0.02-0 (control), C5 -0.05 to -0.02 (control); "
"first qualifying minute per game per state per class; fill at the worse of the minute print and the next within 2 min, one tick adverse, GBP 10, 2% on profit, held to the result (af FT score), never dropped. "
"Legs: BACK_M (scored line, V2 ALL), LAY_U, PAIR (both legs, per GBP 10 risk each, summed / 2); by LEVEL v LEAD and minute band; women and youth out; price-map guard: MO winner's last print by min 85 must be under 1.5 on the af result; halves by season 2024 v 2025; standard bar.")
s=open(q).read()
assert '\n473.' not in s
open(q,'w').write(s.rstrip('\n')+item+'\n')
line=("2026-11-08 | c structural (bf_hist_price, af_events, new) | back the current result on MO when Under (goals+0.5) prints shorter than it, an exact bound; lay the Under, and the pair (499_under_bound, item 473) | RUNNING | -\n")
t=open(h).read(); open(h,'w').write(t.rstrip('\n')+'\n'+line)
print('ok')
