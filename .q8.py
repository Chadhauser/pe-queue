import re, sys
want = set(sys.argv[1:])
for i, l in enumerate(open('watchman/FINDER_QUEUE.md'), 1):
    m = re.match(r'\s*(\d+)\.\s', l)
    if m and m.group(1) in want and ('TODO' in l[:12]):
        print(i, l[:1500])
        print()
print('--- ledger tail')
H = open('watchman/HYPOTHESES.md').read().split('\n')
print(len(H))
for l in H[-14:]:
    print(l[:260])
