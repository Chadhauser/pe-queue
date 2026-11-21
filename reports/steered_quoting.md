**1. Steered quoting before the start: NO. Steering does not turn offering into profit on unseen days under both fill models (a few football versions do under through-only fills alone). Nearest at £25: football match result, stand aside when jumpy (c1), −£54 a day queue / −£42 through-only on 10–21 Nov, about 102 markets a day; racing's steers lose −£66 to −£118 a day (through-only −£71 to −£225) on 26 races a day, less than the unsteered −£289 only because they trade less (per £100 they lose more). 0 of 720 racing and 0 of 480 football versions pass (6 football versions made money on 10–19 Nov; none also on 20–21 Nov and without its best day under both models). The steer cuts the move against us in the first 30 s but nearly doubles it at 2 minutes: session 7's conditions catch a bounce, then the price carries on.**
**2. Thin football markets priced from deep ones: NOT YET. The goals model fits (0.6–1.7 points of probability) and the thin markets' mid sits close to it (median 1–6% away), but offering around fair loses on 10–15 Nov in every market and margin under both fill models (−7 to −9 per £100 closed, −5 to −12 held). Picked on 10–15 Nov, no market profits on both halves under both models; nearest first-half under/over 0.5 closed by offer at 1%: +1.8 / +1.7 per £100 and +£17 / +£11 a day at £25 on 17–21 Nov (62 markets a day with a fair price, fills in 24–36), but −1.3 / −2.7 on 10–15 Nov and in loss without its best day. Thin markets trade 4–10 times an hour before the start; half-time/full-time and book-only lines too rarely to model.**
**3. On paper now: unchanged, 13 rules (449, 670, 2633, 3093, 3993, 4079, 4454, 9408, 11015, 11410, 11412, 11681, 11931). No quoter went on paper (nothing reached YES). Part 3 not run: the goal predictor has no uplift over the price on unseen days (−3.5 points against what the over price expects), so there is nothing to steer with.**

Tier one. Money: £0 (paper only, no order endpoint called, nothing deleted; backups *.bak* before every edit). Data: Betfair stream before the off, 2–21 Nov (20–21 Nov from the live tables, settled markets only); football thin markets 10–21 Nov (no over/under 2.5 on 16 Nov, so no fair price that day).

**What it DOES support / next door.** (a) In racing the steer turned the other way (offer the side session 7 says will lose) beats the control like for like (quote from 10 min, out 30 s, close at one tick: −0.68 / −0.80 per £100 queue against −1.25 on 10–19 Nov; the 2-minute move against a fill falls from 0.43 to 0.21–0.32 ticks), but at each one's best setting it is no better (−0.65 / −0.69 against −0.56). Still a loss. (b) Football match result, the same opposite steer, position carried into the match (BET): through-only +4.3 / +2.5 / +8.8 per £100 (first half / 10–19 / 20–21 Nov), queue −0.7 / +0.2 / −0.2; fails the both-models bar. (c) Thin markets: two slices pass both halves under both models (both-teams-to-score lays under 2.0 at 3% closed by offer, +0.3 to +1.7 per £100, 100–150 fills a half; correct-score backs priced 5–10 at 1% held, BET), but 2 of 64 slices is about what chance gives. **Next door, 29 Nov:** rerun (b) and (c) unchanged on 22–28 Nov (`s14/run14.py fb_mo` with S14_STEERS=r1, `s14/p2_*.py` for the new days, now with session 15's second recorder giving every over/under line and racing place markets). Paper only if both models are positive on the new week.

