import re, sys
n = int(sys.argv[1]) if len(sys.argv) > 1 else 260
for i, l in enumerate(open('/root/pe-queue/watchman/FINDER_QUEUE.md'), 1):
    if re.match(r'^\s*\S+\.\s+(\*\*)?(TODO|RUNNING)', l):
        print(i, l[:n].rstrip())
