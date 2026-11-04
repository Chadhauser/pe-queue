# Finder 2026-11-04 — item 33b: racing in-play shortened 15% / 25%, fair fills

**Verdict: nothing passes.** 0 of 256 lines. Every line has a negative mean, including TRIG, the fill at the trigger print itself, which cannot be had in practice. This replaces item 33's "no valid verdict".

**Job:** jobs/487_racing_inplay_hist.sh, unchanged, exit 0. It stopped at its 2,400 s budget, so the output covers 20,400 of 27,446 market ids (74%), shuffled, spread over all 25 months. The pull slowed sharply after about 870 s (12–13 s per chunk, then up to about 430 s), probably other lanes' load, but that is not confirmed.

**Data:** bf_hist_other GB/IE WIN, 1 Sep 2024 – 30 Sep 2026, 19,984 races with a trigger. Halves split at 13 Sep 2025. Median 3 in-play prints per runner, 60 s apart, no book.

**Results:** racing_bsp on 38,774 runners, the tape's final print on 142,402, unknown on 1,999 (counted as -£10). Where both exist, 38,212 agree and 3 differ.

## First runner per race, per £10
| X | Side | Fill | n | Races | Per £10 | t | h1 | h2 | Pass |
|---|---|---|---|---|---|---|---|---|---|
| 15% | back | NEXT | 17,391 | 17,391 | -3.367 | -5.67 | -3.881 | -2.858 | no |
| 15% | lay | NEXT | 19,139 | 19,139 | -1.061 | -17.97 | -0.970 | -1.151 | no |
| 25% | back | NEXT | 15,850 | 15,850 | -4.099 | -6.29 | -4.933 | -3.283 | no |
| 25% | lay | NEXT | 18,024 | 18,024 | -1.368 | -24.62 | -1.349 | -1.386 | no |
| 15% | back | TRIG, upper bound | 19,123 | 19,123 | -1.078 | -5.66 | -1.119 | -1.036 | not eligible |
| 15% | lay | TRIG, upper bound | 19,984 | 19,984 | -0.632 | -11.54 | -0.570 | -0.693 | not eligible |
| 25% | back | TRIG, upper bound | 18,002 | 18,002 | -1.439 | -7.91 | -1.621 | -1.258 | not eligible |
| 25% | lay | TRIG, upper bound | 19,872 | 19,872 | -1.159 | -18.51 | -1.148 | -1.171 | not eligible |

## Top lines by t, all fills
Only NEXT with FIRST could pass. All are negative.

| X | Set | Side | Fill | Cut | n | Per £10 | t | h1 | h2 |
|---|---|---|---|---|---|---|---|---|---|
| 25% | FIRST | lay | TRIG | entry >= 1.2 | 17,524 | -0.008 | -0.13 | +0.068 | -0.083 |
| 25% | FIRST | back | TRIG | off 3-6 | 3,198 | -0.043 | -0.19 | +0.125 | -0.211 |
| 15% | FIRST | back | TRIG | off <3 | 1,223 | -0.150 | -0.61 | -0.283 | -0.012 |
| 15% | FIRST | back | TRIG | off 3-6 | 3,880 | -0.187 | -0.81 | -0.385 | +0.010 |
| 25% | ALL | lay | TRIG | entry >= 1.2 | 46,450 | -0.033 | -0.83 | +0.013 | -0.080 |
| 15% | FIRST | back | NEXT | off 12-25 | 4,893 | -2.311 | -1.15 | -4.190 | -0.489 |
| 25% | FIRST | back | NEXT | off 12-25 | 4,808 | -2.715 | -1.34 | -4.988 | -0.560 |
| 25% | FIRST | back | TRIG | off <3 | 870 | -0.363 | -1.47 | -0.284 | -0.447 |
| 15% | FIRST | lay | TRIG | off 25+ | 3,558 | -0.063 | -1.51 | -0.120 | -0.008 |
| 25% | ALL | back | NEXT | off 3-6 | 6,459 | -2.939 | -1.95 | -4.548 | -1.336 |
| 15% | FIRST | lay | TRIG | entry >= 1.2 | 18,843 | -0.099 | -2.04 | +0.003 | -0.201 |
| 25% | FIRST | back | NEXT | field 9-12 | 6,031 | -3.595 | -2.17 | -5.528 | -1.673 |
| 25% | FIRST | lay | TRIG | off 25+ | 3,759 | -0.109 | -2.22 | -0.138 | -0.080 |
| 15% | FIRST | back | TRIG | off 6-12 | 5,356 | -0.647 | -2.26 | -0.904 | -0.389 |
| 15% | FIRST | back | NEXT | field 9-12 | 6,470 | -3.453 | -2.28 | -4.961 | -1.932 |

## Reading it
- **The tape can reject this idea but could not have cleared it.** The fill is a one-minute proxy, so a pass would only have been an upper bound. A loss at the trigger print is stronger evidence, but only at one-minute resolution: a tick feed could see the same move earlier and at a better price, so this does not rule out a faster version, which needs a tick source for races.
- **Why fills differ so much:** the market moves a long way in a minute. Backing goes from about -£1.08 at the trigger print to -£3.37 at the next one (15%).
- **Fat tails:** NEXT back lines have very large spread (t -1.15 at -£2.31), so their t values are weak and a few long-priced winners may drive them. Not examined further, as no NEXT line is positive.
- **Trades with no next print:** 12.1% of triggers have no next print and no NEXT trade, because there is no later price to fill at. They remain in TRIG.

**Log:** harness output only; this session cannot write to /root/pe-queue-logs.
