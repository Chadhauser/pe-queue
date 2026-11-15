import sys
L = open('/root/pe-queue/watchman/HYPOTHESES.md').read().split('\n')
print(len(L))
for s in L[-int(sys.argv[1]):]:
    print(s[:400])
