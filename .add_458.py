p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
assert '\n458. ' not in s and s.rstrip().splitlines()[-1].startswith('457. ')
s=s.rstrip('\n')+'\n'+("458. RUNNING 2026-11-08 (lane A, 14:08 UTC) (Finder's own, source c/d, breadth door of item 456 on a second market; tables bf_hist_other, bf_hist_result; job 499_ou25_premarket_drift, a rewrite of jobs/499_mo_premarket_drift.sh with the market type and labels changed, nothing else) "
"**Over/Under 2.5 pre-match drift: enter hours before kick-off, trade out at the last pre-off print.** Rationale: item 456 found MO prints barely move into the off; goal lines take late money on Overs (accumulator punters), so the Over may shorten into the off. "
"Rule fixed before any OU2.5 price is read, the item 456 rule unchanged: entry last print in [KO-W-1h, KO-W], W 24/6/2 h; exit last pre-off print in [KO-30m, KO+10m], else first in-play print within 10 min, else official result; one tick adverse each side, GBP 10, 2%; 30 scored lines W x band x back/lay; halves by date median.\n")
open(p,'w').write(s)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read().rstrip('\n')+'\n'+"2026-11-08 | c/d (bf_hist_other, bf_hist_result, from 456) | Over/Under 2.5 pre-match drift, item 456 rule on a second market (499_ou25_premarket_drift, item 458) | RUNNING | -\n"
open(h,'w').write(t)
print('ok')
