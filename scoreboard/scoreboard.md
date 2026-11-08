# FIN SCOREBOARD (Verifier-only) — 2026-11-08T23:00 UTC

Money: live £0 | paper £191.47 | live edges 0

## Data health
- alpaca_etf: ok | last 2026-11-06 21:59 | rows24h 0 
- alpaca_stocks: ok | last 2026-11-06 20:59 | rows24h 0 
- yf1m: ok | last 2026-11-06 21:59 | rows24h 0 
- local_pg: ok | last None | rows24h None fin_heartbeat 2026-11-06 23:40:04.253999+01:00 ok

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

## Paper ledger — UNVERIFIED-PAPER — ORB-QQQ (Zarattini-Aziz) $100 risk/trade, simulated on Alpaca IEX 1-min bars — from 2026-11-02
trades 5 | wins 1 | $+248.66 = £+191.47 (fx 0.77)

| date | side | entry | stop | exit | reason | R | $ |
|---|---|---|---|---|---|---|---|
| 2026-11-02 | short | 695.09 | 695.55 | 695.55 | stop | -1.065 | -106.45 |
| 2026-11-03 | long | 685.52 | 683.2 | 685.32 | close | -0.099 | -9.91 |
| 2026-11-04 | short | 688.11 | 691.36 | 691.36 | stop | -1.009 | -100.92 |
| 2026-11-05 | short | 678.31 | 683.64 | 648.05 | close | 5.672 | 567.17 |
| 2026-11-06 | short | 656.45 | 658.88 | 658.88 | stop | -1.012 | -101.23 |

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