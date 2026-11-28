No real order was placed. Switch OFF: REAL_MONEY_OFF present yes, ON file absent yes, order calls to the exchange made by this job: 0. Betfair's own record: 0 orders since 27 Nov 13:30 UK.

## 28 Nov 2026, 07:06 UTC (order 729, "they must match"): recorder fixed, schedule fixed, same moment as the trial. Item 5 RUNNING again: dry run restarted 28 Nov 06:58:04 UTC, ends 30 Nov 06:58 UTC
TIER ONE (trading). Money: £0 real (nothing can be sent). Replay of 27-28 Nov: **124 of 125 trial orders paired; all 125 seen by the schedule.** The one left over is the trial ordering one match twice (below). Nothing is BLOCKED.

**What was wrong and what was fixed**
1. **The book recorder** (/root/pe-sports/team/book_recorder.py) wrote nothing from **27 Nov 05:46:19 to 28 Nov 05:14:58 UTC (23 h 29 min)**. Cause: Ubuntu's automatic security update replaced a library PostgreSQL uses at 05:47:21. PostgreSQL restarted at 05:47:26. The recorder never opened a new connection, so every cycle after that failed with "cursor already closed".
   - Fixed: it now reconnects. Original archived first. Only its own process was restarted, its loop untouched.
   - Proof: 2,094 rows at 05:14:58. Then I closed its database session on purpose at 05:15:23. Its log says "database reconnected" at 05:15:28 and it wrote 1,248 rows at 05:15:59.
   - **Lost:** the order book (best two prices and money, every football market from 3 h before to the end) for 27 Nov 05:46 to 28 Nov 05:15 UTC. For scale, the same hours a day earlier held 1.93 million rows across 1,746 markets in 87 matches. It cannot be re-fetched: Betfair gives no history of the order book.
   - **Same fault, still failing, NOT touched (the order said leave the other recorders alone):** coherence_paper.py and v3_recorder.py (/root/pe-sports/team) and desk.py (/root/pe-sports/desk), all since 05:47 on 27 Nov. Every other recorder reconnected by itself. The same 6-line fix fits all three; it needs your yes. The next security update will break any program that does not reconnect.
   - **Can T1's 27-28 Nov trial numbers be trusted?** The prices, yes. All 125 T1 orders of 27-28 Nov had a live stream price in the 2 minutes before. The count, not fully. On 26 Nov (complete data), 1 of 30 T1 orders came only from the book feed. So 27-28 Nov is probably about 3% short of orders, with no wrong prices. The dry-run comparison is not affected: the trial and the runner read the same tables.
2. **The two never looked at** (1.266078510, 1.265836230, 28 Nov 00:00 UTC kick-offs). The stream gives a start of 23:59:59 on 27 Nov. The trial's loader rounds that to 00:00 on 28 Nov and files the match under 28 Nov. The dry runner did not round, so it loaded 27 Nov and found nothing.
   - Fixed: the schedule rounds to the minute, the same way the trial does. A market near midnight is also tried on the next day.
   - Test added: t5_schedule_midnight_kickoff_goes_to_the_trials_day. It passes on the new code. On the archived old code it gives day 27 Nov, so it would have caught this.
3. **The five seconds.** The dry runner now decides on prices stamped up to exactly the start minus 120 s, which is the trial's moment. It uses the trial's own quote-age rule (a quote at most 30 s old) and the trial's own code. It reads 4 s after the moment, so the recorders have written. The trial was not edited.
   - Two more fixes in my new code:
     - the loop could notice a due market up to 5 s late; it now wakes exactly on time;
     - nothing slow runs in a cycle with a decision due.
   - First live cycle: decision moment 06:58:00, read 06:58:04, rows written 06:58:05. The placer allows 10 s.
   - **Both live dry orders pair with the trial's rows, written at 07:04:57:** Kashiwa 2.26 and North District 1.54. Same moment, and the same quote to the microsecond (06:57:57.861 and 06:57:54.626).
   - Tests added: t5_decides_at_the_trials_moment, and t5_five_second_and_midnight_markets_now_pair. The second checks all 8 of yesterday's mismatches give the trial's team and price.
   - My own slip, fixed: one edit broke the hourly comparer from 06:01 to 07:05 UTC. It wrote nothing wrong, because it stops early until the new start exists. A test now runs the comparer end to end (t5_comparer_runs_end_to_end).

