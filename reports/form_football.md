# Football form guide against the price — 27 Nov 2026, final page

**Money:** £0 real (paper only, no order endpoint). Paper: the form trial FORM1 starts tonight, 0 of 100 settled. **Data:** Betfair stream live; API-football live stats and the v3 goal signal live; **the book recorder has failed since 05:46 UTC today** ("cursor already closed" every 30 s, team/book_recorder.py, not mine to touch).

## Form guide
**Made of:** each team's goal margin (capped at 3) and chances made minus allowed (expected goals, else shots on target), measured against the opponent's strength and weighted to recent games, plus home/away extra, rest days, playing abroad, and whether it keeps beating its exchange price. 224,150 matches, 49 competitions down to the National League; `football_form.form_rating`, rebuilt daily. Fitted on 2017-24, **tested on 8,863 matches it never saw** (Jul 2025 - Nov 2026).
- **Higher-rated side won 49.4%; the price said 49.2%.** Before the start the price already holds what our form knows (price alone 0.9946, price + form 0.9953; lower is better). Backing what our form likes loses: -17.7 per £100 in history, -19 to -30 at real prices.
- **The other way round pays:** a side the price rates well above our form beats even its price. History, start price: 10+ points +4.4 per £100 (both halves), 15+ +14.1. **Real prices** (our quotes 2-26 Nov, real fills, £50 cap, 2% commission), back it 2 minutes before: 5+ points: **268 bets, +11.6 per £100, about £52 a day**, both halves (+£617 / +£797), +£774 without the best day.
- **By money:** £10-50k matched +32.7 per £100 (both halves); thin, under £10k: about level (+0.5); £250k+: -15.9. **By type:** second tiers +38.5 and other top flights +16.6 (both halves); big-five -15.0; European cups -1.3. Double chance on the same sides loses (-5.4): the edge is in the win.
- **Frozen for the paper trial (FORM1):** gap 10+ points an hour before, back 2 minutes before. Recorded: 69 bets, +16.6 per £100, **about £20 a day**. Settled by our own job into `football_form.trial_bets`.
- **In play:** no form edge at real prices yet. History (last-traded, ideas only): a side one up at half-time that our form had rated above its price won 58.8% against 61.1% priced (546), so it folds a little more. Draw back when the price-favoured side trails by one: +14.4 per £100 (both halves). At real prices only 13 such bets (-16.4). "Back the draw when level at half-time" was +4.4 in history but **-12.6 at real prices** (286 bets): the back-lay gap eats it.

## Known rules, kept in, run inside every type
69 rule versions (vendor S6-S28, the F_ price-band rules by league, draw and home lays, HT patterns), each by tier, country, favourite strength, form, thin; 54 again at real prices by league group, money and form.
- History, unseen dates: 14 rules pay in both halves. Real prices: 75 of 985 cells pay in both halves and without their best day, about what luck gives.
- **Pay in one type though they lose overall** (real, both halves): PM1 back over 2.5 at 1.6 or shorter, leagues we don't rate: +10.3 per £100, £39 a day (293 bets; -2.5 overall). Back away 2.0-2.5 in thin markets: +8.2, £23 a day (-1.3). Lay home 2.5-3.0 in £10-50k markets: +17.9, £15 a day (-9.1). 27 such cells.
- **Holds in history and at real prices:** lay the home side at 3.0-3.5 two minutes before: history +3.5, real +5.5 (202 bets, both halves), about £10 a day.
- Fail at real prices: S7 (lay the draw 3.0-3.5, history -11.7), S9/S16 (home lays 4.0-5.0, real -6 to -12), HT draw. Lays at 5.0+ (S8, F_ 5.0+ lays) not run: rules forbid; their opposite backs are in the tables.

## Peter's eyes on the big games
- **Watch card** `reports/watch_card.md`, daily 09:30 and 16:30 UTC: today's 6 biggest games pushed (most money matched; we hold no TV listings).
- **Questions**, picked from 1,634 top-five-league games where a yes moved the result more than the price (ideas, not money): **Q25** favourite on top at 25 min? (+5.8 per £100 backing it then); **QHT_LEVEL** level at HT, favourite clearly better chances? (+15.8); **QHT_00** 0-0 at HT, open game? (over 1.5, +22.7).
- **Score sheet** `football_form.eye_calls`: the machine answers every question live (source machine). Peter's answer goes beside it: `python3 /root/pe-sports/sports/football_form/record_eye.py answer chelsea Q25 yes`. `record_eye.py score` gives £ after 30 games. Note: live expected goals are API-football's; the history used understat's.

*Checked: no look-ahead (features unchanged with the future removed), live predictor = pipeline, hand-worked rating and fill sums: 19 known-answer tests pass. Not tried: Asian handicap, draw no bet (voids not in our extraction), next goal. Other exchanges (3-19 Nov): Matchbook 19 bets, +64 per £100 over 4 days, too few to count; Smarkets: no linked market with fresh quotes 2 minutes before.*
