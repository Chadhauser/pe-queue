# FIN SCOREBOARD (Verifier-only) — 2026-11-11T16:22 UTC

Money: live £0 | paper £396.7 | live edges 0

## Data health
- alpaca_etf: ok | last 2026-11-10 21:25 | rows24h 269 
- alpaca_stocks: ok | last 2026-11-10 20:59 | rows24h 277 
- yf1m: ok | last 2026-11-10 21:59 | rows24h 337 
- local_pg: ok | last None | rows24h None fin_heartbeat 2026-11-10 23:40:06.640230+01:00 ok

## Verdicts (gates: t>=2.5 single / 3.5 sweep, both halves >0, n>=200, |control t|<=2)

| hypothesis | n | mean bps | t | IS t | OOS t | control t | verdict | next door |
|---|---|---|---|---|---|---|---|---|
| ORB-QQQ (Zarattini-Aziz, 501) | 1397 | +0.166 R/trade | 2.43 | 1.59 | 1.84 | -0.26 | **WORKS AT SMALL SIZE** | prop-firm MC: 52-63% pass at $100 risk (502/504); combine with any new WORKS before evaluation |
| ORB stocks-in-play top-20 (505) | 1558 | +0.037 R/day | 2.16 | 1.08 | 2.11 | 3.42 | **NOT YET** | H6 fade-spike test (control anomaly) in queue |
| Intraday grammar sweep 7,070 cells (503) | 7070 | best t 3.27 GLD gap | 3.27 | None | None | 0 | **NOT YET** | mechanism tests H1-H5 in queue |
| Mallik TQQQ/SQQQ rules (500) | 4206 | sma150 L/C 35.9% CAGR | 2.63 | None | 2.63 | 0 | **WORKS AT SMALL SIZE** | 200-day filter halves TQQQ drawdown; own-capital only, not prop-firm |
| H1 lev-ETF rebalance (|move by 15:30|>=1%, trade with it to close) | 456 | -1.5 | -0.91 | -0.21 | -1.23 | 2.25 | **NOT YET** | per test: widen threshold / other instrument |
| H2 BTC overnight >=1% -> QQQ open->close same sign | 854 | 5.8 | 1.51 | 1.3 | 0.78 | -1.54 | **WORKS AT SMALL SIZE** | per test: widen threshold / other instrument |
| H3 TLT first-hour >=0.3% -> QQQ 10:30-12:30 OPPOSITE sign | 464 | -0.7 | -0.23 | 0.01 | -0.41 | 1.19 | **NOT YET** | per test: widen threshold / other instrument |
| H4 last trading day of month, long 15:00->close | 77 | 0.4 | 0.06 | -0.21 | 0.33 | -0.97 | **NOT YET** | per test: widen threshold / other instrument |
| H5 Friday last hour, trade toward nearest $5 strike (dist>0.1%) | 258 | 0.8 | 0.35 | 0.01 | 0.69 | 1.97 | **NOT YET** | per test: widen threshold / other instrument |
| H6 fade opening spike, tight stop, top-20 relvol stocks | 1562 | +0.051 R/day | 1.95 | 1.48 | 1.26 | 3.38 | **WORKS AT SMALL SIZE** | stop 0.2 ATR / exit at 11:00 |
| H6 fade opening spike, tight stop, top-20 relvol stocks | 1563 | +0.051 R/day | 1.94 | 1.48 | 1.26 | 3.81 | **NOT YET** | stop 0.2 ATR / exit at 11:00 |
| H7 stocks ORB, realistic fills (next-bar open, 2x cost) | 1563 | -0.059 R/day | -3.4 | -2.94 | -1.77 | -4.62 | **NOT YET** | if control ~0 and real >0: stocks ORB stands with these fills; else withdraw both stock verdicts |
| ORB-QQQ v2 (stop-side guard, 6 gap days skipped) | 1396 | +0.165 R/trade | 2.41 | 1.58 | 1.83 | 1.31 | **WORKS AT SMALL SIZE** | if withdrawn: ORB on SPY/IWM with the guard |
| M1 QQQ gap DOWN >=0.7%: FADE (long) open->10:30. Mechanism: overnight gap | 225 | +3.16 bps/trade | 0.58 | 0.01 | 0.88 | 0.59 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M2 QQQ gap UP >=0.7%: FADE (short) open->10:30. | 265 | +0.84 bps/trade | 0.2 | 0.25 | -0.0 | -1.63 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M3 Lev-ETF rebalance, WIDER: |QQQ move 09:30->15:30|>=1.5% -> trade QQQ W | 213 | +0.17 bps/trade | 0.06 | 0.09 | -0.02 | -0.47 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M6 Lunch reversal: QQQ 11:30->13:30 move >=0.5% -> FADE 13:30->15:00. | 325 | -3.68 bps/trade | -1.2 | -1.71 | 0.13 | 0.19 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M7 Last-hour momentum: QQQ 09:30->15:00 move >=1% -> WITH it 15:00->close | 416 | +4.23 bps/trade | 1.64 | 1.56 | 0.71 | -0.67 | **WORKS AT SMALL SIZE** | widen/narrow threshold once, then sibling instrument, then dead |
| M8 TLT first hour >=0.3% -> QQQ 10:30-12:30 SAME sign (H3 tested opposite | 363 | +0.54 bps/trade | 0.15 | 0.08 | 0.15 | 1.1 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M9 IWM vs QQQ first-hour divergence >=0.5% -> long the LAGGARD, short the | 591 | -1.84 bps/trade | -1.5 | -0.25 | -1.97 | 0.01 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M10 SPY vs QQQ first-hour divergence >=0.4% -> convergence pair 10:30->clo | 310 | -0.92 bps/trade | -0.8 | -0.6 | -0.52 | -0.34 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M11 Turnaround Tuesday: Monday QQQ close-to-close <=-1% -> LONG Tuesday op | 41 | +12.73 bps/trade | 0.76 | 0.7 | 0.37 | 0.26 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M12 Open drive: QQQ first 15-min range >=0.6% and close in top/bottom 20%  | 257 | +4.69 bps/trade | 0.79 | 1.13 | -0.07 | -0.4 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M13 Gap-and-go: QQQ opens OUTSIDE yesterday's high-low range -> continuati | 648 | -2.11 bps/trade | -0.47 | -0.75 | 0.21 | 0.05 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M14 Gap INSIDE range: QQQ gaps >=0.3% but opens inside yesterday's range - | 423 | -4.65 bps/trade | -1.29 | -1.09 | -0.7 | 0.05 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M15 VWAP reversion: QQQ at 10:00 >=0.4% from session VWAP -> FADE 10:00->1 | 169 | +0.09 bps/trade | 0.02 | 0.26 | -0.27 | 1.82 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M20 60-min ORB on QQQ: break of 09:30-10:30 range by 10:35 close -> contin | 270 | -1.26 bps/trade | -0.23 | 0.48 | -1.07 | 0.6 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M21 30-min ORB on QQQ: break of 09:30-10:00 range by 10:05 -> continuation | 440 | -1.28 bps/trade | -0.27 | -0.08 | -0.38 | 0.04 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| M23 5-min ORB on SPY (ORB-QQQ next door), R-multiples. | 1478 | +0.13 R/trade | 1.76 | 2.12 | 0.27 | -0.89 | **WORKS AT SMALL SIZE** | widen/narrow threshold once, then sibling instrument, then dead |
| M24 5-min ORB on IWM, R-multiples. | 1336 | +0.16 R/trade | 2.29 | 2.96 | 0.04 | -0.84 | **WORKS AT SMALL SIZE** | widen/narrow threshold once, then sibling instrument, then dead |
| M25 5-min ORB on TQQQ (3x: same signal, levered instrument; checks the edg | 933 | -0.06 R/trade | -0.77 | -1.02 | -0.03 | 0.68 | **NOT YET** | widen/narrow threshold once, then sibling instrument, then dead |
| C1 Weekend gap: BTC Fri 21:00 UTC -> Mon 00:00 move >=2% -> FADE Mon 00:0 | at 50bps t -1.66 | 94 | -24.43 bps/trade | -0.63 | -0.86 | 0.43 | 0.88 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C2 US equity open effect: BTC 13:00->13:30 UTC move >=0.5% -> WITH it 13: | at 50bps t -3.93 | 291 | -1.85 bps/trade | -0.17 | -0.0 | -0.28 | 1.08 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C3 Asia-session reversal: BTC 00:00->08:00 UTC move >=1.5% -> FADE 08:00- | at 50bps t -5.75 | 388 | -18.33 bps/trade | -1.81 | -1.03 | -2.06 | -0.77 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C4 Funding-time drift: BTC 07:00->08:00 UTC move >=0.5% (pre-funding) ->  | at 50bps t -9.75 | 368 | -12.49 bps/trade | -2.32 | -0.72 | -3.45 | -0.91 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C5 BTC leads ETH: BTC 13:30->14:30 UTC move >=1% -> ETH WITH it 14:30->16 | at 50bps t -5.03 | 287 | -17.70 bps/trade | -1.54 | -1.68 | -0.31 | -1.84 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C6 ORB at US open on BTC: 13:30-13:45 UTC range, break by 13:50 close ->  | at 50bps t -7.49 | 589 | -24.35 bps/trade | -2.83 | -1.82 | -2.31 | 0.3 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C7 Daily-close momentum: BTC 00:00->23:00 UTC move >=3% -> WITH it 23:00- | at 50bps t -8.57 | 411 | +0.56 bps/trade | 0.12 | 1.04 | -1.87 | 0.87 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| C8 Monday open: BTC Sun 00:00->24:00 UTC move >=2% -> FADE Mon 00:00->12: | at 50bps t -1.20 | 81 | -8.60 bps/trade | -0.21 | -0.2 | -0.08 | 0.39 | **NOT YET** | widen/narrow threshold once, then ETH/SOL, then dead |
| H2b BTC overnight (21:00 prev -> 09:25 ET) >=2% -> QQQ 09:30->11:00 SAME s | 342 | -2.43 bps/trade | -0.62 | 0.39 | -1.51 | 2.42 | **NOT YET** | door 3: sibling instrument (SPY), then dead |
| M7b Last-hour momentum, WIDER: QQQ 09:30->15:00 move >=1.5% -> WITH it 15: | 189 | +10.52 bps/trade | 2.31 | 1.61 | 1.65 | 0.51 | **WORKS AT SMALL SIZE** | door 3: sibling instrument (SPY), then dead |
| F1 London open range: EUR_USD 07:00-08:00 UTC range, break by 08:05 -> co | 116 | -2.26 bps/trade | -1.16 | 0.06 | -1.74 | -0.45 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F2 London open range on GBP_USD, same shape. | 110 | -3.92 bps/trade | -1.67 | -1.46 | -0.85 | -1.17 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F3 Asia range breakout: EUR_USD 00:00-07:00 range, break by 07:05 -> cont | 48 | +2.65 bps/trade | 0.94 | 1.06 | 0.25 | -1.66 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F4 Asia-session reversal: GBP_USD 00:00->07:00 move >=0.3% -> FADE 07:00- | 56 | -1.68 bps/trade | -0.52 | 1.04 | -1.9 | -0.49 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F5 NY overlap momentum: EUR_USD 12:30->13:30 UTC move >=0.2% -> WITH it 1 | 65 | -4.96 bps/trade | -1.44 | -0.88 | -1.13 | 0.45 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F6 London fix: EUR_USD 15:00->15:55 UTC move >=0.15% -> FADE 16:00->17:00 | 114 | +0.06 bps/trade | 0.06 | -0.36 | 0.48 | -0.03 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F7 Friday afternoon fade: GBP_USD Fri 07:00->15:00 move >=0.4% -> FADE 15 | 34 | +0.24 bps/trade | 0.05 | 1.17 | -0.73 | -0.63 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F8 USD/JPY Tokyo open momentum: 00:00->00:30 UTC move >=0.15% -> WITH it  | 78 | -3.59 bps/trade | -0.94 | -1.74 | 0.55 | -0.29 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F9 Gold London open range: XAU_USD 07:00-08:00 range, break by 08:05 -> c | 107 | -3.12 bps/trade | -0.6 | 0.97 | -1.25 | 0.3 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |
| F10 Gold NY-open momentum: XAU_USD 13:30->14:00 UTC move >=0.3% -> WITH it | 125 | +4.50 bps/trade | 0.86 | 0.86 | 0.37 | -0.15 | **NOT YET** | widen/narrow threshold once, then sibling pair, then dead |

## Paper ledger — UNVERIFIED-PAPER — ORB-QQQ (Zarattini-Aziz) $100 risk/trade, simulated on Alpaca IEX 1-min bars — from 2026-11-02
trades 7 | wins 2 | $+515.20 = £+396.70 (fx 0.77)

| date | side | entry | stop | exit | reason | R | $ |
|---|---|---|---|---|---|---|---|
| 2026-11-02 | short | 695.09 | 695.55 | 695.55 | stop | -1.065 | -106.45 |
| 2026-11-03 | long | 685.52 | 683.2 | 685.32 | close | -0.099 | -9.91 |
| 2026-11-04 | short | 688.11 | 691.36 | 691.36 | stop | -1.009 | -100.92 |
| 2026-11-05 | short | 678.31 | 683.64 | 648.05 | close | 5.672 | 567.17 |
| 2026-11-06 | short | 656.45 | 658.88 | 658.88 | stop | -1.012 | -101.23 |
| 2026-11-09 | long | 665.73 | 662.19 | 678.77 | close | 3.675 | 367.51 |
| 2026-11-10 | long | 673.09 | 670.0 | 670.0 | stop | -1.01 | -100.97 |

## Queue
- H1-5 mechanisms: verified
- H6 fade-spike: verified
- H7 realfill: verified
- ORB-QQQ v2: verified
- M1: verified
- M2: verified
- M3: verified
- M6: verified
- M7: verified
- M8: verified
- M9: verified
- M10: verified
- M11: verified
- M12: verified
- M13: verified
- M14: verified
- M15: verified
- M20: verified
- M21: verified
- M23: verified
- M24: verified
- M25: verified
- C1: verified
- C2: verified
- C3: verified
- C4: verified
- C5: verified
- C6: verified
- C7: verified
- C8: verified
- H2b: verified
- M7b: verified
- F1: verified
- F2: verified
- F3: verified
- F4: verified
- F5: verified
- F6: verified
- F7: verified
- F8: verified
- F9: verified
- F10: verified