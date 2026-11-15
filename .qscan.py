import re
for i, l in enumerate(open('/root/pe-queue/watchman/FINDER_QUEUE.md'), 1):
    m = re.match(r'\s*(\d+)\.\s*\**\s*(TODO|RUNNING)', l)
    if m:
        print(i, l[:330].rstrip())
        print()
