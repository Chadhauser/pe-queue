# Finder 2026-11-03 — item 8: Asian handicap, DNB, correct score (liq_sample)

**Job:** jobs/457_ah_dnb_cs_liq.sh. Ran 3 times, no crash. Run 2 added the drop-bias test and the "tlfill" variant, and made "known"-only cells ineligible to pass. Run 3 fixed my own bug: the favourite-band dimension had always been "-" (wrong dict key). Figures below are from run 3.

## Data
- **bf_hist_price has NO AH or DNB rows** (census: 0). So everything here is liq_sample (real touch, about 1 sample per selection per minute): 2,656,361 rows, 1,374 games, **28 Oct → 3 Nov (6 days)**. 1,181 games traded after the goal_timeline name match (126 unmatched, 62 with no pre-KO MO). Halves: before/after 2026-10-31.
- AH: lines −1/−0.5/0/+0.5/+1 for each team (quarter lines not tested). Settled on the full-match score; check: AH home −0.5 / MO HOME back at 1-0 in the 2nd half, median ratio 0.994 over 481, which confirms full-match settlement. DNB draw = void.
- FT score = the CS selection at ≤1.05 in the last 10 min of tape: 788 games, 88% agree with the timeline's last score. **460 games have no inferable FT.** Each settle line is shown three ways. *known* drops unknowns: diagnostic only, not eligible to pass. *worst* counts unknowns as a full loss. *tlfill* fills unknowns from the timeline's last score at 85'+. That timeline stops before FT (job 300), so tlfill is still slightly optimistic.
- Fills: back at back_px −1 tick, lay at lay_px +1 tick, exits the other way round. NEXTGOAL = first real print at or after goal+2 at any later minute, otherwise settle (24,080 AH / 3,968 DNB exits went to settle). Nothing is skipped. Entries at 0/15/30/46/60/75 for every selection, so AH/DNB have up to 6 correlated entries per game: t is inflated, the "games" column is the honest count.

## Base results (per £10; h1/h2 = before/after 31 Oct)
| line | n | games | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| DNB back settle (tlfill) | 10,824 | 1,159 | −0.76 | −5.5 | −0.40 | −0.99 |
| DNB lay settle (tlfill) | 11,390 | 1,168 | −0.89 | −8.0 | −0.65 | −1.05 |
| AH 0 / ±0.5 / ±1, back or lay, settle or next goal (tlfill) | 8.5–11k each | ~1,110 | −0.44 … −2.21 | ≤ −2.7 | all < 0 | all < 0 |
| CS current score @60 back / lay (tlfill) | 1,006 / 1,024 | | −0.64 / −0.36 | −1.3 / −1.9 | | |
| CS @70 back / lay (tlfill) | 953 / 972 | | −0.13 / −0.80 | −0.3 / −3.3 | | |
| **CS @80 back (tlfill)** | 925 | 925 | **+0.77** | 1.85 | +0.53 | +0.94 |
| CS @80 back (worst) | 926 | 926 | −1.06 | −2.6 | −1.00 | −1.10 |
| CS @80 back (known — diagnostic) | 701 | 701 | +1.81 | 3.68 | +2.09 | +1.62 |
| CS @80 lay (tlfill) | 938 | | −1.41 | −4.3 | | |

Top cells by t (n≥100). **None passes:**
| cell | n | games | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| CS 80 back / known (dropped unknowns: not eligible) | 701 | 701 | +1.81 | 3.68 | +2.09 | +1.62 |
| AH +0.5 lay / next goal / tlfill / 46-75 / 1 down / fav 3-5 | 343 | 200 | +0.73 | 2.52 | +0.25 | +1.01 |
| AH −0.5 lay / settle / known / 15-30 / level / 5+ | 290 | 178 | +0.47 | 2.41 | +0.64 | +0.32 |
| AH −0.5 lay / next goal / tlfill / 46-75 / level / 3-5 | 544 | 280 | +0.51 | 2.25 | +0.37 | +0.60 |
| AH +0.5 lay / settle / tlfill / 46-75 / 1 down / 3-5 | 343 | 200 | +0.82 | 2.19 | +0.82 | +0.82 |
| AH −0.5 back / settle / tlfill / 15-30 / 1 up / 2-3 | 225 | 164 | +1.23 | 2.14 | +1.44 | +1.10 |
| AH −1 back / settle / tlfill / 15-30 / 1 up | 702 | 514 | +0.94 | 2.09 | +0.58 | +1.19 |
| AH −0.5 lay / settle / tlfill / 46-75 / level / 3-5 | 544 | 280 | +0.55 | 1.95 | +0.75 | +0.43 |
| CS 80 back / tlfill | 925 | 925 | +0.77 | 1.85 | +0.53 | +0.94 |

## Drop-bias finding (important)
Run 1 showed "back the current correct score at 80', settle" as a survivor (+£2.04, t 3.8, both halves positive), but only on games whose final score was inferable from the CS tape. **The timeline shows a goal after 80' in 57% of the FT-unknown games vs 42% of the FT-known games.** A late goal leaves the new scoreline short of ≤1.05 before the tape ends, so the games that kill this bet are the ones that get dropped. With unknowns filled from the timeline it is +£0.77, t 1.85. With unknowns counted as losses it is −£1.06. Any CS or late-goal analysis on liq_sample must not infer the result from the CS price alone.

## Verdict
**Nothing passes.** 5,306 cells tested, 1,713 at n≥300; best honest cell t 2.52. DNB and AH lose at every base line in both halves, by about £0.4–2.2 per £10 (the touch spread plus a tick at each end). Only 6 days of data. Re-run when liq_sample has ≥4 weeks, ideally with a real FT result source (af_fixtures for the current season, if API-Football coverage is added for these leagues).
