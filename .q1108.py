import re
for i, l in enumerate(open('/root/pe-queue/watchman/FINDER_QUEUE.md'), 1):
    m = re.match(r'^(\d+)\. (\S+)', l)
    if m and m.group(2).startswith(('TODO', 'RUNNING')):
        print(i, l[:260].rstrip())
