Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
q = open(Q).read().rstrip('\n')
assert '\n425. ' not in q
q += """
425. RUNNING 2026-11-07 (Finder's own, source c, from item 342's unexplained control; tables bf_hist_other, af_fixtures; job 499_draw_early_print) **Lay the Draw at its first in-play print near kick-off, Allsvenskan, J1 League, Eliteserien.** Rationale: May-Jul 2023, matched games with stats: the Draw won 0.135 on n 200 where it printed within 5 minutes of kick-off, 0.303 on n 221 where it did not, against 0.256 before the print filter; the same split on Aug-Oct 2023 reads 0.241 and 0.275, so it may be these leagues or these months; Allsvenskan 0.133 n 75 and 0.143 n 63, J1 0.159 n 63, Eliteserien 0.113 n 62. No cause known, and a filter artefact is the first suspect. Rule fixed before any price is read, and before any Draw rate after Oct 2023 is read: the three leagues, kicked off Nov 2023 to Oct 2024 or May to Sep 2026 on the tape; first in-play Draw print from kick-off -300 s to +300 s, the higher of it and the next within 120 s, one tick, over 50 not traded, 2%, £10 liability, to the final score, no goal filter, one bet a game. Standard bar, halves by date. May to Oct 2023 chose it and is an audit. Printed, not scored: each league, each year, the back mirror, other leagues as control, Draw share with and without a near print. A pass earns a look for the cause and a real-touch read, not a stake.
"""
open(Q, 'w').write(q)
H = '/root/pe-queue/watchman/HYPOTHESES.md'
h = open(H).read().rstrip('\n')
h += "\n2026-11-07 | c (bf_hist_other, af_fixtures, from item 342's control) | lay the Draw at its first in-play print near kick-off, three leagues, later months, rule fixed | RUNNING (item 425, 499_draw_early_print) | -\n"
open(H, 'w').write(h)
print('ok')
