No real order was placed. Switch OFF: REAL_MONEY_OFF present yes, ON file absent yes, order calls to the exchange made by this job: 0. Betfair's own record: 0 orders since 27 Nov 13:30 UK.
BLOCKED: item 5 - the 2-day dry run has not happened. This closing check ran at 28 Nov 05:28-06:50 UK, 15 hours after the start, not 2 days. The run was then restarted by repair order 729, so the 2 days have to start again.
TIER ONE (trading). Money: £0 real. Items 1-4 re-checked and PASS today. Item 5: the comparison is NOT MATCHED (50 of 58 in the hours that ran). The fixed code matches 124 of 125 on replay but has run 0 clean live hours. The closing check should run again 2 days after the new start written in /root/pe-real/dry_started.

**1. ONE PLACER - PASS.** I ran all 25 locked old programs once each under a tracer. The result was "26 PASS, 0 FAIL": each one exited with "LOCKED 727" before any network connection (0 connects each), and the two shared libraries still import but refuse to send. The search of every .py and .sh on the server found "files with an order-sending call: 1 (/root/pe-real/placer.py); problems: 0" (28 Nov 06:47 UK). The hourly check found the same every hour overnight.

**2. THE OFF SWITCH - PASS.** I re-ran the whole test file: "RESULT: 47 passed, 0 failed; network calls attempted in tests: 0; real sender network calls: 0". It covers each off-switch condition alone and together: OFF present, ON missing, wrong rule, no gate row, failed login, unreadable switch. Only the all-good test with a fake sender sends, and it sends exactly once. Production is still fully off: REAL_MONEY_OFF present, no ON file, real.gate empty, control row disabled.

**3. STAKE CAP AND DAILY LOSS LIMIT - PASS.** These are covered by the same 47 tests. £2.01 is refused, £50.01 is refused even with the cap raised in the test, lays are refused, a second order on the same match is refused, and order 61 is refused. The £20 loss limit trips at the 10th open order, stays tripped after a restart and clears the next day. It is unchanged. Your decision on it is still open: counting every open £2 order as lost stopped 39 of 51 dry orders overnight.

**4. THE GUARD AND BETFAIR'S RECORD - PASS.** The tests forced a bad login, a timeout and a bad read. Each wrote "GUARD FAILED ... real bets NOT checked", never "0 bets". I read Betfair's record myself (read-only, login through creds.py) at 28 Nov 05:29 UK, from 27 Nov 13:30 UK. Result: settled 0, voided 0, lapsed 0, cancelled 0, open orders 0 (work/bf_since_727.txt).

**5. DRY RUN AGAINST T1 - BLOCKED (NOT MATCHED).**
- The first run went 27 Nov 14:17:54 to 28 Nov 05:27:25 UK, 15 h 09 min, with no outages: the runner logged no exit between those times. Its quiet stretches were hours with no kick-offs, not downtime.
- Over that run, 50 of 58 trial orders were matched, 7 trial orders had no dry twin and 1 picked a different team. 6 differed because a price changed in the 5 seconds between the dry runner's moment (start - 125 s) and the trial's (start - 120 s). 2 markets were missing from the dry runner's schedule. Both are faults in the new code, not in the trial.
- Order 729 fixed both. The runner now decides on the trial's own moment, and the schedule rounds kick-off times to the minute. A replay of 26-28 Nov paired 124 of 125 trial orders, and every one of the 125 markets was seen. The one left over is a second trial order on a market already ordered at 09:58; the placer's one-order-per-match rule refuses that by design.
- The restarts: 05:27:25-05:27:56, 05:59:10-05:59:41 and 06:00:56-06:01:27 UK. Order 729 was still working at 06:50 and dry_started says "waiting for the first clean full cycle". So the new 2 days have not begun.

**What a yes from you would switch on (nothing is switched on now):**
1. First, T1 passes the proof gate (100 settled forward paper bets, profit after commission overall and in each half), and the new 2-day dry run reads MATCH.
2. You say yes in this chat for T1 by name. That yes is written into real.gate (rule T1, date, who = Peter, your words).
3. The file /root/pe-real/REAL_MONEY_ON is created, owned by root, containing "T1".
4. /root/REAL_MONEY_OFF is removed.
5. The T1 control row is enabled, and the dry runner is started in real mode. That is a code change, because the runner is locked to dry mode today.
6. From then on, each T1 pick is a £2 back at the best price, lapsing at the off. That means at most 60 a day and one per match, with the £20 daily stop.

None of steps 2-5 has been done. You also still need to choose how the £20 stop works. The key and password in /root/pe-bot/bot_core.py should still be changed.

What I need from you: nothing until the new 2-day dry run ends. Then the closing check runs again.
