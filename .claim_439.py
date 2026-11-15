import re
p='watchman/FINDER_QUEUE.md'
t=open(p).read()
assert '\n439. ' not in t
line=("439. RUNNING 2026-11-08 (lane A; Finder's own, source c; ledger and queue searched for in-play correct score, long shot, CORRECT_SCORE: "
"item 114 read CS before the off, item 115 the current scoreline in-play, item 25(d) 0-0; tables bf_hist_other, af_fixtures, fd_matches; job 499_cs_longshot_ip) "
"**Long-shot Correct Score runners in running: lay or back the scorelines priced 10-200.** Rationale: a 19-runner book in play holds many lines two or more goals away, "
"where a favourite-longshot bias should be largest, and no read has priced them. Rule fixed before any price is read: Sep 2024 to Apr 2025; windows by clock from the off, "
"W20 off+20..25 min, W55 off+70..75, W80 off+95..100; first in-play print of each runner in the window, filled at the worse of it and the next within 120 s, one tick adverse; "
"bands 10-20, 20-50, 50-200 on the fill; back and lay; ALL runners (t_game over per-game means must also reach 3.5) and ONE per game, window and band (nearest 14.1, 31.6, 100); "
"held to the final score from af_fixtures or fd_matches, so nothing drops; 2%, GBP 10 risk; halves by median date; standard bar.\n")
# insert after item 438's line
i=t.index('\n438. ')
j=t.index('\n',i+1)
t=t[:j+1]+line+t[j+1:]
open(p,'w').write(t)
print('ok')
