import re, sys
Q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
H = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
kws = sys.argv[1:]
for k in kws:
    rx = re.compile(k, re.I)
    hq = [l for l in Q if rx.search(l)]
    hh = [l for l in H if rx.search(l)]
    print('==', k, 'queue', len(hq), 'hyp', len(hh))
    for l in hh[:6]:
        print('   H:', l[:230])
