import re
lines = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(lines, 1):
    m = re.match(r'^\s*(\d+)\.\s+(\S+)', l)
    if m and m.group(2).startswith(('TODO', 'RUNNING')):
        print(i, l[:260])
        print('---')
