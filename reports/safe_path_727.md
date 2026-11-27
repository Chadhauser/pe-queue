No real order was placed. Switch OFF: REAL_MONEY_OFF present yes, ON file absent yes, order calls to the exchange made by this job: 0.
TIER ONE (trading). Money: £0 real. Items 1-4 DONE and proved; item 5 (the 2-day dry run against T1) RUNNING since 27 Nov 14:17:54 UTC, ends about 29 Nov 14:18 UTC. Nothing is BLOCKED.

**Read first (decisions only Peter can make):**
1. **The £20 daily loss limit will stop T1 every day at £2 stakes.** It counts every open order at its full £2, and a T1 bet stays open about 2 hours. So the 10th order open at once stops the day (£18 open + £2 = £20). On the trial's own days (22-26 Nov) that would have happened at the 14th to 34th order of the day; T1 makes 28-127 orders a day. Built exactly as ordered. If you want "refuse this one order and wait" instead of "stop for the day", or a higher limit, that is a code change for your yes.
2. **Real bets after 14 Oct.** Betfair's own records (read-only, 27 Nov) show 269 real bets placed 15 Oct-8 Nov, last at 8 Nov 22:08 UTC: mostly £2 back-and-lay pairs on Over 2.5 goals, -£13.20 in all. The readiness report said the last real order was 14 Oct. The logs did not show which program placed them. Every program that could have done it is now locked.
3. **Secrets in old code:** /root/pe-bot/bot_core.py lines 15-17 hold a Betfair app key and the Railway database password. They were not copied anywhere except the untouched archive original (mode 600). Both should be changed. runner/creds.py still falls back to reading them.

**1. ONE PLACER - DONE.** Built: lock727.py locked 25 files after copying each original to /root/pe-archive/placers_locked_27nov/ (MANIFEST.md lists each file, its checksum before and after, and the change). The files are the 9 programs in the report (bot_core with trade_bot, tennis_bot, decay_bot, ltd_live, late_over_live, pg_bot, prematch_bot, auto_bettor, brain/betfair.py), plus 5 old queue jobs that would rewrite pg_bot, ltd_live and late_over_live with the order call, in all 3 copies of the queue repo. In each file every order call now raises "LOCKED 727", each program's first line exits, and execute bits are off. The two libraries that running recorders import (bot_core, brain/betfair) get no exit when imported, so the recorders are untouched; only their send call refuses. The job lock is committed to the repo (55f8eac4), because the finance runner resets its copy every 2 minutes. Searched: every .py and .sh under / (not /proc, /sys, /dev, /run, Python library folders, node_modules, .git, or the archive). The search looked for Betfair place/cancel/replace/update order calls (as a call, a URL or JSON-RPC), library order methods, Smarkets /v3/orders and Matchbook /offers. Cron lines are all commented (#PAUSED-543). There are no systemd units or timers, and no watch.list lines. Their keepalive scripts are not in cron. An hourly check (onecall.py) writes a BREAK if any other file gains a call, a locked file changes, placer.py changes, or the switch is not fully off.
Tested: each locked file run under a system-call tracer: "RESULT: 26 PASS, 0 FAIL", every one "exit 1 | network connects 0 | says: LOCKED 727" (a control run that does connect counts 1). Search: "files with an order-sending call: 1 (/root/pe-real/placer.py); problems: 0". Pattern tests: all 24 originals that hold a call are found (trade_bot holds none of its own); prose mentions, the locked files and a planted file behave as expected. Tests for item 1: 4 passed, 0 failed.

**2. THE OFF SWITCH - DONE.** Built: /root/pe-real/placer.py, the only file holding the send call. Before every order, in this order, it needs all five:
- REAL_MONEY_OFF absent;
- REAL_MONEY_ON a plain root-owned file naming exactly this rule;
- real.gate passed, with a date, who = Peter, and the chat words;
- the control row enabled;
- the latest login good and under 10 minutes old.
Anything missing, unreadable or erroring refuses, and the reason goes to the database row and placer.log. Paths are written in the code: no environment variable, flag or config can change them. A placer with test paths cannot be given the real sender. Dry mode runs every check, writes the row and stops one line before the sender. The dry runner locks its own process to dry mode.
Tested (20 passed, 0 failed, all with a fake sender and temporary files and tables):
- default = refused, all reasons listed;
- OFF present with everything else on = refused, OFF the only failing check;
- refused: ON missing; ON names T2; two names; empty; not root's; a symlink; a folder; not text;
- refused: gate missing; gate without Peter's words; control off or missing;
- refused: login failed; login 11 minutes old; unreadable switch; a check that errors;
- all good = exactly one send (BACK, LIMIT, LAPSE, £2.00 at the best back price);
- the real sender refuses bad orders by itself. Network calls attempted: 0; real sender reached: 0.
Production state now: "REAL_MONEY_OFF present: yes | ON file absent: yes | real.gate rows: 0 | real.control: T1 enabled=False | real-mode rows: 0, sent: 0".