## Part 1 — steered quoting (session 10's quoter `s10/mm.py` unchanged + per-moment switches; session 7's conditions and features)
Steer score at each quote: number of session 7's first-half pre-start conditions met for a back (price expected to shorten) minus those for a lay (racing win 9 / 8 conditions, football match result 3 / 4; tennis has none and is not on the stream before the start). (a) only the favoured side, lay under 3.0; (b) both sides, the side the score is against pulled; (c) as (b) and stand aside when both sides' conditions fire or the market is jumpy (another runner's 2-minute move or this runner's 30-second move above the first-half 90th percentile: racing 0.61 / 0.108 log, football 0.048 / 0.015); (d) unsteered control; 1 / 2 = score needed. r = rule 708's opposite side. Fitted on 2–9 Nov only. Same quoter, sizes, stops (1/2/3 ticks), time limits (out 60/30/10 s, or BET), closing styles and £50 cap as session 10. On 5 and 14 Nov the racing conditions called the next 30-second move right 53–55% of the time (48–52% for all moments); football 48–51%.

Version picked on 2–9 Nov (queue model), judged on 10–19 Nov and 20–21 Nov. £25. Each cell queue / through-only.
| Market, form, steer | Version | Fills 10–19 | Round trips | Round trip earns | One-sided costs | Price after 30 s* | after 2 min* | £/£100 2–9 Nov | 10–19 Nov | 20–21 Nov | £ a day 10–21 | Worst day | Without best day | Markets a day |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Racing trade, d control | quote 30 min, out 10 s, stop 3, moving | 21,850 / 8,734 | 88% / 66% | £0.00 / £0.09 | −£0.92 / −£1.69 | +0.21 / +0.40 | +0.36 / +0.73 | −0.53 / −1.30 | −0.56 / −1.70 | −0.59 / −1.34 | −£289 / −£474 | −£540 / −£931 | −£3,472 / −£5,683 | 26 |
| Racing trade, a1 favoured side only | 2 min, 10 s, 3, moving | 4,512 / 1,555 | 82% / 53% | £0.05 / £0.33 | −£1.13 / −£1.92 | +0.17 / +0.50 | +0.96 / +1.91 | −0.80 / −2.19 | −1.04 / −2.80 | −0.85 / −2.46 | −£78 / −£119 | −£227 / −£250 | −£940 / −£1,433 | 26 |
| Racing trade, b2 pull the side against | 2 min, 10 s, 3, moving | 8,304 / 3,385 | 85% / 60% | £0.02 / £0.16 | −£0.94 / −£1.84 | +0.21 / +0.47 | +0.57 / +1.22 | −0.55 / −1.56 | −0.60 / −2.15 | −0.61 / −1.68 | −£116 / −£225 | −£243 / −£505 | −£1,387 / −£2,695 | 26 |
| Racing trade, c2 stand aside | 2 min, 10 s, 3, moving | 7,087 / 2,679 | 85% / 60% | £0.01 / £0.12 | −£0.99 / −£1.86 | +0.21 / +0.50 | +0.43 / +1.24 | −0.55 / −1.56 | −0.65 / −2.28 | −0.68 / −1.79 | −£109 / −£190 | −£207 / −£471 | −£1,310 / −£2,282 | 26 |
| Racing trade, r2 opposite side | 10 min, 30 s, 3, moving | 14,434 / 3,408 | 89% / 72% | −£0.02 / −£0.02 | −£0.96 / −£1.37 | +0.21 / +0.42 | +0.34 / +0.70 | −0.67 / −1.70 | −0.69 / −1.48 | −0.64 / −1.46 | −£180 / −£155 | −£443 / −£282 | −£2,161 / −£1,854 | 26 |
| Football result trade, d control | 10 min, 10 s, 3, moving | 3,618 / 2,313 | 54% / 37% | £0.09 / £0.21 | −£0.64 / −£0.74 | −0.22 / −0.21 | −0.09 / +0.06 | −0.60 / −1.07 | −1.11 / −1.35 | −0.71 / −0.75 | −£88 / −£85 | −£279 / −£313 | −£1,111 / −£1,045 | 106 |
| Football result trade, c1 stand aside | 10 min, 30 s, 3, moving | 2,660 / 1,659 | 54% / 37% | £0.09 / £0.24 | −£0.61 / −£0.67 | −0.20 / −0.28 | −0.20 / −0.23 | −0.40 / −0.97 | −1.02 / −1.14 | −0.23 / +0.34 | −£54 / −£42 | −£118 / −£117 | −£666 / −£525 | 102 |
| Football result trade, b2 | 10 min, 10 s, 3, moving | 3,525 / 2,266 | 53% / 37% | £0.09 / £0.24 | −£0.60 / −£0.65 | −0.20 / −0.13 | −0.08 / +0.10 | −0.45 / −0.95 | −1.04 / −1.10 | −1.15 / −1.04 | −£90 / −£74 | −£266 / −£305 | −£1,137 / −£945 | 105 |
| Football result trade, a1 | 10 min, 10 s, 3, moving | 958 / 595 | 37% / 24% | £0.16 / £0.37 | −£0.64 / +£0.49 | −0.20 / −0.29 | +0.01 / −0.02 | −1.40 / −1.60 | −1.62 / +1.72 | −1.96 / −0.69 | −£32 / +£22 | −£84 / −£78 | −£420 / −£274 | 46 |
| Football result BET, c1 | 10 min, held, 2, moving | 3,447 / 2,214 | 43% / 27% | £0.14 / £0.36 | −£0.26 / −£0.86 | −0.22 / −0.31 | −0.18 / −0.22 | +1.13 / +0.40 | −0.38 / −1.82 | +1.09 / +1.31 | −£4 / −£79 | −£138 / −£253 | −£363 / −£1,119 | 103 |
| Football result BET, r1 opposite side | 10 min, held, 3, fixed | 858 / 430 | 44% / 39% | £0.25 / £0.38 | −£0.14 / +£0.82 | −0.16 / −0.14 | −0.10 / −0.03 | −0.65 / +4.30 | +0.16 / +2.50 | −0.15 / +8.79 | +£2 / +£39 | −£199 / −£190 | −£221 / −£76 | 43 |
*Ticks the middle price sits against our fill price (−0.5 = it has not moved since the fill, as we fill half a tick inside the middle).

