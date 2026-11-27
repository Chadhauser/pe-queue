# Ready for real money? T1 readiness check, 27 Nov 2026 (read-only)
TIER ONE (trading). Money: £0 real. T1 is still a TRIAL (not paper, not proof): +£2,323.76 on 283 settled markets at the market's stake; at a flat £2 it would have been +£133.14 (+23.5 per £100, first half +£89.38, second half +£43.76). Nothing was changed, nothing was placed, no order endpoint was called. /root/REAL_MONEY_OFF exists (empty, 16 Nov 17:12). I did not touch it.

**Short answer: no. Today nothing on this server could place T1's real order, and nothing reads the real-money switch.** About 15 hours of building plus 2 days of dry running are needed (list in 4). Started now, it is ready before T1 can pass the gate.

## 1. What can place a real Betfair order today
- **Nine programs contain the Betfair call that places an order:** pe-bot/bot_core.py (with trade_bot.py), pe-tennis/tennis_bot.py, pe-decay/decay_bot.py, pe-ltd/ltd_live.py, pe-xg/late_over_live.py, pe-pg/pg_bot.py, pe-brain prematch_bot.py, auto_bettor.py and brain/betfair.py. (goaltrade/test_signal_v2.py only names the call, in a test that checks it is absent.) **None is running.** Their cron lines are commented out ("#PAUSED-543", 9 Nov).
- **Last real order: tennis_bot.py, 14 Oct 2026 04:45 UTC.** It placed 138 real orders from 3 to 14 Oct (£425.52 staked, 136 with Betfair bet numbers). Every other program's order table holds dry rows only. The Betfair guard (real_money_guard.py, hourly) has found 0 real settled bets in each of its 506 checks since 16 Nov.
- **What stops them now:** (a) not running and not in cron; (b) dry_run = true in bot_config, tennis_config and lo_control; ltd_control has enabled = false; auto_bettor has DRY_RUN, default true; (c) the pe-logger login these bots read was refused by Betfair (INVALID_USERNAME_OR_PASSWORD, bot.log, last line 16 Nov), while the recorders log in fine through runner/creds.py.
- **Do not rely on these:** /root/REAL_MONEY_OFF and the STOPPED files are read by no program and no keepalive. Order 614 said every placer must check the file, but none does. The guard also reports "0 bets" when its login fails, so a quiet guard is not proof.
- **Peter's £50 a bet limit applies only to paper:** grid/onetest.py line 13 (MAXST = 50, plus £50 lay liability) and grid/bankbook.py line 19 (CAP = 50). In the real programs: bot_core £25 hard cap, tennis/decay/prematch £10, and ltd_live, late_over_live and pg_bot have no cap in the code (the stake comes from a database row). Betfair account-side limits were not checked, because that needs an account call.
- Also: bot_core.py has the app key and the database password written into the code. Do not reuse it.

## 2. What T1 needs that no program does yet
1. **A live trigger.** T1 exists only in grid/trial.py, which every 10 minutes scores quotes that have already been recorded. Nothing acts two minutes before the start.
2. **Market selection at that moment:** football match result, under £5,000 matched, the favourite by middle price with the draw left out, both sides quoted, the quote under 2 s old. It must be the same code as onetest.select(), so the real pick and the paper pick are the same selection.
3. **The stake:** £2 flat, back, LIMIT order at the best back price, cancelled at the off ("LAPSE"), no chasing. The bank book stakes 2% of £2,000 (about £40), so the £2 rule needs its own setting.
4. **One bet per match,** enforced by a unique key in the database, not by memory.
5. **The bank book limits, live:** 20% of the bank at risk, 5% on one match, the rule stops at -3% for the day, the book at -6% (bankbook.py values). Also a daily bet count and £ cap.
6. **A log of each real order beside its paper twin** (way, market, selection, minute), with bet number, size matched, average price, and lapsed or unmatched money.
7. **Checks before every order:** REAL_MONEY_OFF absent, control row enabled, login good, stake ≤ £2 and never over £50 in the code.

## 3. Risks with real money. Measured: money on offer at the best back price two minutes before the start (favourite, under £5,000 matched)
| Stake | T1 trial orders, 22–27 Nov (385) | All such markets, 2–19 Nov (604, from the cache, including under-£2 books) |
|---|---|---|
| £2 | 100% (a book under £2 is never entered) | 96% |
| £10 | 80% | 74% |
| £25 | 66% | 59% |
| £50 | 50% | 43% |
In the second source, favourites priced 2.0–3.0 had £50 on offer only 31% of the time, and those under 1.5 had it 62% of the time. **£2 fills almost always. £25–£50 would part-fill about half the time.** We record only the best price, so the depth behind it was not measured.
Other risks: (a) the quote is about 9–10 s old when the trial "places", so the price can move before a real order arrives; (b) start times slip in these small leagues (Bangladesh, Under-21s, South America), so "two minutes before" may not be the real two minutes; (c) the paper charges 2% commission. If the account pays 5%, T1 drops from +25.6 to +23.9 per £100; (d) 5 of 283 settled at £0 (void), and real settlement must agree; (e) 64% winners at an average price of 2.05 is very strong. Real Betfair settlement is the first independent check of it.

## 4. Build list (hours). Everything except the final send can be tested without placing anything
1. t1_live.py: snapshot at the start minus 125 s, select with onetest's code, write the intended order (3 h).
2. Shared safety module: switch file, control table, hard £2 / £50 caps, one bet per match, the bank book's day limits, refuse on a bad login (2 h).
3. Order sender: LIMIT, LAPSE, customer reference = paper twin key; dry mode stops just before the send (1 h).
4. real_orders table and the link to grid.trial_trades / paper_trades (1 h).
5. Known-answer tests: switch present blocks, second bet on a match refused, -3% stop, £2.01 refused, a selection identical to the trial's (2 h).
6. Dry run for 2 days alongside the trial: every intended order must match its trial twin (1 h setup + 2 days).
7. Daily reconciler (section 5) (2 h).
8. Fix the guard: report a login failure as a BREAK and read the switch file (0.5 h).
9. Read-only check of the account's commission rate from the 136 tennis bets in Betfair's records (0.5 h).
10. Keepalive and watch.list entry. A cron line needs Peter's authorisation (0.5 h).
Total about 15 h. It cannot be tested here: a real order being accepted. After Peter's yes, the first step would be one £2 order.

## 5. Daily paper-to-real reconciliation (07:00 UK, real_vs_paper.md)
Read Betfair's settled orders for the day, including the commission actually charged, and join them to real_orders by bet number and to the paper twin. For each bet: paper price against real average price, £2 asked against £ matched, lapsed money, the result agreeing, and paper £ scaled to £2 against real £ after real commission. Totals: fill rate, average slippage in ticks, real against paper £. Any of these goes to breaks.md as a BREAK: a real bet with no twin, a real bet not from T1, slippage over 1 tick, or a disagreeing result. A twin with no real bet is listed with its reason (limit, stop, no fill).

What I need from you: nothing for this check. When T1 passes the gate: yes or no to building the list above (about 15 h), and your yes before the first real £2 order.