**3. STAKE CAP AND DAILY LOSS LIMIT - DONE.** Constants in placer.py:
- MAX_STAKE 2.00 and ABSOLUTE_MAX 50.00 (the sender checks £50.00 again with its own figure);
- backs only, LIMIT at the best back price, LAPSE at the off, no chasing;
- one order per match, enforced by the check and by a unique key in the database;
- 60 a day;
- DAILY_LOSS_LIMIT 20.00: today's settled loss + every open order + this one; at or past it the placer stops for the UK day, writes a BREAK, and the stop is kept in real.day_stop by date;
- the bank book's limits (20% at risk, 5% a match, -3% rule, -6% book of £2,000), checked against bankbook.py.
Tested (11 passed, 0 failed):
- £2.01 refused, £2.00 sent;
- £50.01 refused with MAX_STAKE raised to £100, and again with ABSOLUTE_MAX also raised;
- a lay refused; a second order on the same match refused (and the database rejected it directly);
- 60 sent and the 61st refused;
- with no loss, orders 1-9 sent and the 10th trips;
- with £8 lost, orders 1-5 sent and the 6th trips (8 + 10 + 2 = 20); still stopped after a winner settles and after a restart; runs again the next day;
- dry mode counts the same limits.

**4. THE GUARD - DONE.** The original is archived first. Why it was quiet: its login uses creds.py and works today. In 506 runs it crashed 3 times on a reply that was not Betfair's (it wrote nothing). A refused login would have printed "0 bets": that was the bug. Now any failed login, timeout or bad read is a BREAK "guard could not log in / could not read". "0 bets" only comes after a good login and read, with both times. It also reads open real orders and states the switch.
Tested (4 passed, 0 failed): forced bad login wrote "BREAK: guard could not log in (RuntimeError: login refused: INVALID_USERNAME_OR_PASSWORD); real bets were NOT checked this hour; REAL_MONEY_OFF present: yes; ON file exists: no". Real run: "2026-11-27T13:53 real settled bets 24h: 0, £+0.00; current (unsettled) real orders: 0 (login ok 13:53:50 UTC, read ok 13:53:50 UTC); REAL_MONEY_OFF present: yes; ON file exists: no".

**5. DRY RUN AGAINST T1 - RUNNING.** Built: t1_live.py uses the trial's own code and loader with T1's frozen rule, at the start minus 125 s, on live recorded prices. Each pick goes to placer.py in dry mode at £2, into real.intended_orders, with every check, would-send and why not. It is kept alive through the mechanic's watch.list. The hourly comparer writes dry_run_t1.md and pushes it, with a cause for each mismatch. The daily reconciler (dry form) writes real_vs_paper.md after 07:00 UK.
Tested (5 passed, 0 failed): the dry runner's process cannot send; it uses the same code and rule; three recorded markets give the trial's exact team and price; tick and slippage arithmetic; dry settlement (a £2 win at 2.04 = +£2.04, lost -£2.00, non-runner £0).
First live check (15:00 UTC kick-offs, 27 Nov): **4 of 4 matched**. The dry runner decided at 14:57:55 and picked Neftchi Baku 1.76, Al-Ittifaq Maqaba 1.85, Vysocina Jihlava 1.48 and Faroe Islands U19 (W) 1.14. The trial's T1 rows, written at 14:58, have the same 4 markets, teams and prices. Both skipped the fifth market (no two-sided quote). All 4 dry rows: limits ok, would send = no (switch off).
Replay of 27 Nov morning: 53 of 57 matched. The other 4 all had prices that moved in the 5 seconds between start - 125 s (as ordered) and the trial's start - 120 s.
- Faults in my new code, fixed: (a) after a restart it wrote late rows for markets already past their moment; they are now recorded as missed, and the 2 days restarted from that fix (first start 14:03:36, kept in dry_started.history); (b) its schedule saw too few markets and now looks back 60 minutes.
- My operational mistake, fixed: my two keepalive lines lacked a final "&", which held the mechanic for 9 minutes (14:10-14:18 UTC). The finance runner reset its repo copy once (13:44 UTC) because of my uncommitted lock edits.
- Findings in how the trial records (not edited): the shared price loader crashes on a small batch of markets that all have different kick-off times (worked around inside the dry runner only); the book recorder has failed every 30 s since 05:47 UTC ("cursor already closed"; trial and dry run read the same tables, so both are affected the same).
- Commission (read-only): 1.96% charged on 64 winning markets, in line with the paper's 2%.

- Small known fault, left alone: the dry runner's log line shows "nan" where the match name should be, because the trial's order frame carries no name. The orders themselves are keyed by market and team, so this is cosmetic. I did not restart the runner to fix it.

Final run (27 Nov 14:36 UTC, files work/test_run_final.txt and work/onecall_final.txt):
- test file: "RESULT: 44 passed, 0 failed; network calls attempted in tests: 0; real sender network calls: 0"
- one-file search: "2026-11-27T14:36Z one-placer check: files with an order-sending call: 1 (/root/pe-real/placer.py); problems: 0"

What I need from you: nothing for the dry run. Before any real order: (1) your choice on the £20 stop-the-day behaviour above; (2) T1 must first pass the proof gate (it is still a trial); (3) then your yes in this chat. The key and the password in bot_core.py should be changed.
