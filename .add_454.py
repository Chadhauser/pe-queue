p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
assert '\n454. ' not in s and s.rstrip().splitlines()[-1].startswith('453. ')
item=("454. RUNNING 2026-11-08 (lane A, 10:45 UTC run) (Finder's own, source b and d, from item 106 which read one month only; tables bf_hist_other, bf_hist_result; "
"job 499_ou05_late_full from jobs/499_four_goal_under.sh) **Over/Under 0.5 at 0-0 by window, on the full loaded tape.** Rationale: item 106 read Over 0.5 at 0-0 on Sep 2026 only "
"(T60 back Over n 644 -0.203, PRE lay Under n 2,549 +0.059); the loader now holds OVER_UNDER_05 Jan 2023 to Sep 2026 with official results, about 20x the games. "
"Rule fixed before any price is read: state 0-0 = no Over 0.5 print at 1.05 or under before entry; entry = first Under 0.5 print in E to E+3 min after the first in-play OU print, "
"E = 20, 35, 65, 80, 95 wall-clock minutes (the break sits between 35 and 65), one entry per game per window, each window scored apart; back and lay Under 0.5, "
"worse of the print and the next within 120 s, one tick adverse, GBP 10, 2%, prices over 50 not traded, official result, never dropped; halves by date median. "
"Ten scored lines; bands by pre-off Over 2.5 price printed for reading only.\n")
open(p,'w').write(s.rstrip('\n')+'\n'+item)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
t=t.rstrip('\n')+'\n'+("2026-11-08 | b/d (bf_hist_other, bf_hist_result, from 106) | back or lay Under 0.5 at 0-0 at five windows, Jan 2023-Sep 2026, rule fixed (499_ou05_late_full, item 454) | RUNNING | -\n")
open(h,'w').write(t)
print('ok')
