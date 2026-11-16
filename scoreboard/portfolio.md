# Portfolio lab — rating simulator (PROXY) — 2026-11-16 10:02 UTC

Streams: ORB-QQQ 1400 trades, M7b 189 trades, 1584 days 2020-07-27 -> 2026-11-13.
Correlation ORB vs M7b daily: +0.06 (all days), +0.00 (days both traded). Low = they diversify.

Judged on the SECOND half only (anything fitted used the first half). D-VaR CAGR = CAGR if rescaled to 6.5% monthly 95% VaR (Darwinex-style).

| sizing | CAGR | vol | Sharpe | max DD | Calmar | +months | worst month | D-VaR CAGR | D-VaR max DD |
|---|---|---|---|---|---|---|---|---|---|
| fixed 0.5% risk ORB only | +19.5% | 19.4% | 1.02 | -14.5% | 1.35 | 64% | -5.9% | +28.7% | -21.0% |
| fixed 1% risk ORB only | +37.9% | 38.7% | 1.02 | -27.5% | 1.38 | 64% | -11.5% | +29.2% | -21.3% |
| fixed 1% ORB + 1x M7b | +40.3% | 39.2% | 1.05 | -27.4% | 1.47 | 64% | -11.5% | +30.3% | -20.8% |
| vol-target 10%, ORB+M7b | +14.2% | 11.9% | 1.17 | -9.8% | 1.45 | 59% | -5.2% | +34.4% | -22.9% |
| vol-target + DD throttle | +10.4% | 10.5% | 0.99 | -9.0% | 1.15 | 56% | -5.8% | +24.4% | -21.0% |
| vol-target, max 1.5% risk/trade + DD throttle | +10.4% | 10.5% | 0.99 | -9.0% | 1.15 | 56% | -5.8% | +24.4% | -21.0% |
| quarter-Kelly (ORB 0.006, M7b 3.00x) fit on 1st half | +31.5% | 27.6% | 1.13 | -18.1% | 1.74 | 56% | -7.5% | +36.9% | -21.0% |

**Best by Calmar (2nd half): quarter-Kelly (ORB 0.006, M7b 3.00x) fit on 1st half** — whole-history check: CAGR +35.2%, max DD -19.7%, Calmar 1.79, positive months 58%.
Reading: a rating that rewards return per unit of drawdown wants the row with the highest Calmar and positive months, not the highest CAGR.
Caveats: rating formula is a proxy; costs are the backtest's (1c spread + 1c slip/side on QQQ) — a CFD at Darwinex charges its own spread, measured once the MT5 demo runs.