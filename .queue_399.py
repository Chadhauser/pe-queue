p='watchman/FINDER_QUEUE.md'
t=open(p).read()
new=r"""399. RUNNING 2026-11-07 (Finder's own, source a, from item 396's audit and item 393; tables ip_reopen, racing_results, ip_tape for sizes; job 499_reopen_restored; these months and races suggested it, so it cannot pass, unseen read is item 400) **Racing: a book restored after the race is decided, back the 1.01 horse at its old price, lay the beaten horse.** Rationale: item 396's DRIFT back won 0.546 v implied 0.302; the row's back sits at 0.97 of BSP while pre_ltp sits at 0.62, e.g. Cala Vadella pre 1.01, back 1.50, BSP 1.52, won. Reads as a book restored to about its pre-off state, the same event as item 393's collapse; item 392's audit had 27 of 31 such runners winning, status and size unknown. Size on show at the row is a median of about £55 on 24 rows. Rule fixed before this split is read: every reopen on ip_reopen, sport horse_racing or racing, WIN, with the lay within 5% of the back. Group by pre_ltp. RESTORED WINNER: pre_ltp at or under 1.20 and mid at least 15% over pre_ltp: back at post_back_px. RESTORED LOSER: pre_ltp at or over 20 and mid at least 15% under pre_ltp: lay at post_lay_px. First qualifying row per runner, one tick adverse, 2%, £10 risk, held to racing_results.won. Controls, not scored: pre_ltp over 1.20 and under 20 with the same two moves, both sides. Halves by date, t by race, standard bar, 3 ticks adverse as a stress. Also printed: mid over BSP, seconds since the race's first reopen, size on show from ip_tape where the rolling window holds the row. No word on whether Betfair lets such a fill stand: bets matched on a restored book may be voided, which no table here can show, so even a clean number earns a paper read and a check of the settled bet, not a stake.
400. TODO (from 21 Nov, about two weeks of new races, re-run every two weeks; n is small, about 2 a day on the first read's count until job 499_reopen_restored prints it; Finder's own, source a; tables ip_reopen, racing_results; job 499_reopen_restored unchanged except a start date of 8 Nov 2026) **Item 399's two lines on races the test has not seen.** Rationale: item 399 reads the months that suggested it. Rule fixed now, no new cuts: RESTORED WINNER back and RESTORED LOSER lay, as item 399, races from 8 Nov 2026 on, standard bar. A pass earns the settled-bet check, not a stake.
"""
if not t.endswith('\n'): t+='\n'
assert '\n399. ' not in t
open(p,'w').write(t+new)
h='watchman/HYPOTHESES.md'
s=open(h).read()
if not s.endswith('\n'): s+='\n'
s+="""2026-11-07 | a (ip_reopen, racing_results, from 396 and 393) | racing, book restored after the race is decided, back the 1.01 horse, lay the beaten one (499_reopen_restored, item 399) | RUNNING | -
2026-11-07 | a (same) | item 399 on unseen races | TODO (item 400, from 21 Nov) | -
"""
open(h,'w').write(s)
print('ok')
