# Finder 2026-11-04 — items 36 and 39: La Liga 0-0, Over 1.5 cheap? Audit

**Data.** bf_hist_price OU15 x af_fixtures x af_events, 12,255 games, 739 La Liga, seasons 2024 and 2025. Own code, not 474's: jobs/489_laliga_00_audit.sh, jobs/489_laliga_checks.sh, jobs/489_laliga_forward.sh. One entry per game per T, no goal by T, first print at T+1..T+3, worse of it and the next print within 2 min, one tick adverse, 2% commission, £10 risk. No goal, a second goal by the exit, or no later print: settled at the result. About half of OU15 rows repeat (873,720 repeated keys, 5,027 with different prices); earliest kept.

**Verdict: NUMERIC PASS, NOT CLEARED TO STAKE. It is one bet, not six lines, and by item 39's own rule ("if only La Liga shows it, call it selection") treat it as selection until a forward sample agrees.**

| PASS line | n | Per £10 | t | 2024 | 2025 | 3 ticks |
|---|---|---|---|---|---|---|
| T35 back Over, goal +5 | 336 | +1.390 | 4.08 | +0.727 | +1.986 | +1.215 |
| T30 back Over, goal +5 | 373 | +1.187 | 3.98 | +0.469 | +1.850 | +1.028 |
| T35 lay Under, goal +5 | 335 | +1.346 | 3.90 | +0.753 | +1.889 | +1.182 |
| T30 lay Under, goal +5 | 370 | +1.167 | 3.88 | +0.521 | +1.767 | +1.016 |
| T35 back Over, goal +10 | 336 | +1.330 | 3.52 | +0.826 | +1.783 | +1.155 |
| T35 back Over, goal +8 | 336 | +1.276 | 3.51 | +0.721 | +1.775 | +1.102 |

**Next nine by t, none passes:** T35 lay Under g+10 n 335 +1.336 t 3.49; T30 back Over g+8 n 373 +1.104 t 3.49; T30 back Over g+10 +1.131 t 3.46; T30 lay Under g+10 n 370 +1.144 t 3.46; T35 lay Under g+8 +1.267 t 3.45; T30 lay Under g+8 +1.098 t 3.44; T46 back Over g+5 n 220 +2.048 t 3.35; T25 lay Under g+5 n 424 +0.819 t 3.28; T46 lay Under g+5 n 221 +1.900 t 3.15.

Item 36's original line reproduces: T30 lay Under g+8 n 370 +£1.10 v 474's n 361 +£1.16. At the house exit of g+8, only T35 back Over clears t 3.5. Goal +5 may carry some of the clock problem found at g+2.

**For it**

| Check | Result |
|---|---|
| Mapping | Last print agrees with the af total 97.6% (other leagues 93.4–97.9%); first-print lag 2.5 min. Not a data fault |
| Calibration | T30 implied 54.4% v won 62.5%, edge +8.1 points, z 3.23; T35 +9.3, z 3.46 |
| Placebo | La Liga first of 12–17 leagues at every T, side and exit (T 15–60); all leagues together are negative: T30 g+8 −£0.24 n 5,593 |
| Spell | All four date quarters positive at T30 back g+8: +0.89, +0.50, +1.27, +1.75 |
| Clubs | 18 of 23 clubs positive. Removing the top five leaves +£0.30 t 0.72, but removing winners always does that |
| Fills | Without a goal landing by the fill: +£1.16 t 3.46, so not fills at stale prices |
| Chosen on 2024 | La Liga first or second in 2024 in most lines; where first, 2025 made +£0.63 to +£5.19, t 1.7–3.6 |
| Real touch | La Liga gap 1–2 ticks v 3–4 for all games, sizes £35–275, but only 5 games |

**Against it**

| Check | Result |
|---|---|
| Selection | La Liga came from these two seasons (476, 480, 474). 1,048 league lines tested here, sharing games; best t 4.08 is about at Bonferroni for that many |
| Untouched season | 2026-27, goals only: from 0-0 at 30' Over 1.5 won 24 of 48 = 50.0% (implied was 54.4%, in-sample 62.5%), z −1.79 v in-sample. At 35' 20 of 43 = 46.5%. Serie A went the other way, 75.7% v 53.8%, so ±7 points is noise at this n: it does not disprove the line, but it does not support it |
| Chosen on 2024, as a method | When another league topped 2024, its 2025 was −£2.09 to +£0.45, none significant on the upside; top-three lines t at most 1.97 |
| Cost | At k = 2 ticks T30 back g+8 +£1.02 t 3.26, k = 3 +£0.95 t 3.04, k = 5 +£0.80 t 2.59, k = 8 2024 goes −0.03 |
| Forward touch | liq_sample since 30 Oct, 8 entries at all T: 5 at T30 back −£0.41, lay −£0.47; the rest lost. No verdict at this n |
| No reason | No structural reason found why this one top league should be mispriced for two seasons |

**Controls at T30 g+8, back Over:** Premier League −0.12, Serie A −0.07, Segunda −0.19, Bundesliga −0.29, Ligue 1 −0.43, all n 240–452. Item 39's other windows: T15 g+8 +0.40 t 1.95; T25 +0.71 t 2.68; T46 +1.90 t 2.86; T60 +3.54 t 2.56 n 141; T70 +4.81 t 1.68 n 96.

**Next.** No stake. liq_sample rolls at about 5–6 days, so "restate weekly" cannot accumulate: item 59 asks the strategy chat to save the touch forward. New item 60 is the mirror: League One and Ligue 2 are as far the other way (T30 −6.6 and −8.7 points, z −2.9).

**Caveats.** Entry is LTP, so all P&L above is an upper bound until real touches exist. The 2026-27 test is goals only. The Betfair historical tables were not searched for 2026-27 La Liga OU15 prints. Logs read from task output, not /root/pe-queue-logs.
