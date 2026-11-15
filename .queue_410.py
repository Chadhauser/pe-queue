p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
if not s.endswith('\n'):
    s += '\n'
s += """410. RUNNING 2026-11-07 (Finder's own, audit of item 407; tables bf_hist_other, bf_hist_result; job 499_ht_identity_audit; these months chose it, so it cannot pass, it only keeps or kills) **Item 407 on the first qualifying print.** Rationale: item 407's rule kept the largest gap in the 8-minute window, which a trader cannot know at the time, and its HTFT G2 CHEAP back read n 354 +2.785 t 1.70 h1 +4.801 h2 +0.450; the rule was mine and the flaw is mine. Rule fixed after seeing item 407's table, no new cuts: as item 407, but the first print by time in the window at or past the gap, one bet per game per line. Printed beside it: win rate against implied HT/FT and implied MO at the signal; price bands to 3, 3-8, 8-20, 20-50; the next HT/FT print's gap, to read whether the print was a one-off. Control, not scored: the MO runner backed or laid at its own print on the same signals.
"""
open(p, 'w').write(s)
print('ok')
