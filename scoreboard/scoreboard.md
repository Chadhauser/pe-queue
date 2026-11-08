# FIN SCOREBOARD (Verifier-only) — 2026-11-08T10:44 UTC

Money: live £0 | paper £0 | live edges 0

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

## Queue
- H1-5 mechanisms: verified
- H6 fade-spike: verified