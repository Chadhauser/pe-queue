p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read().rstrip('\n')
assert '\n436. ' not in s
s += ('\n436. TODO (Finder\'s own, source a, from item 339; tables liq_sample, xx_ip_331, both local; job 499_xx_unconfirmed) **Fade a Betfair in-play jump the other book does not confirm.** '
      'Rationale: item 339, after a 5% Betfair move the other book was still unmoved at its next row on only 12-17% of signals, and taking its stale touch lost (Matchbook n 639 -1.496, Smarkets n 658 -1.459), '
      'so either the thin book is slow or Betfair overshot; this asks the second question on Betfair alone, where the spread is tight. '
      'Rule fixed now, before any price is read: football match odds, minute 5 to 85, each book alone; Betfair mid moved 5% or more between consecutive two-sided rows of one runner up to 120 s apart; '
      'the other book\'s mid (last row at or before each Betfair row, within 60 s) moved under 0.5% over that span AND its next row, within 120 s, is still within 0.5% (UNCONFIRMED); '
      'CONFIRMED (other moved 2% or more the same way by its next row) is the control and cannot pass. Entry at Betfair\'s first row at or after the other book\'s next row, '
      'FADE (mid rose: back at back-1 tick; mid fell: lay at lay+1 tick) and FOLLOW (the reverse) as two lines; exit at the first Betfair row at or after entry+300 s, one tick adverse, greened; '
      'no later row: settled at the last prints. Over 50 not traded. Replay guard total_matched >= 0.999 of the market high. First signal per class per runner per game. Standard bar, halves by date, t by game too. '
      'Suspended other books may still print unchanged rows, so a pass needs a goal_timeline check before any stake.')
open(p, 'w').write(s + '\n')
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read().rstrip('\n')
t += '\n2026-11-08 | a (liq_sample, xx_ip_331, from 339) | fade a Betfair in-play 5% jump the other book does not confirm (499_xx_unconfirmed, item 436) | TODO | -\n'
open(h, 'w').write(t)
print('436 added')
