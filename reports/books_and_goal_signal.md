# Exchanges against each other; the goal signal (session 11, 21 Nov 2026, final version 17:05 UTC; first pushed 16:55)

**1. Crossed prices: about 6 real ones a day, about £1 locked per £100, gone within 24–48 s, worth about £3–4 a day at £50 stakes. NOT YET.** Smarkets and Matchbook polls show about 206 crosses a day against Betfair at a single poll. 79% are gone by the next poll, and nearly all the rest are goals (Betfair suspended within 3 minutes) or a Betfair price that wasn't trading. Checked against Betfair's own status field on 14–19 Nov, 35 crosses in 6 days were real: they lasted 2 polls (24–48 s) and locked a median £1.05 per £100. In total that is £21 at £50 stakes (£48 counting two absurd prices).
**2. Lead and lag: no lag we can trade. NO, in both halves.** Smarkets and Matchbook move with Betfair within 0–3 s, which is below what our timestamps can measure. In play the correlation is Smarkets 0.93 / 0.91 and Matchbook 0.77 / 0.86 (H1 3–11 Nov / H2 12–19 Nov). Backing their old price after Betfair shortens pays only at goals, when they are suspended themselves. Without goals (14–19 Nov) it loses £4–7 per £100 closed on the slow exchange and £2–7 closed on Betfair. Counting every trade, both halves lose when closed on either exchange: H1 −£1 to −£15, H2 −£7 to −£33, about 5 trades a day.
**3. Goal signal: running YES (19 alerts today, last 15:54 UTC); predicts goals NO (+2.7 points of goals in the 10 minutes after half-time, H1 +3.2 / H2 +2.2, but "under" alerts show the same lift the wrong way, so it is a league effect); beats the price NO (−£0.4 to −£1.1 per £100, H1 +£0.05 to −£1.33, H2 −£0.46 to −£1.46, n 58).**

Money: £0 live, £0 paper from these routes. What it DOES support: Betfair is the price; the other two copy it within seconds, so neither "faster" route pays while we take the price. Next door: rest orders inside Matchbook's wide book (back/lay gap a median 6.6%) and close on Betfair. That needs Matchbook's traded volume, which **I started recording tonight** (`books.mb_tape`, 16:47 UTC). **Test on 24 Nov** with 3 days of fills.

## A1. Crossed prices (in play, match winner; Betfair 2%, Smarkets 2%, Matchbook 2% — the project's recorded rate, `bookie_xx.py`, unverified against Matchbook's own tariff)
| | per day | median £ per £100 | still there ~24 s later |
|---|---|---|---|
| All first sightings, 3–19 Nov (17 days) | 206 | 1–4 | 21% |
| Still there at the 2nd poll and Betfair changed in the last 5 s: H1 3–11 Nov / H2 12–19 Nov | 15 / 11 | 2.9 / 1.9 | goals not excluded before 14 Nov |
| **Real: 14–19 Nov, 2nd poll, no Betfair suspension from 3 min before to 1 min after** | **6** | **1.05** (Betfair→Smarkets 1.97, Smarkets→Betfair 0.78) | lasted a median 2 polls; 31% lasted 3+ |
- **Where they fall:** the false crosses are mostly basketball and tennis on Smarkets. On 14–19 Nov, 100% of the basketball ones had no Betfair ticks in the ±30 s around them. The real ones are football and tennis, mostly short prices (1.04–1.15) near the end of matches.
- **Before the start:** about 1 a day (Matchbook only), £0.1–0.5 per £100. xx_recorder keeps no Smarkets prices before the start.
- **Polling:** Smarkets and Matchbook are polled every 23.7 s (median; Smarkets p90 48.9 s because of HTTP 429s). Betfair is the tick stream. The duration of a cross is only known to ±24 s.

## A2. Lead and lag (3–19 Nov, 17 days; H1 3–11, H2 12–19)
| | pairs of polls | peak of correlation | corr at −12/−6/0/+6/+12/+24 s |
|---|---|---|---|
| Smarkets, in play (H1 / H2 peak corr 0.93 / 0.91) | 180,386 | 0 s | 0.48/0.81/0.92/0.67/0.37/0.00 |
| Matchbook, in play (H1 / H2 0.77 / 0.86) | 227,875 | −3 s (timestamp taken before the fetch) | 0.49/0.76/0.76/0.54/0.28/−0.05 |
| Matchbook, before the start (H1 / H2 0.68 / 0.65) | 482,977 | −3 s | 0.42/0.59/0.64/0.49/0.33/0.07 |
- **No lag to measure:** the 24 s polling did not block the test. Polls land at random moments relative to Betfair's moves, so the lag can be read to about 3 s, and it is 0.
- **Polling to trade it:** you would need prices about every 1 s. Smarkets already refuses us at 24 s (12,531 HTTP 429s in recorder.log). Matchbook's free feed answers a full pass in 1–2 s. Even so, the 0–3 s lag is shorter than the in-play bet delays (Betfair 5 s in football), so faster polling can't pay in play. I did not start a faster recorder.
- **Books nobody updates:** where Smarkets or Matchbook quotes are wide (median lay/back 1.25–1.46 in play), their best price copied a median 0% of a 3% Betfair move even 48–96 s later. Those are resting orders nobody is managing. That is the next door, not a taker's edge.

