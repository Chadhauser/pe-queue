import sys
lines = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
print('TOTAL', len(lines))
for n in [int(x) for x in sys.argv[1:]]:
    print(n, lines[n-1][:3000])
    print('-----')
