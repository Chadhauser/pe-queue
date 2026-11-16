<stdin>:4: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
# Verification of the replay and history tests — 2026-11-16 18:25 UTC

## A. Replay engine against the bot's real paper bets (same market, same runner, same moment)

Bot paper bets since 11 Nov (table tape): 61; found on the tape: 0; tape price within 1 tick of the bot's fill: 0 of 0.

| match | market | runner | side | bot price | tape price |
|---|---|---|---|---|---|

Result agreement (bot's settlement vs the replay's cached Betfair result), tick-level rows: 0 of 0.

## C. Settlement maths re-done independently

67 settled bets; total difference between the bot's pnl and an independent recalculation: £0.00

## B. Twelve worked examples from the history test (check any against a results site)

| kick-off | match | market | runner | cell | price 2 min before | result | profit at £2 |
|---|---|---|---|---|---|---|---|
| 01 Dec 2025 20:00 | Rayo Vallecano v Valencia | FIRST_GOAL_SCORER | Alvaro Garcia | LAY 0.10-0.15 | 7.8 | LOSER | £+1.96 |
| 21 Mar 2026 05:00 | Sapporo v Kofu | FIRST_HALF_GOALS_05 | Under 0.5 Goals | BACK 0.40-0.45 | 2.5 | LOSER | £-2.00 |
| 26 Apr 2026 15:30 | Dortmund v Freiburg | HALF_TIME_FULL_TIME | Dortmund/Dortmund | LAY 0.40-0.45 | 2.28 | WINNER | £-2.56 |
| 17 Jan 2026 15:30 | Ajax v Go Ahead Eagles | HALF_TIME_FULL_TIME | Ajax/Ajax | BACK 0.35-0.40 | 2.66 | LOSER | £-2.00 |
| 15 Feb 2026 11:15 | Feyenoord v Go Ahead Eagles | HALF_TIME_FULL_TIME | Feyenoord/Feyenoord | BACK 0.45-0.50 | 2.08 | LOSER | £-2.00 |
| 13 Dec 2025 13:00 | Swansea U21 v Wolves U21 | BOTH_TEAMS_TO_SCORE | Yes | LAY 0.65-0.70 | 1.46 | WINNER | £-0.92 |
| 16 Jan 2026 19:00 | Burnley U21 v Tottenham U21 | CORRECT_SCORE | Any Other Away Win | BACK 0.20-0.25 | 5.0 | LOSER | £-2.00 |
| 07 Dec 2025 16:00 | Sturm Graz v Grazer AK | OVER_UNDER_45 | Under 4.5 Goals | LAY 0.90-1.00 | 1.1 | WINNER | £-0.20 |