**Replay, 27 Nov 00:00 to 28 Nov 04:58 UTC** (the schedule rebuilt minute by minute as the loop builds it; each market decided at its moment):
- 125 trial orders, 125 seen, 124 paired (same team, back, same price, same moment).
- Still differs, 1: Poland U19 (W), market 1.266139624. The kick-off moved from 10:00 to 12:00 UTC and the trial ordered it twice, at 09:58 and 11:58; the 09:58 row is still "open". The placer allows one order per match, so a real twin can never exist for the second one. This is a finding in how the trial records; the trial was not edited.
- Left to chance: a price stamped before the moment but reaching the database more than 4 s late would still split a pair.

**Restart:** previous start 27 Nov 14:17:54 UTC and the short runs of this fix are kept in /root/pe-real/dry_started.history. New start: 1795849084 (28 Nov 06:58:04 UTC). **The 2 days end 30 Nov 06:58 UTC.**
- Test file: "RESULT: 48 passed, 0 failed; network calls attempted in tests: 0; real sender network calls: 0"
- One-file search: "2026-11-28T07:06Z one-placer check: files with an order-sending call: 1 (/root/pe-real/placer.py); problems: 0"

**For Peter**
(a) **The 269 real bets of 15 Oct to 8 Nov (-£13.20) were placed by /root/pe-pg/pg_bot.py**, the after-a-goal bot. It lays £2 just after a goal and backs out 10 minutes later.
- Evidence:
  - 268 of the 269 bet numbers on Betfair's own records (read only) are in the bot's own table pg_trades: 138 entries, 130 exits.
  - The 269th (16 Oct 20:36:20, £2.09 back at 1.29, Deportivo v Levante) is a second exit it sent 14 s before the exit it recorded on the same trade.
  - Its log (/root/pe-pg/bot.log) has the trades, down to the last one (Estrela v Benfica, 8 Nov 22:08).
  - Cron started /root/pe-pg/keepalive.sh every minute from at least 25 Oct (the oldest system log kept) until it was paused by job 543 on 9 Nov 11:05 UTC.
- Missing evidence:
  - Betfair holds no order or strategy reference on any of the 269 (0 of 269), because the bot never set one.
  - Process accounting is not installed.
  - System logs before 25 Oct are gone, so cron for 15-24 Oct rests on the bot's table and log alone.
- **Locked:** yes, since 27 Nov. Same checksum as in the lock list; it exits with "LOCKED 727" before any import (run again today: exit 1); its cron line stays commented out.

(b) **Daily loss limit, one line:** on T1's 27 Nov trial orders at £2, "count only settled losses plus this order" would have let the placer run to the 60-a-day cap: 60 orders, +£12.96, never past £11.99 down. As built, it stopped for the day at the 14th order at 10:58 UTC (£0.51 settled loss, 9 open): 13 orders, -£8.43. Worked on the 85 trial orders that have settled, with each match settled 1 h 55 min after kick-off. This is an option only; the limit is unchanged.

What I need from you: (1) yes/no to the reconnect fix for coherence_paper, v3_recorder and desk; (2) your choice on (b); (3) the app key and password in bot_core.py should still be changed.

## Closing check of 28 Nov 05:28-06:50 UTC (another session), kept as written. It was right then: the new 2 days had not begun. They began at 06:58:04 UTC, so its BLOCKED line now reads RUNNING, and the closing check should run again after 30 Nov 06:58 UTC. The 27 Nov report is in git history (a6fb0047).
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
