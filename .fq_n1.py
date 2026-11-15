import re
for i, l in enumerate(open('/root/pe-queue/watchman/FINDER_QUEUE.md'), 1):
    m = re.match(r'^\s*(\d+)\.\s+(TODO|RUNNING)\b', l)
    if m:
        print(i, l[:260].rstrip())