What the steer changes, same version for every steer (quote from 10 min, out 30 s, stop 3, close held at one tick of profit), 10–19 Nov, queue / through:
| | Fills | Round trips | After 30 s* | After 2 min* | £/£100 10–19 | 20–21 |
|---|---|---|---|---|---|---|
| Racing d control | 6,471 / 4,381 | 59% / 42% | +0.30 / +0.59 | +0.43 / +0.73 | −1.25 / −2.62 | −0.91 / −1.77 |
| Racing a1 favoured only | 4,900 / 2,427 | 59% / 37% | +0.21 / +0.44 | +0.75 / +1.50 | −2.03 / −3.80 | −1.74 / −3.69 |
| Racing b2 / c2 | 6,456 / 6,035 (q) | 58% / 58% (q) | +0.31 / +0.33 (q) | +0.55 / +0.63 (q) | −1.09 / −1.16 (q) | −1.10 / −1.14 (q) |
| Racing r2 opposite side | 5,667 / 2,434 | 63% / 46% | +0.22 / +0.49 | +0.21 / +0.84 | −0.68 / −2.00 | −0.68 / −1.61 |
| Football d control | 2,477 / 1,943 | 33% / 26% | −0.20 / −0.23 | −0.05 / +0.04 | −1.54 / −1.71 | −0.22 / −0.13 |
| Football a1 / c2 (queue) | 810 / 2,063 | 30% / 35% | −0.13 / −0.22 | +0.09 / −0.18 | −1.70 / −1.31 | +1.18 / −0.97 |

