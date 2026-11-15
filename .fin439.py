p='watchman/FINDER_QUEUE.md'
t=open(p).read()
i=t.index('\n439. RUNNING 2026-11-08 ')+1
old='439. RUNNING 2026-11-08 '
new=("439. DONE 2026-11-08 — nothing passes, 0 of 36; 7,869 games, Sep 2024 to Apr 2025; win rates match implied in every cell, so no long-shot bias in running; "
"best ALL W20 20-50 lay n 15,685 +0.011 t 0.74 t_game 1.05 h1 -0.011 h2 +0.033; all 18 backs lose -0.49 to -3.25; 38,438 of 46,573 markets had no af/fd result -> item 441; "
"jobs/499_cs_longshot_ip.sh, reports/finder_2026-11-08_item439.md ")
assert t[i:i+len(old)]==old
t=t[:i]+new+t[i+len(old):]
assert '\n441. ' not in t
line=("441. TODO (Finder's own, source c, lower leagues, from item 439's counts; tables bf_hist_other, bf_hist_result; job 499_cs_longshot_minor to write from jobs/499_cs_longshot_ip.sh) "
"**Item 439's in-play long-shot CS lay on the leagues af_fixtures and fd_matches do not hold, settled on Betfair's own result.** "
"Rationale: item 439 found the long CS lines priced fair, but scored only 8,135 of 46,573 markets; the 38,438 unscored are the minor and foreign leagues, "
"thinner books where a favourite-longshot bias is likelier, and they were never read. First step, before any price: count the CORRECT_SCORE winners bf_hist_result holds "
"for those markets, Sep 2024 to Apr 2025; if under 3,000 markets, BLOCKED for the loader (a re-read of the Betfair files for results, as item 245). "
"Rule fixed now, no new cuts: item 439's windows, bands, fill, ALL and ONE, costs and bar exactly, on markets with no af/fd result only, settled to the bf_hist_result winner; "
"games with both a result and a bf_hist_result row (item 439's) used as the check that the two agree, at least 99%.\n")
k=t.index('\n440. '); j=t.index('\n',k+1)
t=t[:j+1]+line+t[j+1:]
open(p,'w').write(t)
h='watchman/HYPOTHESES.md'
add=("2026-11-08 | c (bf_hist_other, af_fixtures, fd_matches) | long-shot Correct Score runners in running, priced 10-200, at three clock windows (499_cs_longshot_ip, item 439) | DONE | nothing passes; 0 of 36; best W20 20-50 lay n 15,685 +0.011 t 0.74; won equals implied in every cell\n"
"2026-11-08 | b published (none on the box) | new-manager bounce at the first in-play print (item 440) | BLOCKED | no coach data on the box; needs API-Football coach dates from the loader\n"
"2026-11-08 | c lower leagues (bf_hist_other, bf_hist_result, from 439) | item 439's long-shot CS lay on the 38,438 markets af/fd do not hold, settled on Betfair's result (item 441) | TODO | -\n")
s=open(h).read()
if not s.endswith('\n'): s+='\n'
open(h,'w').write(s+add)
print('ok')
