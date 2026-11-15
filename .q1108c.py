import re
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i in (238, 482):
    l = L[i-1]
    for m in re.finditer(r'(?i)winter|mid-season|days since last|rest days|fixture gap|international break', l):
        print(i, l[:40], '...', l[max(0, m.start()-200):m.end()+200])
        print()
