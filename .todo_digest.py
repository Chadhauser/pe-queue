import re
L = open('watchman/FINDER_QUEUE.md').read().split('\n')
print(len(L), 'lines')
n = 0
for i, l in enumerate(L, 1):
    m = re.match(r'\s*(\d+)\.\s+(TODO|RUNNING)', l)
    if m:
        n += 1
        print(i, l[:330].replace('\n', ' '))
        print()
print('open', n)
print('--- last 8 lines (ends)')
for l in L[-8:]:
    print(l[:250])
