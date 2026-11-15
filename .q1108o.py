L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i in range(len(L) - 6, len(L)):
    print(i + 1, L[i][:1500])
    print('---')
H = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
for l in H[-8:]:
    print(l[:400])
