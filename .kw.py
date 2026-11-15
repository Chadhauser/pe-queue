import re, glob
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
h = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
jobs = {f: open(f, errors='ignore').read() for f in glob.glob('/root/pe-queue/jobs/*.sh')}
KW = ['referee', 'manager|new coach|sacked|caretaker', 'dead rubber|nothing to play|last game of the season|final day|last round|final round',
      'overround|book sum|book total', 'promoted|relegat', 'opening day|first game of the season|first round of the season|season opener|early season|early-season',
      'altitude|attendance|capacity|venue_', 'weather|rain|temperature', 'round number|league_round|af_round|\\bround\\b',
      'playoff|play-off', 'second half of the season|run-in|late season', 'tv\\b|total_matched|traded volume', 'kick-off hour|ko hour|by hour|UTC hour|local kick',
      'first_half_goals|FH05.*OU|second.half goals', 'corner', 'NEXT_GOAL|next goal', 'ASIAN|asian handicap', 'injur', 'over_under_05|OU05', 'streak|unbeaten|winless']
for k in KW:
    r = re.compile(k, re.I)
    its = []
    for l in q:
        m = re.match(r'^\s*(\d+)\.\s', l)
        if m and r.search(l):
            its.append(m.group(1))
    jb = [f.split('/')[-1] for f, t in jobs.items() if r.search(t)]
    print(k, '| queue', len(its), its[:14], '| hyp', sum(1 for l in h if r.search(l)), '| jobs', len(jb), jb[:5])
print(len(q), len(h))
