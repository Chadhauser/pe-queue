import re, sys
txt = open('/root/pe-queue/watchman/HYPOTHESES.md').read().splitlines()
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().splitlines()
print('hyp lines', len(txt), 'queue lines', len(q))
for kw in sys.argv[1:]:
    hits = [l for l in txt if re.search(kw, l, re.I)]
    qh = [l for l in q if re.search(kw, l, re.I)]
    print('==', kw, len(hits), 'hyp', len(qh), 'queue')
    for l in hits[:6]:
        print('   ', l[:230])
