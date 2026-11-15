p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n').split('\n')
i = max(k for k, l in enumerate(t) if l.startswith('367. '))
assert not any(l.startswith('368. ') for l in t)
new = [
 "368. RUNNING 2026-11-07 (Finder's own, source c; table bf_hist_other; job 499_cricket_men_thin, a wrapper on 499_cricket_women_stress; from item 367) **Is item 367's lean thinness, not women?** Rationale: women's THIN carried item 367, so if the cause is a thin book the same lines should show on men's thin games, where the sample is larger. Rule fixed before this read: entries, costs and scoring as 367, men's two-runner games, THIN and THICK at the men's median of pre-off prints, <1.5 back and 6-20 lay; women alongside as the reference. Standard bar on THIN at 1 tick, read also at 3 and 5.",
]
t[i+1:i+1] = new
open(p, 'w').write('\n'.join(t) + '\n')
print('ok', i)
