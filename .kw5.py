import re, glob
q = open('watchman/FINDER_QUEUE.md').read().split('\n')
h = open('watchman/HYPOTHESES.md').read().split('\n')
jobs = {f: open(f, errors='ignore').read() for f in glob.glob('jobs/*.sh*')}
words = ['rematch|same opponent|same two|reverse fixture|revenge|h2h|head.to.head|last meeting|previous meeting',
         'europa|thursday|european', 'last run|previous run|last time out|previous race',
         'traded (at|as low)|1\\.1.{0,30}lost|bust|beaten.{0,20}in.?running', 'season opener|opening day|first game of the season|first round|opening round',
         'unbeaten|winless|streak|losing run', 'hat.?trick', 'big (win|loss)|heavy defeat|thrash|hammer|lost by [3-9]']
for w in words:
    r = re.compile(w, re.I)
    a = [l for l in q if r.search(l)]
    c = [f[5:] for f, t in jobs.items() if r.search(t)]
    print(f'== {w[:50]}: q {len(a)} jobs {len(c)}', c[:4])
    for l in a[:12]:
        s = l.find('**')
        print('   ', l[:4], l[12:45], '|', l[s:s+85])
