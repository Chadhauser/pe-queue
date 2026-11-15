p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
assert '\n456. ' not in s and s.rstrip().splitlines()[-1].startswith('455. ')
item=("456. RUNNING 2026-11-08 (lane A, 13:40 UTC run) (Finder's own, source c and d: no ledger line reads the football pre-match path on bf_hist_other, items 469 and 465 read stream_ticks only, n 1,222; "
"tables bf_hist_other, bf_hist_result; job 499_mo_premarket_drift from jobs/499_ou05_late_full.sh) **Match Odds pre-match drift: enter hours before kick-off, trade out at the last pre-off print.** "
"Rationale: a pre-off swing needs no result and pays both ways if early prices lean one way into the off (money arrives late on favourites, thin books early); the loader holds MO Jan 2023 to Sep 2026, "
"about 60% of markets print 6 h out and 96-99% in the last 15 min (coverage counted, no price read). Rule fixed before any price is read: entry = the last print of the runner in [KO-W-1h, KO-W], "
"W = 24 h, 6 h, 2 h; exit = the last pre-off print of the same runner in [KO-30 min, KO+10 min]; if none, the first in-play print within 10 min of its first in-play print; if none, the official MO result "
"(never dropped). Back at one tick adverse, out by laying one tick adverse (and the mirror for a lay, GBP 10 liability), 2% on a green profit, entry prices 1.01-20 only. "
"Scored lines: W x entry band (1.01-1.6, 1.6-2.5, 2.5-4, 4-8, 8-20) x back or lay = 30, one runner per game per line (the shortest in the band); women and youth out; halves by date median. "
"Role (HOME, AWAY, DRAW) and year printed for reading only.\n")
open(p,'w').write(s.rstrip('\n')+'\n'+item)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
t=t.rstrip('\n')+'\n'+("2026-11-08 | c/d (bf_hist_other, bf_hist_result) | MO pre-match drift, enter 24/6/2 h before KO by price band, trade out at the last pre-off print, rule fixed (499_mo_premarket_drift, item 456) | RUNNING | -\n")
open(h,'w').write(t)
print('ok')
