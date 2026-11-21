# What we record, against what the exchanges offer (21 Nov 2026, Builder session 15)
**Betfair offers 61 football market types today (218 matches, 6,553 markets). We record 23 of them all day, plus 3 more in play only. Of the 38 we skip, the biggest is alternative total goals: £92,000 matched on a top match.** Offered = Betfair's catalogue for today, read only. Recorded = what is on our disk, 31 Oct–20 Nov. Gap = median (lay − back) ÷ back. Matched = median money matched per market. "Real prices" = best back and lay with the money on offer.

| Football (Betfair) | Recorded? | Since | Markets a day | Prices | Gap | Matched |
|---|---|---|---|---|---|---|
| Match odds | yes: stream every tick, book every 2 min, in-play sample | 2 Nov (stream) | 186 | real | 2.9% | £17,000 |
| Over/under 0.5–5.5 | yes: book + in-play; the 2.5 line on stream since 2 Nov, 4.5 since 10 Nov | 17 Nov (book) | ~197 each | real | 3.4–4.7% | £2,400–7,600 |
| Both teams to score, correct score, half time, half-time score, half-time/full-time, double chance, draw no bet, Asian handicap, first-half 0.5/1.5/2.5, team to score 1+ | yes: book + in-play; 8 of them on stream since 10–15 Nov | 17 Nov (book) | 194–199 each | real | 4–46% (CS 22%, HT/FT 46%) | £10–9,500 |
| Match odds + over/under 2.5, match odds + both score, win to nil | in play only | 14 Nov | 135–139 | real | 22–25% | under £20 |
| Over/under 6.5 / 7.5 / 8.5 | **no** (17–18 Nov only) | – | Betfair offers 218 | – | 26% / 367% / none | £3,700 / £536 / £26 |
| Alternative total goals (quarter lines) | **no** (17–18 Nov only) | – | 218 | – | 12.6% | **£92,000** |
| Team goals 2+/3+, team over/unders, odd/even, first-half 3.5, correct score 2 | **no** (17–18 Nov only) | – | 6–209 | – | 10–60% | £5–3,700 |
| Corners (over/under 8.5–11.5), cards (over/under 2.5–5.5), shown a card, sending off, penalty, to score, shots on target | **no** | – | 9–24 | – | no two-sided prices | £16–5,600 |
| Next goal | in the book recorder's list, but Betfair offers none today | – | 0 | – | – | – |

| Other sports (Betfair) | What we record (since 31 Oct unless shown) | What we do NOT record (offered today: gap, matched) |
|---|---|---|
| Horse racing, GB/IE | win, last 12 min before the off, every tick (2 Nov, 26–37 races a day, gap 4.2%, £203,000); win and place in running (143 / 28 a day, all countries) | **place before the off**, other place terms (14%, £618), each way (32%, £287), forecast (122%, £172), reverse forecast (53%, £421), without the favourite (226%, £0), match bets (39%, £0), **win before the last 12 min** |
| Tennis | match odds in play, stream (1 Nov, 87 a day, 2.3%, £25,000); set winner (152, 7.7%, £972); game by game (186, two-sided only 18% of the time); handicap and total (~5 a day, rarely two-sided) | set betting (12%, £81), number of sets (8.7%, £216), set correct score, win a set, **every pre-match market** |
| Cricket | match odds in play (17 a day, 7.4%, £741,000) | innings runs lines (1st innings 20-over line 0.5%, £760,000), tied match (7%, £10,000), batters, draw no bet, pre-match |
| Golf | winner in play (3 a day, 46%, £195,000) | top 5/10/20 (53–135%, £23,000–40,000), each way, three balls, match bets, round scores |
| Basketball, ice hockey, American football, rugby, darts, snooker, MMA, esports | match odds / money line in play; handicap and total in play for basketball, American football, ice hockey | **every market before the start**; darts 180s (4%, £1,455), MMA method of victory (20%, £417), rugby half time, winning margin, try scorers; **greyhounds (105 races today): nothing at all** |

| Smarkets / Matchbook | Recorded | Not recorded (offered today) |
|---|---|---|
| Smarkets (since 5–11 Nov; no matched money in the feed) | in play only, football (141 matches a day: result, result + both score, result + over/under 2.5, half time, draw no bet; two-sided only 26–50% of the time, gap 12–45%), tennis (188, match and set winners, almost never two-sided), basketball (110) | over/under 0.5–6.5, correct score, both teams to score, Asian handicap, double chance, every pre-match market, racing (to win, to place top 2/3/4, gap 13–41%), ice hockey, American football, rugby, darts, snooker |
| Matchbook (since 13 Nov) | in play, football match odds only (~390 a day, gap 6.2%) | tennis and basketball (its own list asks for them, but only "Match Odds" names are kept, so their "money_line" markets drop out), totals, handicaps, correct score, both score, racing (124 meetings today, win and place), every pre-match market |

**What we are NOT recording, and why:**
1. **Never asked for:** racing place before the off, other place terms, each way, forecasts, without the favourite, match bets; greyhounds; every pre-match market outside football and GB/IE win; Smarkets and Matchbook outside in-play winner markets.
2. **A filter in a recorder:** the book recorder dropped alternative total goals, over/under 6.5–8.5, team goals and win to nil when its list was cut to 23 types (file changed 18 Nov 07:38). The in-play liquidity recorder asks for corners and cards under codes Betfair does not use (CORNER_ODDS, BOOKING_ODDS…), so it records none; the real codes are OVER_UNDER_85_CORNR, OVER_UNDER_35_CARDS and so on. The in-play recorder for other sports keeps 3 markets per event and 150 in all, so tennis set betting and cricket runs lines fall out. Matchbook keeps only markets named "Match Odds".
3. **The stream's 200-market cap:** it subscribes to 200 and leaves out about 280 every minute (stream.log 16:12 UTC). It ranks pre-match football types last, so those are the ones dropped.
4. **The test sees less than we record:** the test's day cache keeps settled markets only, so on 17–19 Nov it held 32 matches a day of the book recorder's ~199.

Sources: /root/pe-sports/markets/catalogue_today.json (today, read only) and recorded_stats.csv (day cache 31 Oct–19 Nov + liq_sample 14–20 Nov); raw counts for 20 Nov are from book_snap, stream_ticks, ip_tape and xx_tape. Today's catalogue was read at 17:15, when the early races had gone, so racing's "offered" column covers the evening Newcastle card only.
