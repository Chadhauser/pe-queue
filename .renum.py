def swap(path, pairs):
    s = open(path).read()
    for a, b, n in pairs:
        assert s.count(a) == n, (path, a, s.count(a))
        s = s.replace(a, b)
    open(path, 'w').write(s)
R = '/root/pe-queue/'
swap(R + 'watchman/FINDER_QUEUE.md', [
    ('413. TODO (first read when Soccer 2023-05', '420. TODO (first read when Soccer 2023-05', 1),
    ('414. TODO (first read when Soccer 2023-05', '421. TODO (first read when Soccer 2023-05', 1),
    ('a look-ahead, item 410; goes on as item 413;', 'a look-ahead, item 410; goes on as item 420;', 1),
    ('won 0.553 v 0.589, goes on as item 414;', 'won 0.553 v 0.589, goes on as item 421;', 1),
])
swap(R + 'watchman/HYPOTHESES.md', [
    ('older months, rule fixed | TODO (item 413, about 8 Nov)', 'older months, rule fixed | TODO (item 420, about 8 Nov)', 1),
    ('older months, rule fixed | TODO (item 414, about 8 Nov)', 'older months, rule fixed | TODO (item 421, about 8 Nov)', 1),
])
swap(R + 'reports/finder_2026-11-07_items407-412.md', [
    ('Next door: items 413 and 414,', 'Next door: items 420 and 421,', 1),
    ('NOT YET: item 413 re-reads', 'NOT YET: item 420 re-reads', 1),
    ('older months; item 414 re-reads', 'older months; item 421 re-reads', 1),
    ('.dcsel.py, .finish_407.py.', '.dcsel.py, .finish_407.py, .renum.py.\nNumbering: a parallel lane took 413 and 414 while this run was open, so these two were renumbered 420 and 421 after the first push.', 1),
])
M = '/root/.claude/projects/-root-pe-queue/memory/'
swap(M + 'ht-htft-lean.md', [
    ('"Items 407-414:', '"Items 407-412, 420, 421:', 1),
    ('item 413 re-reads on older months', 'item 420 re-reads on older months', 1),
    ('Item 414 is a separate lean', 'Item 421 is a separate lean', 1),
    ('re-read items 413 and 414 when', 're-read items 420 and 421 when', 1),
])
swap(M + 'MEMORY.md', [('items 413, 414 from about 8 Nov', 'items 420, 421 from about 8 Nov', 1)])
print('ok')
