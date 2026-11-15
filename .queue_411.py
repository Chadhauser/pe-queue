p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
if not s.endswith('\n'):
    s += '\n'
s += """411. RUNNING 2026-11-07 (Finder's own, from item 407; local liq_sample HTFT, HT_MO, MO, 5 Nov 09:16 to 7 Nov 12:59 BST; job 499_ht_identity_touch; pilot, about 2 days, cannot pass) **Item 407 at the real touch: spread, and any locked profit.** Rationale: item 407 reads prints; a sampled HT/FT book in play shows 1.04 back, 950 lay on most runners, so the question is whether the gap can be taken at all. Rule fixed before any touch is summed: X is the runner on the last HT_MO row of the game with back and lay both at or under 1.2, no such row no game. Snapshots at minute 52 or later and after that row, X/F on HTFT and F on MO on the same ts. Print the median spread in points for each market and the share with lay within 5% of back. Lock: back X/F at back_px and lay F on MO at lay_px, or lay X/F and back F, worst outcome after 2% on the winning market only; count snapshots and games with worst above zero, the size on the thinner side, and whether the next snapshot still locks. No result or hold, so no bar applies: a lock with size earns a stream read, none closes the riskless form of the idea.
"""
open(p, 'w').write(s)
print('ok')
