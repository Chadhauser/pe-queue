# Finder 2026-11-04 — item 51: cross-market residuals inside a game. PILOT

**Data.** liq_sample 30 Oct–4 Nov x goal_timeline. Job: jobs/489_cross_market_residuals.sh (number shared, as 450-499 is full). 1,221 recorder games, 1,016 mapped, 21 dropped for the mislabelled MO. 15,918 in-play snapshots fitted, one per game per 5 min; 937 candidates in 289 games.

**Method.** Two Poisson rates for remaining goals, from the current score, fitted to overround-removed mids of MO, OU15, OU25, OU35 and BTTS (at least 3 open). Back if model p − 1/back_px >= 3/5/10 points; lay if 1/lay_px − model p >= that, so the edge must clear the actual touch. Spread <= 1.25. One tick adverse, 2% commission, £10 risk. Exits +10 min and settle; a market passed before the exit settles at the result; unknown result = −£10 (106 rows).

**Not tested.** AH and CS are not in the fit. Next goal +8 is not a separate exit, as a goal inside the hold is settled at the result or exited at +10. The traded line is in its own fit, which shrinks its residual.

**The book agrees with itself.** Median fit RMSE 0.0088, p90 0.0165, and only 344 snapshots above 0.06. Most fits are within a point of every line, so a 3-point edge beyond the touch is rare and, as below, not a mispricing.

**Headline lines, per £10. Survivors: none.** tc = per game; Quiet = no feed goal in the last 3 min.

| Side | Edge | Sel | Exit | n | Games | Price | Mean | t | tc | h1 | h2 | ex-top |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Back | .03 | all | +10 | 361 | 201 | 4.32 | −1.320 | −2.98 | −3.12 | −0.195 | −2.922 | −1.664 |
| Back | .03 | all | settle | 361 | 201 | 4.32 | −1.766 | −2.13 | −2.11 | +0.124 | −4.456 | −2.111 |
| Back | .03 | first | +10 | 201 | 201 | 3.82 | −1.252 | −3.36 | −3.36 | −0.292 | −2.799 | −1.379 |
| Back | .03 | quiet | +10 | 330 | 181 | 4.53 | −1.440 | −2.98 | −3.25 | −0.251 | −3.095 | −1.817 |
| Back | .05 | all | +10 | 107 | 78 | 4.11 | −1.174 | −1.72 | −1.63 | −0.288 | −2.394 | −1.462 |
| Back | .05 | all | settle | 107 | 78 | 4.11 | −2.515 | −1.89 | −1.02 | −0.524 | −5.258 | −3.186 |
| Lay | .03 | all | +10 | 377 | 223 | 2.51 | −1.326 | −3.47 | −4.82 | −0.515 | −2.427 | −1.619 |
| Lay | .03 | all | settle | 377 | 223 | 2.51 | −0.941 | −1.08 | −1.40 | −0.387 | −1.693 | −1.316 |
| Lay | .03 | first | +10 | 223 | 223 | 2.79 | −1.351 | −5.01 | −5.01 | −1.104 | −1.767 | −1.436 |
| Lay | .03 | quiet | +10 | 356 | 210 | 2.43 | −1.315 | −3.27 | −4.61 | −0.420 | −2.489 | −1.625 |
| Lay | .05 | all | +10 | 110 | 78 | 2.40 | −1.189 | −1.91 | −0.32 | +0.018 | −2.440 | −1.472 |
| Lay | .05 | first | settle | 78 | 78 | 2.61 | +0.401 | 0.16 | 0.16 | +1.017 | −0.439 | −1.412 |

**Top lines by t, n >= 100:** lay .03 quiet price <=1.5 settle n 147 +£0.002 t 0.00; back .03 quiet price 3+ settle n 159 −£1.234 t −0.72; back .03 quiet 0-30' +10 n 115 −£0.912 t −0.79. Every other line at n >= 100 has a lower t. By market and minute at edge .05, n is 20–49 per cell: for reading only (best back 45-60' +10 n 22 +£3.21 t 1.31).

**Verdict: nothing passes, pilot.** 0 of 138 lines, none positive at n >= 100 beyond £0.002. Both the back and the lay lose, so these residuals are a stale or wide price, not value: when one line sits away from the consensus, trading towards it pays the spread and gets nothing back. Item 0e's exact-arbitrage finding extends to relative value on these five markets.

**Re-run.** Not queued: liq_sample rolls at about 5–6 days, and with this result a larger n would only sharpen a loss. Log read from the task output, not /root/pe-queue-logs.
