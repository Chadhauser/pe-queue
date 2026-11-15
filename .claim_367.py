p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n').split('\n')
i = max(k for k, l in enumerate(t) if l.startswith('366. '))
assert not any(l.startswith('367. ') for l in t)
new = [
 "367. RUNNING 2026-11-07 (Finder's own, source a; tables bf_hist_other, cricket_matches on Railway; job 499_cricket_women_stress; from item 366; same games, so it can only keep or kill the lean and cannot pass) **Item 366's two women's lines under stress.** Rationale: W <1.5 back and W 6-20 lay are the two best reads, and they are mostly the same game from opposite sides, so they are one idea, and a wide thin book could eat it all. Rule fixed before this read: entries as 366, W <1.5 back and W 6-20 lay. Score: official winner where cricket_matches has a unique women's match within a day, else inferred, else last-print odds. Costs 1, 3 and 5 ticks adverse. Split THIN and THICK at the median count of pre-off prints in the entry window, and by half. Men's <1.5 back alongside as the control.",
]
t[i+1:i+1] = new
open(p, 'w').write('\n'.join(t) + '\n')
print('ok', i)
