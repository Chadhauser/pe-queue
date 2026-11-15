p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "487. RUNNING 2026-11-09 (claimed about 07:56 UTC, same run as 486;"
assert s.count(old) == 1
s = s.replace(old, "487. TODO (NO RESULT 2026-11-09, run time, not a code fault: the first run spent over 10 min on MATCH_ODDS alone, a full 38 GB type scan with the DISTINCT ON spilling at 64 MB work_mem, "
"and was stopped; the cut run (fit May 2024-Sep 2026, four types OU4.5, MO, OU3.5, FH1.5) stalled in the unseen pull by id, which ran 71 s for 43 chunks in job 486 but over 20 min after the stopped scan (cold cache, parallel disk reads), "
"stopped at about 08:24 UTC with no result read and its query cancelled; before a re-run: pull item 486's unseen closes once into a local table with the last-print ts, "
"print progress each chunk, and run it outside a 90-min slot or one type a night; job jobs/499_calib_fresh_unseen.sh holds the cut version; reports/finder_2026-11-09_item486.md) (claimed about 07:56 UTC, same run as 486;")
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old2 = "scored on 486's unseen markets (item 487) | TODO |"
assert t.count(old2) == 1
t = t.replace(old2, "scored on 486's unseen markets (item 487) | TODO (no result 9 Nov, run time) |")
open(h, 'w').write(t)
r = '/root/pe-queue/reports/finder_2026-11-09_item486.md'
x = open(r).read()
marker = "Scratch files from this run"
add = ("## Item 487 (next door, same run): NO RESULT, run time\n"
"`jobs/499_calib_fresh_unseen.sh` refits the map on fresh closes only (every runner's last pre-off print within 10 min of the off) and scores it on 486's unseen markets.\n"
"- **First run:** over 10 min on MATCH_ODDS alone (a full scan of the 38 GB type, with the DISTINCT ON spilling at the brief's 64 MB `work_mem`), so I stopped it.\n"
"- **Cut run:** fit on May 2024-Sep 2026, four types only. It stalled in the unseen pull by id. That pull took 71 s in 486; this time it ran over 20 min after the stopped scan, with parallel disk reads, most likely a cold cache. I stopped it at about 08:24 UTC with no result read, and cancelled its query.\n"
"- **Before a re-run:** pull 486's unseen closes once into a local table with the last-print time, print progress per chunk, and run it outside a 90-minute slot or one type a night. The item stays TODO.\n\n")
assert marker in x
x = x.replace(marker, add + marker)
x = x.replace(".add_486.py, .chk486.py, .chk486_body.py, .diag486.py.", ".add_486.py, .chk486.py, .chk486_body.py, .diag486.py, .done_486.py, .claim_487.py, .chk487.py, .chk487_body.py, .act487.py, .cancel487.py, .nores_487.py.")
open(r, 'w').write(x)
print('ok', len(x.splitlines()), 'report lines')
