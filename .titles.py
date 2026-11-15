import re
lines = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for i, l in enumerate(lines, 1):
    m = re.match(r'^\s*(\d+)\.\s*(\S+)', l)
    if not m:
        continue
    t = re.search(r'\*\*(.+?)\*\*', l)
    title = t.group(1) if t else l[:70]
    if int(m.group(1)) >= 230:
        print(m.group(1), m.group(2)[:4], title[:95])
print('--- recheck hooks')
for i, l in enumerate(lines, 1):
    if re.search(r'(2023-0[5-7]|Jul(y)? 2023|Jun(e)? 2023|before Aug 2023|before Sep 2023)', l) and re.match(r'^\s*\d+\.\s*TODO', l):
        m = re.match(r'^\s*(\d+)\.', l)
        print(m.group(1), [x for x in re.findall(r'.{60}(?:2023-0[5-7]|Jul(?:y)? 2023|Jun(?:e)? 2023).{50}', l)][:2])
