# Finder 2026-11-02 — queue item 0: AUDIT of job 321 "MOMO" (pressure scalp)

**Job:** jobs/454_momo_audit.sh (independent code: own fixture matcher, own fills; 321 read only to know what it claimed).
**Data:** goal_live_predictions 174,164 rows / 3,145 fixtures (27 Oct – 2 Nov); liq_sample MO+OU25 548k rows, 1,237 events (28 Oct 03:38 – 2 Nov 08:27 UTC).
Matched 1,046 fixtures to the recorder; 935 games had at least one trigger. Halves split at 2026-10-30 23:31 UTC.

## Three defects in 321 (each alone kills the claim)
1. **The side rule never existed.** goal_live_predictions has NO dangerous attacks / SOT / stats_json since 27 Oct (0 of 174,164 rows non-null).
   321 coded `(home_da or 0)`, so every DA delta was 0 → tie → HOME. "Back the pressing side" was really "back HOME".
2. **Fills on the wrong side of the spread.** liq_recorder.py stores back_px = availableToBack[0], lay_px = availableToLay[0].
   321 backed at lay_px and laid out at back_px — it *collected* the spread on both legs. Honest: back at back_px −1 tick, lay at lay_px +1 tick.
3. **"No exit print → skip"** (180 s tolerance) — same bias as 315. 454 holds to the next real print at any time, else settles at the result.

## Reconciliation (same rows, 321-style vs honest fills)
| leg | exit | n | 321-style per £10 | honest per £10 |
|---|---|---|---|---|
| MO HOME ("press") | +5m | 3,055 | +18.0 | −1.26 |
| MO AWAY ("other") | +5m | 2,943 | +29.7 | −1.60 |
| OU25 Over | +5m | 2,819 | +7.2 | −1.00 |
My replica is far above 321's +£0.68 because 321 also filtered lay_px<100 (I did not): the sign of the result is the point, not the size.
Spread alone (back and lay out at the same print, 1 tick adverse each leg): MO −£0.74 (1–2), −£0.94 (2–3), −£1.10 (3–5), −£1.72 (5–10), −£2.86 (10–20) per £10.

## Honest results (back at touch, lay out at touch, never skipped) — top 10 of 24 cells by t (all 24 are in the job log), none survives
| cell | n | games | per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|
| MO AWAY +10m tgt5% 1/game/10min | 1,399 | 844 | −1.28 | −6.7 | −1.24 | −1.33 |
| MO AWAY +5m tgt5% 1/game/10min | 1,399 | 844 | −1.38 | −7.9 | −1.47 | −1.30 |
| MO AWAY +10m tgt5% all | 2,996 | 844 | −1.14 | −8.0 | −1.23 | −1.05 |
| MO AWAY +10m fixed 1/game/10min | 1,399 | 844 | −1.60 | −9.8 | −1.62 | −1.58 |
| OU25 Over +10m fixed 1/game/10min | 1,587 | 926 | −1.24 | −12.2 | −1.32 | −1.18 |
| MO HOME +10m fixed 1/game/10min | 1,448 | 879 | −1.47 | −12.5 | −1.71 | −1.27 |
| MO HOME +5m fixed 1/game/10min | 1,448 | 879 | −1.45 | −15.3 | −1.61 | −1.31 |
| MO HOME +5m fixed all (the claimed line) | 3,110 | 879 | −1.29 | −17.3 | −1.53 | −1.05 |
| MO HOME +5m tgt5% all | 3,110 | 879 | −1.32 | −18.8 | −1.53 | −1.11 |
| OU25 Over +5m fixed all | 3,438 | 926 | −1.18 | −20.5 | −1.36 | −1.00 |
All 24 cells (3 legs × 2 exits × fixed/target × all/one-per-game-per-10-min) are negative in both halves. "All" rows are correlated (≈3.5 entries/game); t is inflated, but the sign is negative anyway.

## Checks asked for (MO HOME +5m)
- (1) Look-ahead: trigger prices strictly before t, stats rows ≤ t, entry = first print strictly after t. No look-ahead found in the trigger.
- (2) Goal in the previous 3 min: **yes** n 2,104, −£0.87 (t −9.1); **no** n 1,006, −£2.17 (t −19.5). 68% of triggers fire right after a goal — MOMO is mostly a goal detector. OU25 Over: yes −£0.70, no −£2.22.
- (3) Exits: 3,083 at a print, 23 settled at result, 4 with no result (ET / feed stops before 88') counted as −£10. Goal inside the window 15.5%; 5% target hit 7%.
- (6) Minute band: 1–30 −£1.10, 31–60 −£1.37, 61–80 −£1.61. Price band: 1–2 −£0.94, 2–3 −£1.30, 3–5 −£1.25, 5–10 −£1.60, 10–20 −£3.25.
- (7) Other side (AWAY) and OU25 Over: both negative, see table.

## Verdict
**Nothing passes.** The +£0.68 was an artefact: a stats column that is empty (so "pressing side" = HOME), fills that took the spread twice in 321's favour, and skipped exits.
At the real touch, a 5–10-minute in-play scalp on MO/OU25 has to beat a round-trip cost of about £0.7–2.9 per £10. This trigger moves nowhere near that much.
Item 0b (momo_paper bot) is NOT built. **Action for Peter:** treat the pressure_scalp table (321) as void. Any job that trades liq_sample should enter a back at back_px and exit at lay_px.
Also: goal_live_predictions stopped storing SOT/DA (all NULL since at least 27 Oct). PRESS/PJUMP-type ideas cannot be tested until the goal engine writes them again.
