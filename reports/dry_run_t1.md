T1 DRY RUN, no real money (£0 real; the switch is off, nothing can be sent). If the dry orders had been real £2 bets: +£4.37 on 4 settled (2% commission; the paper trial's own £ is in trial_today.md).
Started 27 Nov 14:17 UK, running 2.9 h of 48 h. Compared up to 16:50 UK (the trial writes its orders up to 10 minutes late).

**Matched 8 of 10** (same market, same team, back, price within one tick, same moment). Trial order with no dry order: 2. Dry order with no trial order: 0. Both, but different: 0.

Why the others differ (count, cause):
- 2 x the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides at start - 120 s; a quote between the two moments changed the pick

| Decision (UK) | Market | Trial picked | Dry runner picked | Cause |
|---|---|---|---|---|
| 27 Nov 16:28 | 1.266127056 | Al Wehdat 1.66 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 16:28 | 1.266123180 | Stal Stalowa Wola 1.97 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |

The placer's own limits (with the switch imagined on): 8 of 8 dry orders passed every limit; 0 were stopped by a limit.
Would send with the switch as it is: 0 (it must be 0: REAL_MONEY_OFF is present, there is no ON file, the gate is empty, the control row is off).

Written 27 Nov 17:10 UK by /root/pe-real/compare_t1.py (hourly). Detail per market: table real.t1_compare; every dry order: real.intended_orders.
