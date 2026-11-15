import re, glob
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
H = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
J = {f: open(f, errors='ignore').read() for f in glob.glob('/root/pe-queue/jobs/499_*.sh')}
K = ['beaten fav', 'harville|place.*implied|place v win|win v place|place market', 'last race|first race', 'distance|furlong|sprint',
     'opening round|first game of the season|season open|opening day', 'final round|last round|last day of|dead rubber|end of season|season.s end',
     'ipmin|ipmax', 'unlucky', 'chase|hurdle|novice', 'bank holiday|christmas|boxing day|new year',
     'all.?weather|evening', 'debut|maiden', 'multiple runners|same owner|same trainer|pair of', 'previous bsp|last.time.*bsp|bsp.*last time|shorter than last|price.*last run']
for k in K:
    r = re.compile(k, re.I)
    print('==', k, 'queue', sum(bool(r.search(l)) for l in Q), 'ledger', sum(bool(r.search(l)) for l in H), 'jobs', sum(bool(r.search(t)) for t in J.values()))
    for l in [l for l in H if r.search(l)][:5]:
        print('   L', ' | '.join(l.split('|')[2:]).strip()[:170])
    print('   J', [f.split('/')[-1][4:-3] for f, t in J.items() if r.search(t)][:6])