£ a day on 10–21 Nov at each stake (each version as in the first table), queue / through:
| | £10 | £25 | £50 |
|---|---|---|---|
| Racing d control | −£119 / −£175 | −£289 / −£474 | −£561 / −£930 |
| Racing a1 | −£23 / −£46 | −£78 / −£119 | −£165 / −£242 |
| Racing b2 | −£45 / −£82 | −£116 / −£225 | −£236 / −£452 |
| Racing c2 | −£40 / −£68 | −£109 / −£190 | −£222 / −£383 |
| Football result d control | −£37 / −£35 | −£88 / −£85 | −£155 / −£156 |
| Football result c1 | −£22 / −£17 | −£54 / −£42 | −£94 / −£74 |
| Football result b2 | −£38 / −£30 | −£90 / −£74 | −£157 / −£137 |
| Football result a1 | −£12 / +£10 | −£32 / +£22 | −£63 / +£44 |

## Part 2 — thin football markets priced from match odds + over/under 2.5 (`s14/goals.py`, independent Poisson goals each minute)
**Fit, 10–15 Nov (589 matches, 19,880 match-minutes):** the model reproduces the deep markets' own prices within 0.84 (home), 1.72 (draw), 0.94 (away), 0.63 (over 2.5) points of probability (RMSE); it prices the draw 1.3 points short (the plain Poisson model's known draw gap). 17–21 Nov: 0.85 / 1.61 / 0.90 / 0.84. First half's share of goals fitted once on 10–15 Nov: 45% (median error 0.5 points on half-time and first-half-goals prices).
| Thin market (stream, 10–15 / 17–21 Nov) | Gap back–lay | Mid against our fair | Fair inside the gap | Trades an hour per market (money) | Picked on 10–15 Nov | £/£100 10–15 (q / t) | 17–21 (q / t) | £ a day 17–21 at £25 (q / t) | Worst day | Without best day |
|---|---|---|---|---|---|---|---|---|---|---|
| Correct score | 20% / 13% | 5.8% / 5.7% | 67% / 53% | 80 over 19 runners (£543) | held 1% (BET) | −8.0 / −7.3 | −5.5 / +9.0 | −£352 / +£378 | −£572 / −£295 | −£1,762 / +£551 |
| Correct score | | | | | closed by offer 2% | −8.6 / −10.5 | −3.1 / −1.7 | −£185 / −£65 | −£1,218 / −£951 | −£2,030 / −£2,045 |
| Both teams to score | 4.4% / 3.4% | 3.5% / 3.5% | 36% / 27% | 10 (£179) | closed 3% | −1.9 / −4.3 | −5.2 / −4.2 | −£86 / −£60 | −£279 / −£209 | −£558 / −£401 |
| First-half goals 0.5 | 3.3% / 3.1% | 1.0% / 1.0% | 76% / 69% | 6 (£98) | closed 1% | −1.3 / −2.7 | +1.8 / +1.7 | +£17 / +£11 | −£146 / −£90 | −£69 / −£77 |
| First-half goals 2.5 | 2.8% / 2.7% | 1.2% / 1.3% | 65% / 60% | 4.5 (£112) | closed 2% | −8.5 / −13.9 | −12.9 / −16.7 | −£66 / −£41 | −£232 / −£127 | −£330 / −£204 |
| Half-time result | 5.5% / 5.0% | 1.0% / 0.9% | 86% / 87% | 5 (£85) | held 1% (BET) | −3.4 / −13.6 | −2.3 / −4.8 | −£28 / −£40 | −£140 / −£199 | −£263 / −£282 |
| Over/under 4.5 | 3.3% / 2.6% | 0.9% / 1.0% | 80% / 70% | 9 (£246) | held 3% (BET) | +3.2 / −1.9 | +1.6 / +7.6 | +£5 / +£20 | −£198 / −£198 | −£89 / −£34 |
| Half-time/full-time | 31% / 25% | 5.4% / 5.8% | 78% / 74% | 7.5 over 9 runners, median market 0 (£43) | held 1% (BET) | −4.9 / −7.1 | −2.7 / +8.0 | −£23 / +£39 | −£705 / −£503 | −£874 / −£685 |
| Double chance | 2.4% / 1.9% | 1.0% / 1.4% | 54% / 36% | 8 (£180), 11 markets on 10–15 Nov | closed 3% | (5 fills) | −2.5 / −5.2 | −£16 / −£17 | −£57 / −£30 | −£92 / −£83 |
| Draw no bet / first-half 1.5 (stream 10–15 Nov only) | 4.1% / 3.5% | 1.1% / 1.1% | 73% / 73% | 4.3 / 5.6 | closed 1% / 3% | −11.7 / −12.5; −0.7 / −1.9 | not on the stream | | | |
| Over/under 0.5, 1.5, 3.5, 5.5–8.5, half-time score (book snapshots only, 17–21 Nov) | 1.9–20% (6.5+: 9–90%) | 0.4–3.7% (6.5+: 6–52%) | 55–92% | **no trade data: fills cannot be modelled** | — | | | | | |
All versions pooled, 10–15 Nov: −7.2 to −9.3 per £100 closed by offer, −4.7 to −12.4 held (BET), both models; 64 slices (market × side × price band × margin × exit) with 100+ fills each half: 13 profit on both halves under one model, 2 under both (above). Picking on 10–15 Nov does not predict 17–21 Nov (+2.5 per £100 for the first-half winners against +1.8 for the first-half losers). The fills come before moves against us of 0.5–3 ticks within 30 s: thin-market money arrives when it knows something our fair price does not yet show.
Fills modelled only where we record trades (Betfair stream). **Racing place against win: not possible: place markets are not recorded before the start** (stream has WIN only; book snapshots are football only). Session 15 started a second recorder tonight that adds them.

