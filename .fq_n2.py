import sys
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for n in sys.argv[1:]:
    print(n, L[int(n)-1][:3000])
    print('---')
