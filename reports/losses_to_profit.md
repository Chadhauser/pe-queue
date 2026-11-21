# Losses to profit: who was on the other side (21 Nov 2026, Builder session 9)

**Of the paper loss of −£5,993 (8,681 settled bets, each once, 19–21 Nov): −£7,602 from costs, +£8,747 from prices (they went our way on average), −£7,137 from not getting out.** The costs went to whoever offers prices. The not-getting-out loss is racing (−£9,110), where we backed outsiders 10 minutes before and the only exit was a closing lay we could not fill. That is more than luck alone would give (−2.8 standard deviations); across all trades it is −1.8.
**Other-side rows that hold up on all days and both halves: none yet.** Nearest: way 63513, in UK and Irish racing two minutes before the off, rest a back 5 ticks above the lay price for backers who must get out. It made +5.6 per £100 on 515 orders (+1.8 first half, +8.9 second), but −10.8 without its best day and three biggest winners, its worst day was −£1,012, and its largest single loss −£50. The league's standard bar put it on paper; this session's honesty check does not pass it. Forward paper decides at 100 settled. Next test: 20–21 Nov through the one test once they are cached, Mon 23 Nov.

**Who was on the other side, all recorded days (31 Oct–19 Nov through the one test, the 187 paper rules, 73,741 bets once).** Costs are the only steady loss: −2.2 per £100 in the first half, −2.4 in the second, −2.7 on paper. Prices and exits were +2.6 / +2.5 per £100 in the first half, +1.4 / +0.6 in the second, and +3.1 / −2.5 on paper. These rules were picked for paper on these same days, so that edge was selection, and it wore off: total +2.9 → −0.4 → −2.1 per £100. So the people taking the other side of our bets did not out-guess us. The steady winner was whoever offers prices. A straight mirror cannot pay because the originals won on the recorded days. Every one of the 40 mirrors loses on at least one half.

| Where the loss sits (£ kept per £100: total = costs + prices + not getting out) | Paper 19–21 Nov | All days, 1st half | All days, 2nd half |
|---|---|---|---|
| Horse racing | −11.8 = −1.8 +0.2 −10.2 (2,748 bets) | +4.9 = −2.4 +2.9 +4.3 | −0.3 = −2.2 +1.9 −0.1 |
| Football | +2.5 = −2.9 +4.4 +1.1 (5,776) | +1.7 = −1.9 +2.1 +1.5 | −0.3 = −2.3 +1.2 +0.8 |
| Entry price 20+ / 10–20 | −0.9 / −11.9 | +9.1 / +2.1 | −5.5 / −0.4 |
| Entered 2–10 min / last 2 min before the off | −5.8 / −5.7 | +4.0 / +2.2 | −0.8 / +1.4 |
| Trade, exit missed / held bet | −8.0 (−£7,721) / +3.6 | +3.4 / +2.4 | −1.4 / +0.7 |

| Other-side row (each a TRADE with 10% target, 10% stop and a time limit unless BET) | Rows | Orders | Best row: £ per £100, 1st / 2nd half | Without best day and 3 biggest winners | Worst day | Largest single loss | Verdict |
|---|---|---|---|---|---|---|---|
| Mirror, taking the price (20 worst rules) | 20 | 29,572 | racing p120 mirror 63481: −0.35 / −0.28 | −0.34 | −£15 | −£1.59 | NOT YET: none positive in either half |
| Mirror, offering at the price we took | 20 | 8,649 | 63482: −0.37 / −0.33 (football half-time/full-time 63486: 11 orders only) | −0.38 | −£12 | −£1.51 | NOT YET |
| Offer 1–2 ticks better than we took | 18 | 4,103 | 63504: −0.25 / −0.18 | −0.26 | −£7 | −£1.33 | NOT YET: fills come when the price runs against |
| Be the exit, racing, 5–10 ticks away | 24 | 7,527 | 63513 (p120, back +5 ticks): +1.8 / +8.9 | −10.8 | −£1,012 | −£50 | WORKS ON PAPER BAR ONLY; in play (i10–i60) loses up to −37 per £100 |
| Lay long shots 10–15 / 15–25 / 25–50, held (BET) | 3 | 1,543 | 15–25 (63542): −0.98 / +0.29 | −0.81 | −£115 | −£50 | NOT YET; 50+ fills nothing (£1 minimum under a £50 liability) |
| Lay long shots, only deep markets (£20k+), held / traded | 6 | 2,382 | 10–15 traded (63540): −0.58 / −0.30 | −0.59 | −£18 | −£5 | NOT YET |

Long shots across all days: backing does NOT lose more than its costs in every band. Backing at 10–15 made −6.1 / +26.1 per £100 by half, 15–25 −14.3 / −19.4, 25–50 +70 / −48, and 50+ +25 / −53, against costs of 4–8. Only 15–25 loses beyond its costs on both halves. Laying that band kept −0.32 per £100 (560 orders), because a £50-liability lay stakes about £2. Three days of long shots losing was mostly luck.
Checked: the loss split was hand-worked on five bets (s9/test_split.py ALL PASS), and costs + prices + exits add to each bet's profit to the penny. The new exit with a target, a stop and a time limit (onetest 'tst') has 9 hand-worked checks in test_known.py, ALL PASS, including one where the £50 closing-lay cap applies. Paper figures are rebuilt from stored bets matched to recorded quotes (0 bets without quotes). For a trade, 'prices' runs to the moment it was due out, so for racing exits timed after the off it includes part of the race.
Not done: 20–21 Nov through the one test. Building that day from the database needs about 6 GB, and the paper trader peaks at 10 GB; my first run helped cause three out-of-memory kills of the paper trader (12:31–12:51 UTC) before I made it lighter. The test fills in-play orders at the quote of the moment, which is generous.
Side effects: the league pass run to add these rows took 14 ways off paper under the standing forward gate (100+ settled, a losing half) and put way 63513 on paper. 98 rows added (ids 63455–63552). Files: /root/pe-builder/s9. Paper only, no orders, nothing deleted; backups *.bak_session9.