## Part 3 — goal-predictor steer in play: not run
The brief's condition is uplift on unseen dates. goal_trade.md reports uplift over the NORMAL goal rate (+2 / +6 / +8 points at 5 / 10 / 15 min); I read the condition as uplift over the PRICE, because a steer can only help if it knows more than the price. The predictor beats the normal goal rate (top tenth 30% against 24% within 10 min, 9–19 Nov) but is **3.5 points below what the over price already expects** (goaltrade/v2_results.md, 9–19 Nov unseen), and the goal monitor "beats the price NO" (books_and_goal_signal.md). A quoter steered by it would be steered by less than the price already knows, so the 5-second order delay was not modelled. Recheck when session 12's rerun on 29 Nov (22–28 Nov added) reports.

## How it was checked
- `s14/test_mm14.py` ALL PASS: session 10's 31 hand cases pass unchanged through the steered quoter with every switch on; on 5 Nov racing all 576 session 10 versions give identical arrays to `s10/mm.py`; 10 new hand cases for the switches (pull before the trade, pull on the same update, closing orders untouched, lay under 3.0).
- `s14/test_goals.py` ALL PASS (14): 0-0 = e^-(λh+λa), both to score, under 2.5, first-half under 0.5, every market's runners sum to 1 (double chance to 2), HT/FT Draw/Draw against brute force, the fit recovers the means it was given.
- `s14/test_p2sim.py` ALL PASS (13): back at fair+2% inside the gap fills on a queue trade but not through-only, never crossing the best price, queue eaten, lay below fair only under 3.0, close by opposite offer +£0.50 either way, the 60-second take-out, no fair price = no order. A gap it found (the closing order went in one update late) was fixed before the runs.
- No look-ahead: features are session 7's own rows (s7_rows; 20–21 Nov rebuilt with s7feat.rowfeat), joined at or before each quote; conditions and jumpy limits from 2–9 Nov; fair prices use deep quotes at or before each minute and apply from that minute. Conditions fired on 39–51% of racing quote moments on every day, live days included.
- Generous to the quoter, as session 10: no reaction delay before the off. Football 6 Nov has no pre-start stream.
- Files: /root/pe-builder/s14 (mm14.py, steer.py, run14.py, summ14.py, pick14.py, goals.py, p2_data.py, p2_fair.py, p2_gaps.py, p2_sim.py, p2_summ.py, p2_report.py, var14*.parquet, pick14*.parquet, p2_*.csv, out/). The paper trader stayed up; no out-of-memory kills during the runs.

What I need from you: nothing.
