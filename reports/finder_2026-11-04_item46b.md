# Finder 2026-11-04: item 46b, calibration atlas on all cached games

**Verdict: PARTIAL, nothing passes on 8,771 of 12,255 games.** 0 of 88 lines, 64 at n >= 300. On this evidence the market's error map is not tradable.

Job: `jobs/488_calibration_atlas.sh`, unchanged, at default FETCH_SECS=0, so cache only (178 of 246 chunks). Raising FETCH_SECS needed an approval this unattended run does not have, so the other 68 chunks, about 3,350 games, stay unscored. Used 4,180 games of 2024 and 4,591 of 2025, 1.43M rows; dropped 100 on kick-off lag, 29 on goals not matching FT. Fit on 2024, scored on 2025, one entry per game, one tick adverse, 2% commission, £10. Halves at the 2025 median date, 15 Dec 2025.

## Top 15 hold-out lines by t (survivors: none)

| Rule | Side, exit | n | price | per £10 | t | h1 | h2 | x3 | 2024 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| #15 OU15 Over G27 | lay, settle | 383 | 1.46 | +1.204 | 1.42 | +1.154 | +1.267 | +0.807 | +2.366 |
| #29 MO Away G22 | back, settle | 448 | 2.70 | +0.780 | 1.28 | +1.084 | +0.206 | +0.578 | +3.119 |
| #37 MO Draw R39 | lay, settle | 213 | 3.60 | +0.432 | 1.08 | +0.999 | −0.162 | +0.321 | +0.771 |
| #11 MO Away R26 | back, goal +8 | 232 | 2.44 | +0.494 | 1.02 | +0.272 | +0.721 | n/a | +1.133 |
| #37 MO Draw R39 | lay, goal +8 | 213 | 3.60 | +0.206 | 0.99 | +0.332 | +0.074 | n/a | −0.037 |
| #10 MO Away R17 | lay, goal +8 | 310 | 3.00 | +0.236 | 0.95 | −0.172 | +0.724 | n/a | +0.447 |
| #32 OU15 Under R20 | back, settle | 229 | 2.96 | +0.915 | 0.95 | +2.448 | −0.959 | +0.693 | +3.231 |
| #31 OU15 Under G12 | back, settle | 229 | 2.96 | +0.915 | 0.95 | +2.448 | −0.959 | +0.693 | +3.231 |
| #15 OU15 Over G27 | lay, goal +8 | 383 | 1.46 | +0.608 | 0.93 | +0.320 | +0.970 | n/a | +0.619 |
| #30 OU35 Over G34 | lay, settle | 1,173 | 3.55 | +0.154 | 0.80 | +0.230 | +0.093 | +0.043 | +0.210 |
| GBM bottom 5% | lay, settle | 1,692 | 1.72 | +0.239 | 0.74 | +0.135 | +0.377 | −0.027 | +10.366 |
| #6 OU15 Over R18 | lay, settle | 691 | 1.35 | +0.411 | 0.60 | +0.098 | +0.937 | −0.059 | +2.892 |
| #11 MO Away R26 | back, settle | 232 | 2.44 | +0.439 | 0.56 | +0.400 | +0.478 | +0.268 | +3.756 |
| #3 MO Home G30 | lay, settle | 1,268 | 2.32 | +0.149 | 0.55 | −0.044 | +0.507 | −0.004 | +1.292 |
| #35 OU25 Over G41 | lay, settle | 179 | 1.95 | +0.368 | 0.44 | −1.018 | +1.622 | +0.182 | +2.047 |

All lines: hold-out mean −£0.134, median −£0.165, 28.4% positive, against +£1.522 in sample. Tree rules are re-drawn on this larger set, so rule numbers do not match the first run's.

## Reading
**Model.** Correlation of prediction and residual: 0.327 in sample, 0.014 on 2025 (first run on 2,953 games: −0.013). It has a little real signal, too little to pay: the top decile realises +0.0055 against +0.0719 predicted, and costs swamp it.

**Persistence.** Leaves with n >= 200 in 2025: Spearman 0.258, same sign 60.8%, mean size 0.0557 falling to 0.0216. So the map partly persists, at about a third of its fitted size. This is the same picture as item 52: a little true structure, smaller than the cost.

**By selection.** Under lines have run slightly high and Over lines slightly low in both seasons: OU15 Over −0.0161 then −0.0112, OU15 Under +0.0158 then +0.0109, OU35 +0.0148 then +0.0083. Laying Over 3.5 is the only base line above zero at settle, +£0.026 per row, on rows that share games, so this is not a clean trade.

Note: by 5-minute band, band 90 shows back −£4.85 and lay −£3.58 at settle, far from every other band; I did not establish why, and it does not touch the lines above unless their rules reach that band.

Limits: rows share games in the atlas tables; lines are one per game, but rules overlap (#31 and #32 are the same bet). LTP only, so anything positive is an upper bound. Seasons overlap in calendar time.
