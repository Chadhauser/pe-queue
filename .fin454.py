p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
old='454. RUNNING 2026-11-08 (lane A, 10:45 UTC run) '
assert s.count(old)==1 and '\n455. ' not in s
s=s.replace(old,"454. DONE 2026-11-08 — nothing passes (jobs/499_ou05_late_full.sh, reports/finder_2026-11-08_item454.md; 37,039 games Jan 2023-Sep 2026, 0 of 10; "
"Under 0.5 within 0.0-0.6 points of the result at every window, best E35 back n 8,475 -0.261, lays -0.117 to -0.374; next door item 455) ")
s=s.rstrip('\n')+'\n'+("455. TODO (re-check 22 Nov 2026, when local liq_sample holds about four weeks of OU05 books from 27 Oct; Finder's own, source c, third door of the 0-0 OU0.5 family after items 106, 454; "
"table liq_sample (mkt OU05, real touch with sizes, 120,814 rows in two days on 8 Nov); job 499_ou05_rest_touch to write from jobs/499_ou05_late_full.sh) "
"**Rest inside the OU0.5 spread at 0-0.** Rationale: item 454 found Under 0.5 priced fair at prints at every window (E20 won 0.142 v 0.138 implied, E95 0.642 v 0.639), so crossing loses the tick plus commission; "
"the only money left is the spread. Rule: at 0-0 (no Over 0.5 at 1.05 or under) at match minutes 15, 30, 50, 65, 80, rest a back of Under 0.5 at the current lay touch and a lay at the back touch, "
"filled only when a later ltp prints through the resting price within 5 min, held to the official or last-print result; report fill rate, per GBP 10 on fills, and the unfilled count.\n")
open(p,'w').write(s)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
o2="(499_ou05_late_full, item 454) | RUNNING | -"
assert t.count(o2)==1
t=t.replace(o2,"(499_ou05_late_full, item 454) | DONE | nothing passes; 0 of 10; 37,039 games, Under won within 0.6 points of implied at every window; best E35 back n 8,475 -0.261")
t=t.rstrip('\n')+'\n'+"2026-11-08 | c structural (liq_sample OU05, from 454) | rest a back or lay inside the OU0.5 spread at 0-0 by match minute, fill on a trade-through | TODO (item 455, re-check 22 Nov) | item 454 prints fair, crossing loses the cost\n"
open(h,'w').write(t)
print('ok')
