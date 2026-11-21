# Other markets and the other side (session 15, 21 Nov 2026): tier one, money £0, paper only

Standing rule 708: every bad verdict from today's six pages, re-run from the opposite side, in the other recorded markets and on Smarkets and Matchbook. Rules: the one test (price on offer, money shown, £2 minimum, £50 cap, 2% commission), first half of the dates to find (31 Oct–9 Nov), second half to check (10–19 Nov), backs first, no lay at 5.0 or longer. Figures are **£ kept per £100, first half / second half (orders)**.

**One alternative passes both halves: lay UK/IE racing winners before the off after a 10% drift in 2 minutes. It made +3.4 (199) / +2.4 (218) per £100, £574 over 20 days, and +2.2 without its best day.** It was picked from 1,937 candidates, so it is a lead, not a result. Next: score it on 20–23 Nov once those days are cached (Mon 23 Nov).

| Idea (page) | Bad number | Best alternative | Its halves (orders) | Verdict |
|---|---|---|---|---|
| 300 winner conditions (builder_handover_7) | −15.6 / −13.0 | Racing WIN, before the off, LAY when the price rose ≥9.4% in 120 s (below 5.0), target and stop 20%, 5-min limit | **+3.4 (199) / +2.4 (218)**; worst day −£94; 13 of 17 days up | Lead. Also: flow lay +1.3 / +1.0 (894); in-play 1-tick lay +0.9 / +0.9 (3,039), bet delay not modelled |
| Cricket nearest miss (same page) | −12.2 / +11.9 | Best cricket variant of 2 sides × other types | −2.0 / −4.5 | Nothing better |
| Other-side rows 63481/82/504/513/540/542 (losses_to_profit) | 63481 −0.35 / −0.28 | Back where 63481 laid (best on the first half) | +5.8 (699) / −0.8 (757) | Fails the check. Place market: 0 orders |
| Back the over, goal coming (goal_trade) | −3.2 / −5.5 (recomputed) | Back the pressing side in match odds, 10-min hold | +6.3 (298) / +1.3 (274), but −1.3 without its 3 biggest wins; worst day −£317 | Fails. Under −2.7 / −1.5; lay the over −3.1 / +0.3 |
| v2 goal trade (goal_signal_audit 3) | −8.30 / −5.06 | Same inputs as goal_trade: see the line above | — | Same answer |
| Price trigger, over shortens 5% in 60 s (goal_signal_audit 3) | −15p / −21p per £1 | 252 variants (shorten or drift, back or lay, 21 market types, 1/3/10 min). Best with 30+ orders a half: lay match odds after it shortens, out at 3 min | −5.0 (2,346) / −7.6 (1,878). Original-like −14.0 / −12.2 | Nothing better. Draw no bet back +26.9 / +12.9 (97, 11–19 Nov only), but −11.2 without its 3 biggest wins |
| Half-time goal alerts (books C) | −0.4 to −1.1 | BTTS No after the alert | +6.5 (40) / +0.1 (13) | Too few. Correct-score +7.3 / +35.8 has 97 positions with no exit or result |
| Lead and lag (books A2) | H1 −1 to −15 | Opposite side: lay the stale Smarkets/Matchbook price after Betfair drifts ≥3%, back it on Betfair 5 s later | Matchbook +1.9 (228) / +14.9 (94) on session 11's split (3–11 / 12–19 Nov), but −1.0 / +2.1 without its 3 biggest wins; median trade −£1.6 to −£2.8. At the next poll −5.6 / −5.2 | Nothing better. The gains are 8 trades: lays at 1.02–1.03, where very little is at risk, or Betfair prices 4 to 92 times ours, which cannot both be right. Without gaps over 50%: Matchbook −1.6 / +4.9, Smarkets −4.6 / +3.6 |
| Crossed prices (books A1) | about £1 per £100, 6 a day | Opposite side is the same lock. Other markets: not recorded on Smarkets or Matchbook | — | Nothing better in what we record |
| Offering prices (offering_prices) | racing −0.73; football −1.16 | Picked on the first half: lay First Half Over/Under 0.5 at 10 min (57761) | +67.9 / −3.0 | Fails. 3431 (match odds back offer, held) +4.2 / +25.4 and 63514 +23.8 / +8.9 are both positive but under 300 orders; I did not check them without the best day |

**Markets that could not be tried, because they were not recorded on 31 Oct–19 Nov:**
- Racing place, each-way and forecast before the off.
- Tennis before the match.
- Corners and cards. liq_recorder asks for them under codes Betfair does not use.
- In-play football beyond match odds and Over/Under 2.5 before 11 Nov. After that, too thin for both halves.
- Smarkets and Matchbook outside the winner markets. Matchbook in play is "Match Odds" only.
- Racing on Smarkets and Matchbook.

The new recorder (`markets.extra_snap`, running since 16:19 UTC) covers these on Betfair from tonight: 139 types and 2,727 markets by 17:12. In the 30 minutes to 17:53 it recorded 169,060 rows across 129 types, including 39 football types and 24,266 in-play rows of other goal lines. Gaps that remain:
- Cards markets have rows before the kick-off only. There were 0 in-play rows on the 5 matches that offered them, and no corners markets were listed.
- Smarkets and Matchbook non-winner markets are still not recorded.

**Next goal: Betfair does not list one.** At about 17:45 UTC, 38 in-play football events had only FIRST_GOAL_SCORER, and that was on 4 of them. goal_signal_audit's top wish cannot be met on Betfair.

Files: /root/pe-sports/markets/s15_*.py, *.parquet. Tests: s15_test_money.py passes 7 of 7.
