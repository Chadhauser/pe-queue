import re
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read()
h = open('/root/pe-queue/watchman/HYPOTHESES.md').read()
t = (q + h).lower()
for k in ['caan', 'webb', 'psychoff', 'lay the draw', 'ltd', 'trademate', 'sports trading life', 'cricket', 'tennis', 'greyhound', 'darts', 'snooker', 'basketball', 'rugby', 'ice hockey', 'baseball', 'american football', 'boxing', 'golf', 'horse racing', 'next goal', 'tie-break', 'set betting', 'first goal', 'goal kick', 'ou45', 'over 4.5', 'team_a', 'last 5', 'unders after']:
    print(f'{k!r}: {t.count(k)}')
import collections
# sport list in bf_hist_result
