# Finder 2026-11-03 — item 0e: related-market arbitrage inside one football game (job 466)

**Data:** liq_sample, 29 Oct 03:33 → 3 Nov 19:46 UTC, 2.54 M rows, 1,274 games (1,268 with at least one pair); MO, DNB, AH ±0, CS, BTTS, OU15/25/35.
All markets of a game share one `ts` per snapshot, so legs are synchronous. Score from goal_timeline 60 s before each snapshot (lagged; 153 games
unmatched, so the full outcome grid is used, which is conservative). Halves: h1 < 1 Nov ≤ h2.

**Method:** for each game × snapshot × pair, an LP chooses the backs and lays at the touch (only legs with ≥ £2 available) that maximise the
**guaranteed** (worst final score) P&L per £1 at risk, after 2% commission on every winning bet. Versions: TOUCH, and ADV (one tick adverse
on every leg). A "cross" arb is one whose margin beats the best single-market margin in the same snapshot. **Honest P&L:** the weights found
at snapshot k are filled at snapshot k+1 (one tick adverse; legs that have gone are not filled) and scored at the worst outcome. One trade
per game × pair × run.

**Recorder defect found:** in 24 games the MO home runner is labelled `AWAY`, so each snapshot has two `AWAY` rows and no `HOME`. Those MO
markets were dropped; before the fix they produced fake 100% DNB~MO "arbs". DNB/AH teams were matched to home/away by price consistency
with MO, falling back to the name in 72 games.

| pair | snaps (ADV) | cross arbs /1,000 snaps | runs | runs ≥60 s | median margin | exec n | exec per £10 | t | h1 / h2 |
|---|---|---|---|---|---|---|---|---|---|
| CS~OU25 | 92,047 | 3.19 | 113 | 45 | 27.8% | 111 | −2.53 | −4.45 | −3.60 / −1.47 |
| CS~BTTS | 86,909 | 0.94 | 39 | 10 | 25.6% | 36 | −3.10 | −2.61 | −6.98 / −0.01 |
| DNB~MO | 92,173 | 0.28 | 26 | 0 | 11.6% | 26 | −3.26 | −6.51 | −2.84 / −3.62 |
| OU15~OU25~OU35 | 66,715 | 0.03 | 2 | 0 | 5.9% | 2 | +1.42 | (n 2) | +1.18 / +1.67 |
| AH0~DNB | 72,987 | 0.00 | 0 | — | — | — | — | — | — |
| **ALL** | | | | | | **175** | **−2.71** | **−6.13** | −4.08 / −1.45 |

Intra-market holes (a margin with no cross-market gain): CS~BTTS / CS~OU25 / OU ladder run at about 8–9 per 1,000 snapshots. These are
over-round gaps inside one book, almost all in late in-play CS.

**Verdict: nothing passes.** In-match related markets on Betfair are consistent at the touch. AH0 vs DNB never showed an arb, DNB vs MO
showed one 0.3 times per 1,000 minutes and never for 60 s, and the OU ladder showed 2 runs in 6 days. The CS~OU25 and CS~BTTS
"arbs" are big (median 25–28%, some at 100%) and 52 runs meet the spec's ≥1% / ≥60 s / ≥£5 bar. But they are phantoms: they sit at
60–90' just after goals, when one book is stale or suspended or the lagged score is out of date. Filled at the next real snapshot they lose
−£2.5 to −£3.3 per £10, with only 31% of runs positive. The spec's persistence criterion alone would have called a line that loses money.
Caveats: snapshots are about 65 s apart, so sub-minute arbs are invisible here (stream_ticks has no CS, DNB or AH to check that).
Per-bet commission is slightly harsher than Betfair's per-market commission (worth well under 1%, which does not change the verdict).

**New hypothesis (queue item 19):** from the same data on 1–2 Nov (412 games), the DNB-implied probability closes only about 11% of its gap
to the MO-implied fair price per minute; a 6-point gap moves 1.3 points against a half-spread of about 6. Crossing loses, so test the
tick-level lead-lag between MO DRAW and OU25 UNDER on stream_ticks.
