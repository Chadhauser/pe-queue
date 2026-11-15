p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
assert '\n479. ' not in s
item=("\n479. RUNNING 2026-11-09 02:50 UTC (Finder's own, source a, next door of item 445; tables bf_hist_other, bf_hist_result; job 499_dn24_green_exit from jobs/499_jump_down_lay.sh) "
"**Lay the Match Odds runner that shortened 2-4 points at the off, and back out 10-15 min later instead of holding to the result.** "
"Rationale: item 445's lay to the result is positive in both halves on 971 unseen games (+0.365, FAV leg n 488 +0.817) but t 1.21, as a £10 liability held 90 min is mostly result noise; "
"if the edge is an overreaction at the off it should show up as a drift back within minutes, and a greened exit cuts the variance. Never read with an exit on any month. "
"Rule fixed now, before any price: item 445's code unchanged for the signal (DN24 = first in-play print 2 to under 4 implied points under the last pre-off print, one bet a game, the larger gap, prices over 50 not traded, women and youth out); "
"lay at the worse of the first in-play print and the next within 120 s, one tick adverse, £10 liability; exit = back at the worse (lower) of the first in-play print from 10 to 15 min after entry and the next within 120 s, one tick adverse, greened to equal profit, 2% on profit; "
"if no print in that window, held to the official result, never dropped. Scored lines: MO ONE green, MO FAV green, on every loaded month (Aug 2022 to Sep 2026), halves by date median, standard bar; "
"the read also needs the months before Mar 2023 positive, printed apart. Printed: OUT and DRAW green, the share held to result, and a FLAT control (gap under 1 point either way, same exit) for the round-trip cost.\n")
s=s.rstrip('\n')+'\n'+item
open(p,'w').write(s)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read().rstrip('\n')+'\n'
t+="2026-11-09 | a moves (bf_hist_other, bf_hist_result, from 445) | lay the MO runner that shortened 2-4 points at the off, green out 10-15 min later (499_dn24_green_exit, item 479) | RUNNING | 445 to result n 971 +0.365 t 1.21, FAV n 488 +0.817\n"
open(h,'w').write(t)
print('ok')
