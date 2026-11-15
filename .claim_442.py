p='watchman/FINDER_QUEUE.md'
t=open(p).read()
old='441. TODO ('
assert t.count(old)==1
t=t.replace(old,("441. BLOCKED 2026-11-08 — first step failed its own bar: bf_hist_result holds CORRECT_SCORE winners on Aug 2024 only in Sep 2024 to Apr 2025 "
"(2,853 markets; Sep-Apr 0 of 49,737), under 3,000 before the af/fd games are taken out; it needs the loader to re-read those months' results (as item 245); "
"the official winners sit on Mar 2023 to Aug 2024 and May-Sep 2026, so the next door is item 442 (reports/finder_2026-11-08_item439.md) — ("))
assert '\n442. ' not in t
line=("442. RUNNING 2026-11-08 (lane A; Finder's own, source c, lower leagues and unseen months, from items 439, 441; tables bf_hist_other, bf_hist_result, af_fixtures, fd_matches; "
"job 499_cs_longshot_minor from jobs/499_cs_longshot_ip.sh) **Item 439's in-play long-shot CS lay and back on Mar 2023 to Aug 2024, settled to Betfair's official winner, "
"minor leagues apart.** Rationale: item 439 read only the 17% of markets af/fd could score, and only Sep 2024 to Apr 2025; bf_hist_result holds official CS winners on about "
"49,000 markets Mar 2023 to Aug 2024, months no CS in-play read has used. Rule fixed now, before any price: item 439's windows, bands, fill, ALL and ONE, costs and bar "
"exactly; market_time 2023-03-01 to 2024-09-01; settled to the bf_hist_result WINNER runner, a market with no single winner not scored and counted; split MINOR (no af/fd "
"result by item 439's matching) and MAJOR (af/fd result held), lines read on each and on BOTH; check: on MAJOR the official winner must equal the af/fd score on at least 99%, "
"or the job stops.\n")
k=t.index('\n441. '); j=t.index('\n',k+1)
t=t[:j+1]+line+t[j+1:]
open(p,'w').write(t); print('ok')
