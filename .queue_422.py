Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read().rstrip('\n')
assert '\n422. ' not in q and '\n423. ' not in q
q += """
422. RUNNING 2026-11-07 (Finder's own, source a, item 414's keep line; tables bf_hist_other, bf_hist_result; job 499_jump_up_delay) **Item 414 on May 2023, the first month no read has used.** Rationale: item 414 held on the months that chose it, n 1,500 +1.321 t 3.21, and said a later load is its unseen read. Rule fixed before this job reads a price: item 414's signal, ONE E1 scored, market time in May 2023 only, re-read as older months load, standard bar, halves by date. E2 and E3 printed. Soccer 2023-05 holds 47,356 of 47,357 files, and 2023-04 is still loading, so it is left out tonight. One month cannot reach n 300, so this cannot pass tonight.
423. RUNNING 2026-11-07 (Finder's own, source a, from items 414, 415; tables bf_hist_other, bf_hist_result; job 499_jump_up_delay) **Item 414, entered minutes later, once the book has rebuilt.** Rationale: item 415 found 54% of signal prints at or over the lay, spread 1.40 points, so a backer cannot take the signal print; a print picked by the clock, not by the gap, is free of that side selection, and if the win rate still beats the price there a taker has a route. Rule fixed before this job reads a price: item 414's signal and one bet a game unchanged; entry the runner's first in-play print from D minutes after the signal print to D minutes plus 300 s, none in that span no trade, worse of it and the next within 120 s, one tick, over 50 not traded, 2%, £10, official result, no goal filter. D 5 is the scored line; D 3, 10, 15 printed. May 2023 alone counts under the standard bar, and only it and later loads can pass; the months that chose the signal are printed as an audit. Controls, not scored: UP 1-2, DOWN 2-4, FLAT under 1 point by role. A pass, or an audit that holds, earns a read on stream_ticks at back_px, not a stake.
"""
open(Q, 'w').write(q)
h = open(H).read().rstrip('\n')
h += """
2026-11-07 | a (bf_hist_other, from item 414) | item 414 on May 2023, the first unseen month, rule fixed | RUNNING (item 422, 499_jump_up_delay) | -
2026-11-07 | a (bf_hist_other, from items 414, 415) | item 414 entered 5 minutes later, a print the gap did not choose, rule fixed | RUNNING (item 423, 499_jump_up_delay) | -
"""
open(H, 'w').write(h)
print('ok')