| Stale back after a Betfair shortening ≥3% (back first, price < 5.0, £50 cap, 2%) | n | lay at once on Betfair (+5 s) | close on the slow exchange (target +1%, stop −3%, 120 s) | close on Betfair, same rules |
|---|---|---|---|---|
| 14–19 Nov, no Betfair suspension, entry at the next poll | 30 | −6.76 | −4.10 | −6.53 |
| same, entry at the poll | 10 | +0.85 | −6.62 | −1.65 |
| at goals (Betfair suspended): not real, the slow exchange is suspended too | 32 | +35.17 | −19.38 | −14.77 |
| All 17 days, every trade, entry at the next poll: H1 / H2 (Matchbook) | 51 / 50 | +1.14 / +12.87 (goals) | −12.22 / −8.36 | −7.49 / −7.05 |
| same, Smarkets: H1 / H2 | 31 / 18 | +4.14 / +14.55 (goals) | −9.30 / −20.52 | −7.00 / −18.37 |

Entry is the first poll after the move (median 11–20 s later). I can only tell goal moments apart from 14 Nov, when Betfair's raw stream status starts. Sizes: the cash on offer is taken as each feed reports it, and the Betfair closing leg assumes Betfair can take £50.

## A3. Offering on the quiet exchange, closing on Betfair
- **Can't test yet:** the tape has no trades for either exchange. Last-traded price is present on 0% of 5.7M Matchbook and 1.8M Smarkets rows, and the existing recorder keeps no volume or market status.
- **Now recording:** Matchbook's free, no-login feed gives traded volume per runner and a suspension flag. `mb_volume_recorder.py` now records them every 20 s for football Match Odds, before and during play, about 174 markets. It is registered in watch.list as `mbvol`.
- **Still missing:** Smarkets volume (its API already rate-limits us).

## C. The goal signal (monitor_ht.py; goal_alerts)
- **Running:** up since 19 Nov (pid 1597574). 19 alerts today, the last at 15:54:25 UTC, 1,329 stored in all. Every one is a half-time trigger: 934 "back over", 395 "back under".
- **Predicts goals:** 1,242 of 1,329 alerts join to `goal_timeline`. The comparison is the same half-time score in leagues without an alert; same league and score leaves only 67 alerts.

| | 10 min | 15 min | 20 min |
|---|---|---|---|
| Over alerts (n 789): goal rate, alert / comparison | 31.2 / 28.5% | 44.5 / 40.8% | 53.9 / 50.3% |
| Lift, H1 / H2 (dates split 12 Sep) | +3.2 / +2.2 | +3.4 / +4.0 | 0.0 / +7.5 |
| Under alerts (n 315): lift in goals, should be negative | +2.6 | +1.3 | +3.4 |

- **Delay:** alerts fire a median 12 s after half-time shows (p90 54 s), and none after the restart. The delay costs nothing.
- **In the price:** back the next over line at Betfair's price on offer, 5 s after the alert, £50 capped at the money shown. Stop at a lay price of 1.15× entry, with a 10/15/20-minute limit and 2% commission. Data is `liq_sample`, 31 Oct–21 Nov.
  - Over alerts (n 58): −£0.39 / −£0.87 / −£1.07 per £100. H1 (n 41): +£0.05 / −£1.04 / −£1.33. H2 (n 17): −£1.46 / −£0.46 / −£0.46.
  - Same trade, no alert (n 1,214): −£2.0.
  - The alerts won the line 82.8% of the time against 83.6% implied by the price: the price already has it.
- **In conjunction, a quoter pulling unders while an alert is live:** the most it saves is about £2.70 per £100 exposed, which is inside the noise. The alerts fire at half-time anyway, so the simpler rule is to pause during the break.
- **In conjunction, Smarkets or Matchbook overs left stale after an alert:** can't be tested. Neither exchange's over/under is recorded (Matchbook Match Odds only; Smarkets winner markets only).

Files: /root/pe-sports/books/partA_*.py (tests: partA_test.py), partC_*.py, partC_summary.md; tables books.mb_tape, books.partc_ht, books.partc_alerts. The bookmaker collector an earlier run left going was stopped (`#STOPPED-706`, files kept).

What I need from you: nothing.
