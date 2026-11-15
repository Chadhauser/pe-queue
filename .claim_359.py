p='/root/pe-queue/watchman/FINDER_QUEUE.md'
q=open(p).read()
assert '\n359. ' not in q
if not q.endswith('\n'): q+='\n'
q+="359. RUNNING 2026-11-07 (Finder's own, source d, from item 353; table tennis_matches, ATP only; job 499_tennis_error_close) **A tennis player's price error reverts: Pinnacle closes, unseen dates.** Rationale: item 353 read the reverse of what it set out to find: HIGH won 0.511 v implied 0.531, LOW 0.562 v 0.536, control 0.540 v 0.534. Rule fixed before any close was read: z as item 353 on closes, earlier dates, at least 20 matches, scored only on dates outside the tape (before 31 Aug 2024, after 31 Mar 2026). HIGH must read z <= -2 against |z| <= 0.5 control and LOW z >= 2. Closes are a proxy, so this cannot pass the bar; support earns a re-read on Tennis months the loader has not reached.\n"
open(p,'w').write(q); print('ok')
