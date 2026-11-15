import re
L = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(L, 1):
    if re.match(r'^\d+\.\s+(TODO|RUNNING)', l):
        print(i, l[:420].replace('\n', ' '))
        print()
print('--- tail (last 6 lines heads)')
for i, l in list(enumerate(L, 1))[-6:]:
    print(i, l[:160])
