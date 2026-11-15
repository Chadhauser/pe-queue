import sys
t = open('/root/pe-queue/watchman/HYPOTHESES.md').read().lower()
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().lower()
print('lines', t.count('\n'))
for k in sys.argv[1:]:
    k = k.lower()
    print(k, 'hyp', t.count(k), 'queue', q.count(k))
    for l in t.split('\n'):
        if k in l:
            print('   ', l[:200])
