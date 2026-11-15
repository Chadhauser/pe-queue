import re, glob
q = open('watchman/FINDER_QUEUE.md').read().split('\n')
h = open('watchman/HYPOTHESES.md').read().split('\n')
jobs = {f: open(f, errors='ignore').read() for f in glob.glob('jobs/*.sh*')}
words = ['own goal', 'suspen(sion|ded) (for|player)|banned|missed last|previous.{0,20}red|red.{0,25}(last|previous) game',
         'early sub|injur|substitut', 'direct red|second yellow|red card.*yellow', 'pp_vol', 'ip_vol', 'morning_vol', 'share of (the )?(matched|volume|money)|volume share|money share',
         'header|free kick|Normal Goal', 'by a substitute|substitute scor|super.?sub', 'captain', 'debut', 'shots? on target|xg', 'corners?', 'coach', 'formation',
         'ipmax|ipmin', 'ppmax|ppmin', 'winner.{0,20}previous|won (its|their) last', 'odd.?even|odd number|EVEN', 'time.?to.?(first|next).?goal']
for w in words:
    r = re.compile(w, re.I)
    a = [i for i, l in enumerate(q) if r.search(l)]
    b = [i for i, l in enumerate(h) if r.search(l)]
    c = [f[5:] for f, t in jobs.items() if r.search(t)]
    print(f'{w[:40]:40s} q {len(a):3d} led {len(b):3d} jobs {len(c):3d}', [q[i][:4].strip() for i in a[:7]], c[:3])
print()
for w in ['own goal', 'injur|substitut', 'pp_vol', 'direct red|second yellow', 'share of (the )?(matched|volume|money)|volume share|money share']:
    r = re.compile(w, re.I)
    for l in q:
        m = r.search(l)
        if m:
            s = l.find('**')
            print(w[:10], '|', l[:5], '|', l[s:s+90], '| ...', l[max(0, m.start()-60):m.end()+50])
    print()
