import re, sys
txt = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for kw in sys.argv[1:]:
    h = [l for l in txt if re.search(kw, l, re.I)]
    qq = [l for l in q if re.search(kw, l, re.I)]
    print('==', kw, 'hyp', len(h), 'queue', len(qq))
    for l in h[:6]:
        print('  H:', l[:230])
