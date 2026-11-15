src = '/root/pe-queue/jobs/499_sep22_rereads.sh'
dst = '/root/pe-queue/jobs/499_aug22_rereads.sh'
t = open(src).read()
pairs = [
    ("# 499_sep22_rereads (Finder 2026-11-09, 02:30 UTC run, lane A): items 451, 448, 450 and 465 on September 2022, a month no read has used",
     "# 499_aug22_rereads (Finder 2026-11-09, 04:05 UTC run, lane A): items 448, 450 and 465 on August 2022, a month no read has used in full (451 closed, kept for the record)"),
    ("# (Soccer 2022-09 DONE on the loader, 66,193 of 66,193 files, finished about 00:56 UTC 9 Nov).",
     "# (Soccer 2022-08 on the loader: run only once bf_hist_months shows it DONE; Aug 2022 is the oldest month on the box, so any item needing earlier games has a burn-in and may read n near 0)."),
    ("# Copy of jobs/499_oct22_rereads.sh with only the month changed (10 -> 9, October -> September labels); each child job runs unchanged except its month list and labels.",
     "# Copy of jobs/499_sep22_rereads.sh with only the month changed (9 -> 8, September -> August labels); each child job runs unchanged except its month list and labels."),
    ("with the window cut to Sep 2022 and the same added scored line as the Oct read:",
     "with the window cut to Aug 2022 and the same added scored line as the Oct and Sep reads:"),
    ("range(9,10)", "range(8,9)"),
    ("September 2022 only", "August 2022 only"),
    ("Sep 2022", "Aug 2022"),
    ("a=pd.Timestamp(2022,9,1)", "a=pd.Timestamp(2022,8,1)"),
    ("while a<pd.Timestamp(2022,10,1):", "while a<pd.Timestamp(2022,9,1):"),
]
for a, b in pairs:
    assert t.count(a) >= 1, a
    t = t.replace(a, b)
bad = [l for l in t.split('\n') if 'Sep' in l and not l.startswith('#')]
assert not bad, bad
assert 'range(9,10)' not in t
open(dst, 'w').write(t)

p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
for it in ('445', '448', '450', '465'):
    old = '\n' + it + '. TODO ('
    assert s.count(old) == 1, it
    s = s.replace(old, '\n' + it + '. RUNNING 2026-11-09 04:05 UTC (Aug 2022 re-read once Soccer 2022-08 reads DONE, code unchanged) (', 1)
open(p, 'w').write(s)
print('ok')
