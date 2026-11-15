import re
lines = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(lines, 1):
    m = re.match(r'^\s*(\d+)\.\s*(\*\*)?(TODO|RUNNING)', l)
    if m:
        print(i, l[:420].replace('\n', ' '))
        print()
