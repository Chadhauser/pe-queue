# Builder session 10 handover (21 Nov 2026) - Part 1 done, Part 2 running

Part 1, paper book cleared: 96 rules were on paper; 83 came off; 13 stay.
- Test: profit in both halves of all recorded days (31 Oct-10 Nov / 11-21 Nov: one test to 19 Nov, own paper trades 20-21 Nov), still in profit without the best day, and without the best day plus the 3 biggest winners. Lays at 5.0 or longer come off whatever the result.
- Off: 26 for lays at 5.0+ (Peter's rule), 40 for a losing half, the rest for losing without the best day or the top 3 winners. Each has its reason and date in grid.paper_failed (83 rows), and in paper_end, so the paper trader no longer places for them. Their past paper trades stay in grid.paper_trades.
- Stay (13): 11410, 11412, 11931, 9408, 670, 4454 football match result; 11015, 11681 football over/under 2.5; 2633, 3093, 3993, 4079 football first-half goals 2.5; 449 tennis. None of them is racing.
- The Trades files (trades_today.md, trades_<day>.md) now show only rules still on paper (papertrader.py, backup papertrader.py.bak_session10). test_known.py ALL PASS.
