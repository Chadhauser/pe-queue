# Goal signal audit and version 2 (session 13, 21 Nov 2026) — tier one, money £0, paper only

1. **Version 1 cannot predict a goal.** Its 2.09 million stored predictions (7 Jul–21 Nov, checked against the score feed) rank goals no better than chance: uplift over the base rate **+0.0 points (7 Jul–13 Sep) and −0.2 (14 Sep–21 Nov)**. On the unseen days 9–19 Nov its top tenth was −2.9 (first half of matches) and +6.5 (second half), from only 41–43 matches. It also predicts 38% where 27% happens.
2. **Version 2 adds +4.0 points (first half of matches) and +5.3 (second half) on the unseen days**, counting only minutes with an over price to trade. That is session 12's market inputs: money traded per minute and the over price not drifting. **None of the 10 new inputs added anything**, so none were kept.
3. **Does the goal trade pay with it? NOT YET.** Back the over, 10% stop, out at the goal or after 10 min, on unseen days: **−£8.30 per £100 (58 orders, first half), −£5.06 (248, second half)**. Without the stop: −£10.1 and −£16.0. The minutes 45–75 form from session 12 (−£0.6 per £100 without its best day) is still the closest.

Data health: the stream was 1 s old and the score feeds 58–90 s old at 17:20 UTC. There were no score feeds on 10–12 Nov, and only 719 of 2,341 matches had one.

| # | The chat's point | Verdict | Evidence |
|---|---|---|---|
| 1 | Hand-set thresholds, never scored | **Confirmed, wrong in detail.** "4 of 6, 5% in 60 s, 5 ticks, 20-min cooldown, 11 leagues" are not in the running code. What is there is also hand-set: minutes 25–75; fixed rates of 9 shots on target, 2.7 xG and 200 dangerous attacks per match; edge 2–15%; 12 league ids. The two fitted maps were fitted on a backfill that sees the final stats. None were ever scored on unseen days. | live_goal_model.py:70-109,206; origination.py:59; pattern_matcher.py:81 |
| 2 | Big history, never scored honestly | **Confirmed, now scored.** Live predictions: ranking 0.50 (0.50 = chance). **Backfill +17/+10 points is hindsight**: it spreads the full-match shots back over every minute. Half-time calls: stated 82% chance, won 81%, then 76%. Half-time stats: 0.51. 1,331 alerts all half-time; their "+£24 per £100" uses a fixed price, real prices gave −£0.4 to −£1.1 (session 11). Calibration fitted once (4 Sep); its daily refit fails. | audit_history.md |
| 3 | Price trigger fires after the news | **Confirmed.** The old code has no price trigger: its in-play price reads have failed 203,620 times ("bf_price_log does not exist"), so no in-play alert was ever stored. Tested the chat's rule anyway: after an over shortens 5% in 60 s, goals run at the base rate (+0.3 / −2.9 points). Backing then laying 1/3/10 min later loses 15/15/18p per £1 (first half) and 21/27/32p (second half), against 6.5/7.7/10.2p at any minute. | v2_results.md |
| 4 | No stop, no drift cost, no side, no first half | **Confirmed.** The only exit is the clock (minute 75–85). **Fixed in the test:** a 10% stop and the drift cost are counted, and both halves are scored; still a loss. Side: the wrong team scoring costs £71–81 per £100 (session 12). | position_monitor.py:73-97 |
| 5 | Inputs died silently | **Confirmed.** Goal events stopped 8 Nov; stats had 0 rows on 9–15 and 19 Nov; the score feed had 0 rows on 10–13 Nov. Railway's monitor kept reporting "635 live" with rising fire counts to 19 Nov. Lost rows: 9,300 predictions and 932 score-feed rows (duplicate key), 4 boot failures. **Fixed in v2:** no match is scored if the stream is over 60 s old, and none fires without a score under 3 min old. Health is written every cycle (goaltrade.v2_health). watch.list now has v2 (gs2) and book_snap's recorder (bookrec). Stream, ESPN and Sofascore were already listed. The api-football score feed belongs to the old monitor, so it has no line: the mechanic could edit the old code. | monitor_ht.log |
| 6 | Stats late; the market is instant | **Confirmed.** Goals show a median 1.6 min late (90th percentile 6.8 min) on api-football and 2.2 min (8.1 min) on ESPN. Stats exist on only 14% of minutes. v2 runs on prices and refuses to fire when the match odds just jumped but the score feed has not changed. | cache/audit_lag.json |
| 7 | Stats against fixed levels, not the price | **Confirmed.** The price's own goal expectation is now an input. It does not answer "more goals than the line implies": v2's top tenth scored 30% where the price implied 33%, and that baseline itself overstates goals by about 10 points. Found a bug in session 12's version: with no over price it returned near-certainty. | v2_fit.py |

**Version 2 is running:** `signal_v2.py` (paper only, reads our own database only, 9/9 tests pass). Every cycle it scores every in-play football match on the stream, not 11 leagues: 37 at 17:20, of which 25 were scored and 9 had no score feed. Its top tenth goes to **goaltrade.signal_v2** with the reason in plain words and a paper entry price; 2 signals by 17:22. **(c) not wired:** no goal-trade paper trader exists, because session 12 put nothing on paper. Each signal row stores its entry so it can be settled later.

**What would help most that we don't have:**
1. A next-goal market. It has no time drift, which is the 22–54p per £1 that kills this trade. Session 15 says it is adding it tonight; I have not checked.
2. Over 0.5 and 1.5 lines on the stream. Today v2 often has to back Over 2.5 at 9.0 at 0–0.
3. A score feed under 30 s on every match.
4. Correct-score prices in play: recorded only from 10 Nov, on 0–4% of minutes.

Next test: **29 Nov**, rerun with 22–28 Nov, then score v2's own signal rows.

Files: /root/pe-sports/goaltrade (audit_history.py, audit_matchstats.py, v2_build.py, v2_fit.py, v2_results.md, signal_v2.py, test_signal_v2.py).
