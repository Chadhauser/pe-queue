# Why paper trade exits do not fill (21 Nov 2026, Builder session 8)

**Mostly our own set-up, not the market: 76% of the 4,902 missed or part-filled exits.** The biggest single cause (1,442, 29%) is our recorder. The market was open and trading, but it was not on our live price stream (that takes at most 200 markets), so the only quote was a once-a-minute snapshot, and the test refused it as too old. Only 24% are the market itself (too little money, no price, suspended).
**Most of the money is our rules (−£7,845 of −£10,181).** The £50 cap the test puts on the *closing* bet causes 1,006 (−£4,477): mostly racing outsiders backed at 10+ and laid back 30 s before the off. Exits timed after the market has already closed cause 603 (−£3,254): races exited 2 minutes after the off, first-half markets at 90 minutes.
**The one change: let a closing bet ignore the £50 cap and take the first fresh price up to 60 s after the exit moment.** 1,615 of these trades would then get fully out instead of 0, and 1,879 partly. Warning: getting out does not stop the loss. It costs −12.5 per £100, against −6.4 on paper. The loss is in the entries (racing outsiders at 10+: −£8,841), not the exits.

Covers settled paper TRADES 19–21 Nov to 11:20 UTC, each bet once, voids left out: 6,776 trades, 3,354 missed and 1,548 part-filled. The paper record has grown since Peter's figure (6,218 trades). Missed exits alone (rest-both-sides trades left out): −£7,854 on 3,296 trades, close to the −£7,621 quoted.
**Checks.** Each trade was replayed from the recorded prices. On the 1,662 trades whose exit takes the price on offer and that the paper record shows as filled, the replay finds a fill on 1,655 (rested and rest-both-sides exits were not re-run). The paper profit rebuilt from the stored bets matches to the penny on all 6,776. Of the 860 "no quote" moments, the recorder logged the market as suspended within 60 s in only 38. In the rest the market was open.

| Cause (missed / part) | Trades | Share | Paper £ | Per £100 | Fully out with the change |
|---|---|---|---|---|---|
| Recorder: market open but not on our live stream; quote too old | 1,442 / 0 | 29% | −£1,042 | −2.1 | 874 |
| Market: less money on offer than the position needed, or under £2 | 392 / 658 | 21% | +£330 | +0.9 | 19 |
| Rules: our £50 cap on the closing bet | 132 / 874 | 21% | −£4,477 | −14.4 | 662 |
| Rules: exit timed after the market closed (race over, half ended, market settled) | 603 / 0 | 12% | −£3,254 | −21.6 | 0 |
| Rules: exit moment never came (no in-play event after entry, mostly "30 s after the next goal") | 271 / 0 | 6% | +£3 | 0.0 | 0 |
| Rules: price moved so far the closing bet was under the £1 minimum | 192 / 0 | 4% | +£281 | +5.1 | 0 |
| Market: no price at all on the exit side | 84 / 0 | 2% | −£1,213 | −91.4 | 3 |
| Recorder: quote stale or delayed over 2 s | 82 / 0 | 2% | −£369 | −15.5 | 44 |
| Market: suspended at the exit moment | 62 / 0 | 1% | −£43 | −2.3 | 10 |
| Rules: rested closing order never traded through, or rest-both-sides clearing order | 94 / 16 | 2% | −£398 | — | 3 |

| Split | Market | Our recorder | Our rules | Missed or part | Paper £ |
|---|---|---|---|---|---|
| Football | 522 | 1,444 | 1,062 | 3,028 | +£251 |
| Racing | 650 | 31 | 1,105 | 1,786 | −£10,098 |
| Tennis / cricket | 24 / 0 | 27 / 22 | 15 / 0 | 66 / 22 | −£265 / −£69 |
| Exit before the start / in-play | 125 / 1,071 | 239 / 1,285 | 737 / 1,445 | 1,101 / 3,801 | −£2,669 / −£7,512 |
| Entry price under 2 / 2-5 | 131 / 347 | 171 / 416 | 354 / 583 | 656 / 1,346 | −£807 / −£438 |
| Entry price 5-10 / 10+ | 353 / 365 | 402 / 535 | 393 / 852 | 1,148 / 1,752 | −£95 / −£8,841 |

| Other exits on the same 4,902 trades | Fully out | Part | Still held | £ | Per £100 |
|---|---|---|---|---|---|
| Paper (as the test did it) | 0 | 1,548 | 3,354 | −£10,181 | −6.4 |
| (i) take what is on offer at the moment, or the first fresh quote within 60 s; no £50 cap | 1,615 | 1,879 | 1,408 | −£19,897 | −12.5 |
| (ii) stop at −10%, target at +10% of stake, checked every tick from entry; else (i) | 2,145 | 2,526 | 231 | −£23,241 | −14.6 |

(ii) hit the stop 2,881 times and the target 703 times. The back-lay gap at entry is only 2.5% (median), so the stops fired on real moves that held positions recovered from. By sport, per £100: racing −19.6 paper → −13.8 (i) / −10.0 (ii); football +0.2 → −12.1 / −17.0; tennis −9.4 → −9.1 / −16.7.
**Money on the way out, at entry.** Median £20 waiting on the exit side (filled £42, missed £12); median stake £11. "Only enter with at least twice the closing stake on offer" does separate them, but not cleanly. With twice or more (3,404 trades): 36% filled, 43% missed, +2.0 per £100. With less (3,160): 15% filled, 58% missed, −12.0 per £100. Racing 42% against 14% filled; football 33% against 15%.
**Fill rate, all trades (full / part).** Football 25% / 16% of 3,972 · racing 27% / 36% of 2,455 · tennis 43% / 30% of 115 · cricket 0% of 22.
**Too strict.** The £50 cap stops a closing bet that lowers our risk, and Betfair would take it (1,006 trades). The recorder keeps only the best price, so a real order that would also take the next price levels is counted short (part of the 658 short fills). A 15-second freshness limit on a market polled once a minute refuses markets that were open.
**Too generous.** Betfair holds in-play bets for a few seconds before matching them, and the test fills at the quote of the exact moment. It also gives us all the money shown at the best price, as if no one else wanted it.
**Next, on the server.** Exits must be due while their market is still open: racing in-play exits within about 1 minute of the off (the median race market here stays open 3.8 minutes), and no first-half market exited after half time. The markets we hold trades in go on the live stream first. Re-test after both, with the cap off for closing bets only. Files: /root/pe-builder/s8 (exits_why.py, gaps.py, report.py, missed_rows.csv). Read-only work: no table or trading file touched.
