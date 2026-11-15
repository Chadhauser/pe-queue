p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
assert '\n461. ' not in s
item=("461. RUNNING 2026-11-08 16:25 UTC (Finder's own, source c structural, mirror of item 31's overround capture; tables bf_hist_other, bf_hist_result; job 499_mo_underround_ko) "
"**Back the stale leg of a Match Odds book whose three last pre-off prints sum under 100%.** Rationale: item 31 found wide books (sum of implied 103%+) lose on both sides; the opposite case, "
"a book whose last prints sum under 100%, has never been read, and if one leg's print is stale it may still be long when it next trades. Rule fixed now, before any price is read: first MO market per game, "
"senior men (women and youth out), official MO result; each runner's last pre-off print in KO-10 min to KO+10 min, all three needed; S = sum of 1/ltp; t* = the latest of the three; STALE = the runner whose last print is oldest "
"(must be at least 60 s older than t*). Entry at STALE's first print after t* within 10 min (pre-off, or in-play only if within 120 s of the market's first in-play print), worse of that print and the next within 120 s, "
"one tick adverse, GBP 10 back stake, held to the official result, 2% on profit; one trade per game. Scored: U3 (S < 0.97) STALE back, U1 (0.97 <= S < 0.99) STALE back. Read only: their lay mirrors, FAIR (0.99-1.01) STALE back control, "
"O3 (S > 1.03) STALE lay, and the share of U3 entries where STALE's next print is shorter than its stale print. Months Nov 2022 to Oct 2026 as loaded (Nov 2024 to Apr 2026 LISTFAIL read as no rows); halves by date median; standard bar. "
"Prints only, so a pass earns a real-touch read on liq_sample, not a stake.\n")
if not s.endswith('\n'): s+='\n'
s+=item
open(p,'w').write(s); print('ok')
