T1 DRY RUN, no real money (£0 real; the switch is off, nothing can be sent). If the dry orders had been real £2 bets: +£12.18 on 9 settled (2% commission; the paper trial's own £ is in trial_today.md).
Started 28 Nov 06:58 UK, running 8.2 h of 48 h. Compared up to 14:50 UK (the trial writes its orders up to 10 minutes late).

**Matched 68 of 69** (same market, same team, back, price within one tick, same moment). Trial order with no dry order: 0. Dry order with no trial order: 0. Both, but different: 1.

Why the others differ (count, cause):
- 1 x FINDING in how the trial records: its pick cannot be reproduced from prices up to its own decision moment (start - 120 s); it used information recorded later

| Decision (UK) | Market | Trial picked | Dry runner picked | Cause |
|---|---|---|---|---|
| 28 Nov 13:58 | 1.265880589 | Mlada Boleslav 2.72 | Sigma Olomouc 2.70 | FINDING in how the trial records: its pick cannot be reproduced from prices up to its own decision moment (sta |

The placer's own limits (with the switch imagined on): 9 of 69 dry orders passed every limit; 60 were stopped by a limit: 59 x stopped for #: daily loss limit # reached at row #; 1 x settled loss # # open orders # # this # = # (limit #).
Would send with the switch as it is: 0 (it must be 0: REAL_MONEY_OFF is present, there is no ON file, the gate is empty, the control row is off).

Written 28 Nov 15:10 UK by /root/pe-real/compare_t1.py (hourly). Detail per market: table real.t1_compare; every dry order: real.intended_orders.
