# Football form guide against the price — FIRST PAGE, 27 Nov 2026 14:50 UTC (work continuing; final page later today)

Paper only. No order endpoint anywhere. Exchange prices only.

## Form guide
**What it is made of:** each team's goal margin (capped at 3) and chances made minus chances allowed (expected goals where held, else shots on target), both measured against the strength of the opponent and weighted towards recent matches, plus what it does at home and away beyond that, rest days, playing abroad, and whether it keeps beating or failing its exchange price; 224,150 matches, 49 competitions (20 football-data divisions down to the National League, 29 API-football competitions incl. MLS, Brazil, Argentina, Japan, Scandinavia, Champions and Europa League), table `football_form.form_rating` (448,300 rows, 1,403 teams, to 26 Nov).
**Fitted on the past only** (speeds chosen on 2017-24, outcome model fitted before 1 Jul 2024, the price part on 2024-25), **tested on 8,863 matches it never saw** (25 Jul 2025 - 2 Nov 2026, those with a Betfair exchange start price).

- **Higher-rated side won 49.4%; the price gave it 49.2%.** Where form and price disagreed on who was better (7,732 matches), form's side won 52.3% against 51.9% priced. Before the start the exchange price already holds what our form knows: price alone scores 0.9946 (lower is better), price plus our form 0.9953, our form alone 1.0161.
- **Where form says a side is underpriced, it is not:** form 10+ points above the price: won 27.6%, priced 30.7%, -17.7 per £100 backed at the start price.
- **The opposite side is the sign:** where the PRICE rates a side 10+ points above our form, that side won 55.2% against 52.1% priced, **+4.4 per £100 at the start price, first half +3.3, second +5.4** (1,282 bets). It grows with the gap: 12+ points +7.8 (777 bets, +11.7 / +4.1), 15+ points +14.1 (385, +17.9 / +9.8). Away sides +7.2, prices 2.0-3.0 +9.4, both halves positive. Reading: the market has news our results do not (team news, transfers, a new manager) and still has not moved far enough.
- These are history prices (football-data's record of the Betfair exchange start price, depth unknown): a measure, not money. **£ a day at real prices: being measured now** on our own recorded quotes (20 days, 31 Oct - 19 Nov, plus 20-26 Nov from the book recorder).

**Still running (on this page by tonight):** £ a day at real recorded prices; in play (who comes back from behind and who folds, against the half-time price); the known rules inside each type and the thin markets; the watch card and score sheet for Peter's big games.
