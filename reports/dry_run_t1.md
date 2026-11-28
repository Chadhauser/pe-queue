T1 DRY RUN, no real money (£0 real; the switch is off, nothing can be sent). If the dry orders had been real £2 bets: +£12.18 on 9 settled (2% commission; the paper trial's own £ is in trial_today.md).
Started 28 Nov 06:58 UK, running 14.2 h of 48 h. Compared up to 20:50 UK (the trial writes its orders up to 10 minutes late).

**Matched 99 of 116** (same market, same team, back, price within one tick, same moment). Trial order with no dry order: 15. Dry order with no trial order: 1. Both, but different: 1.

Why the others differ (count, cause):
- 2 x FINDING in how the trial records: its pick cannot be reproduced from prices up to its own decision moment (start - 120 s); it used information recorded later
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 16417407
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 219596
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 7223889
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 8831169
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 69819
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 132555
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 2503611
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 674748
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 1282856
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 122903
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 729806
- 1 x missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have picked 48818
- 1 x missed: first looked at 9 s after the decision moment (the dry runner was not running then); T1 would have picked 4364244
- 1 x missed: first looked at 9 s after the decision moment (the dry runner was not running then); T1 would have picked 46980
- 1 x missed: first looked at 9 s after the decision moment (the dry runner was not running then); T1 would have picked 69719

| Decision (UK) | Market | Trial picked | Dry runner picked | Cause |
|---|---|---|---|---|
| 28 Nov 14:58 | 1.265897654 | Oldham 2.42 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.266051038 | Yeovil 5.10 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.266108741 | Cukaricki 1.59 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.265872130 | St Mirren 2.34 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.265910274 | Bromley 2.42 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.266118790 | Stranraer 1.34 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.266119917 | Stenhousemuir 1.47 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 14:58 | 1.265851255 | Dundee Utd 1.68 | - | missed: first looked at 10 s after the decision moment (the dry runner was not running then); T1 would have pi |
| 28 Nov 17:28 | 1.266153860 | Pau 1.73 | - | missed: first looked at 9 s after the decision moment (the dry runner was not running then); T1 would have pic |
| 28 Nov 17:28 | 1.266108525 | Partizan Belgrade 1.29 | - | missed: first looked at 9 s after the decision moment (the dry runner was not running then); T1 would have pic |
| 28 Nov 17:28 | 1.266051540 | Southend 2.08 | - | missed: first looked at 9 s after the decision moment (the dry runner was not running then); T1 would have pic |
| 28 Nov 19:43 | 1.265940288 | - | Zulte-Waregem 2.14 | FINDING in how the trial records: its pick cannot be reproduced from prices up to its own decision moment (sta |

The placer's own limits (with the switch imagined on): 9 of 101 dry orders passed every limit; 92 were stopped by a limit: 91 x stopped for #: daily loss limit # reached at row #; 1 x settled loss # # open orders # # this # = # (limit #).
Would send with the switch as it is: 0 (it must be 0: REAL_MONEY_OFF is present, there is no ON file, the gate is empty, the control row is off).

Written 28 Nov 21:10 UK by /root/pe-real/compare_t1.py (hourly). Detail per market: table real.t1_compare; every dry order: real.intended_orders.
