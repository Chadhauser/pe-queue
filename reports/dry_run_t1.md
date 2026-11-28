T1 DRY RUN, no real money (£0 real; the switch is off, nothing can be sent). If the dry orders had been real £2 bets: +£8.08 on 11 settled (2% commission; the paper trial's own £ is in trial_today.md).
Started 27 Nov 14:17 UK, running 14.9 h of 48 h. Compared up to 04:50 UK (the trial writes its orders up to 10 minutes late).

**Matched 50 of 58** (same market, same team, back, price within one tick, same moment). Trial order with no dry order: 7. Dry order with no trial order: 0. Both, but different: 1.

Why the others differ (count, cause):
- 6 x the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides at start - 120 s; a quote between the two moments changed the pick
- 1 x never looked at: 2228 pre-off stream prices for it in the hour before the live moment (it should have been in the schedule: a fault in the new code)
- 1 x never looked at: 830 pre-off stream prices for it in the hour before the live moment (it should have been in the schedule: a fault in the new code)

| Decision (UK) | Market | Trial picked | Dry runner picked | Cause |
|---|---|---|---|---|
| 27 Nov 16:28 | 1.266123180 | Stal Stalowa Wola 1.97 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 16:28 | 1.266127056 | Al Wehdat 1.66 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 17:58 | 1.265989435 | Omonia FC Aradippou 2.16 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 17:58 | 1.266013213 | Athletic Bilbao B 2.30 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 17:58 | 1.265926756 | Portimonense 2.38 | - | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 18:28 | 1.265929799 | DEBRECENI VSC 2.68 | Gyori 2.68 | the price changed in the last 5 seconds: the live runner acts at start - 125 s (as ordered), the trial decides |
| 27 Nov 23:58 | 1.266078510 | Academia de Balompie Boliviano 1.69 | - | never looked at: 2228 pre-off stream prices for it in the hour before the live moment (it should have been in  |
| 27 Nov 23:58 | 1.265836230 | Tristan Suarez 1.89 | - | never looked at: 830 pre-off stream prices for it in the hour before the live moment (it should have been in t |

The placer's own limits (with the switch imagined on): 11 of 51 dry orders passed every limit; 40 were stopped by a limit: 39 x stopped for #: daily loss limit # reached at row #; 1 x settled loss # # open orders # # this # = # (limit #).
Would send with the switch as it is: 0 (it must be 0: REAL_MONEY_OFF is present, there is no ON file, the gate is empty, the control row is off).

Written 28 Nov 05:10 UK by /root/pe-real/compare_t1.py (hourly). Detail per market: table real.t1_compare; every dry order: real.intended_orders.
