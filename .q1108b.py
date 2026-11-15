L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for n in (294, 350, 451, 469, 523, 532, 533, 537, 538, 550, 560, 563, 565):
    print(n, L[n-1][:1500])
    print()
