import re
txt = open('/root/pe-queue/watchman/HYPOTHESES.md').read().lower()
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().lower()
print('lines', txt.count('\n'))
for k in ['morningwap', 'ppwap', 'btts', 'red card', 'fh05', 'fh15', 'ipmin', 'ou35', 'corner', 'equalis', 'late goal', 'dnb', 'second goal', 'ou15',
          'place market', 'each way', 'ah ', 'stoppage', 'injury time', '90+', 'kick-off time', 'midweek', 'monday', 'sunday', 'weekday', 'time of day', 'evening', 'lunchtime', 'early kick']:
    print(f'{k!r}: hyp {txt.count(k)} queue {q.count(k)}')
