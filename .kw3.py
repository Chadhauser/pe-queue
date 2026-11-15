import re, glob
q = open('watchman/FINDER_QUEUE.md').read().split('\n')
h = open('watchman/HYPOTHESES.md').read().split('\n')
jobs = {f: open(f, errors='ignore').read() for f in glob.glob('jobs/*.sh*')}
words = ['tick size|tick-size|tick boundar|price boundar|round number|anchor',
         'last race|final race|last of the day|chas(e|ing) loss',
         'first race', 'referee', 'promoted|newly promoted', 'dead rubber|nothing to play|final round|last day of|final day|last round',
         'aggregate|second leg|two-leg', 'derby|local rival', 'manager|sacked|new coach',
         'overround|over-round|book sum|sum of (the )?(back|price)', 'any other|any unquoted',
         'over_under_45|OU45|over 4.5', 'over_under_05|Over 0.5', 'half_time\\b|HALF_TIME', 'total_matched|matched volume|tv ',
         'kick-off time|kickoff hour|hour of|time of day|evening games', 'weekday|day of week|monday|midweek',
         'dutch|arbitrage|arb ', 'cashout|cash out', 'scoreless|0-0 at', 'late goal|stoppage', 'each.way|each way|place market',
         'trap ', 'non.?runner|withdraw', 'set betting|tie.?break', 'break of serve|service break', 'darts', 'snooker', 'golf', 'rugby', 'basketball', 'ice hockey|NHL', 'NFL|american football', 'mma|boxing', 'baseball|MLB']
for w in words:
    r = re.compile(w, re.I)
    a = [i for i, l in enumerate(q) if r.search(l)]
    b = [i for i, l in enumerate(h) if r.search(l)]
    c = [f for f, t in jobs.items() if r.search(t)]
    print(f'{w[:38]:38s} queue {len(a):3d} ledger {len(b):3d} jobs {len(c):3d}  e.g.', [q[i][:5].strip() for i in a[:6]])
