p='/root/pe-queue/reports/finder_2026-11-08_item456.md'
s=open(p).read()
def sub(a,b):
    global s
    assert s.count(a)==1, a[:60]
    s=s.replace(a,b)
sub("""the median runner ends at the same print.
- So a taker who crosses two ticks pays the spread and gets nothing back.
""","""the median runner ends at the same print, so a taker crossing two ticks pays the spread for nothing.
""")
sub("""  - W24 2.5-4 lay: n 745, -0.023.
  - Every line with n of 1,000 or more is -0.09 to -0.36.
""","""  - W24 2.5-4 lay: n 745, -0.023. Every line with n of 1,000 or more is -0.09 to -0.36.
""")
sub("""  - Pooled with Jan 2023 (n 92, +0.198): n 169, about -0.18. It weakens.
  - The ONE E1 control is n 194, -1.038.
""","""  - Pooled with Jan 2023 (n 92, +0.198): n 169, about -0.18, so it weakens. The ONE E1 control is n 194, -1.038.
""")
sub("""- The 1,683 unscored trades had no exit print and no result. At 0.4% they cannot turn any line positive: the best line would need +0.055 x 1,254 = £69 from them.
""","""- The 1,683 unscored trades (no exit print, no result) are left out, 0.4% of trades. They were not counted per line. A run of 8-20 backs among them could move a small line, but 0.4% cannot close a gap of t -5 or worse.
""")
open(p,'w').write(s); print(len(s.splitlines()))
