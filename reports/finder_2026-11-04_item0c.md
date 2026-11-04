# Finder 2026-11-04, item 0c: audit of the racing pre-off scalper paper bot

**Data used:** preoff_scalp_paper, 117 trades on 19 races, all 3 Nov 12:14–19:26 UTC. stream_ticks 1–3 Nov for the fill checks and the replay, 69 races, 3.3M ticks.

**Job:** jobs/479. The output is in the harness task file, as this run could not write to /root/pe-queue-logs. **Fix applied once:** the first run stopped on my own known-answer check (the tick below 4.0 is 3.95, not 3.9), before any data was read. The P&L code did not change.

**Timing:** audited at about 22 h, not 24 h, and only one racing afternoon has traded. The bot's own 117 trades cannot reach n 300, so the replay carries the verdict.

## Bot's own trades

As recorded: n 117, −£0.27/£10, t −9.44, hit rate 12.8%, mean −1.28 ticks, sum −£31.56. Re-priced to house rules: **−£0.54/£10, t −14.91** (BACK n 90 −0.655, LAY n 27 −0.155). Filling at the next tick instead: −£0.53. All 117 fall on one day, so a date split is impossible; by time of day, h1 n 57 −0.205, h2 n 60 −0.331.

| cut | n / per £10 as recorded |
|---|---|
| exit | stop 74 −0.440; time 25 −0.114; target 13 +0.354; pre_off 5 −0.154 |
| price band | 2–3: 21 −0.110; 3–5: 36 −0.202; 5–8: 60 −0.366 |
| secs to off | 30–120: 15 −0.297; 120–300: 52 −0.298; 300–600: 50 −0.233 |
| venue | Fairyhouse 8 −0.129; Lingfield 27 −0.255; Sedgefield 42 −0.278; Warwick 31 −0.287; Wolverhampton 9 −0.342 |

## Bot against its spec

| item | does | should do | grade | evidence |
|---|---|---|---|---|
| UK/IE WIN only | stream catalogue filtered to GB, IE, WIN | same | PASS | pe-stream/stream_client.py:27 |
| Never in play | 0 entries and 0 exits at or after the off | none | PASS | in-play tick found for 19 of 19 races; secs to off at entry 33..598 |
| Targets traded through | 13 of 13 confirmed by ltp beyond target with tv up | through, not touch | PASS | Part B |
| Stops and time exits at the real touch | 90.4% equal the last touch before the exit stamp | real touch | PASS with a gap | the other 9.6% not traced; the bot stamps the time before its read, which may explain them |
| Entry fills | fills at once at the touch, no trade-through test | "only when the touch trades through" | FAIL | code line 80–86; 93.2% printed beyond entry within 60 s, a weak test as ordinary prints at the far touch count |
| "Not lengthening" filter | compares last three per-tick ltp values, which repeat | last three TRADED prices | FAIL | one race checked, 23,672 ticks: per-tick flag 0 times, traded flag 132 times, so the filter does nothing there |
| Weight of money depth | touch only, mean of tick ratios | first three price points | FAIL | no size at levels 2–3 in stream_ticks, so the spec cannot be tested here |
| £50k matched | sums tv only over runners that ticked in the last 45 s | total matched | FAIL, minor | code line 39–46; can understate, effect not measured |
| Lay risk | £10 stake, mean liability £44.65 | house rule: £10 liability | FAIL | code line 29 |
| Venue column | absent | table includes venue | FAIL, minor | derived for 117 of 117 from other tables |

**Not fixed:** the bot is under /root/pe-race, which the Finder may not touch. These need Peter or the strategy chat, and the verdict below gives no reason to spend time on them.

## Independent replay, own code, signal then fill on the next tick

48 lines, top 15 by t after merging BOT and SPEC where they match. Halves: 1 Nov v 2–3 Nov. None passes.

| line | n | races | per £10 | t | h1 | h2 |
|---|--:|--:|--:|--:|--:|--:|
| BOT/SPEC exit=target | 35 | 27 | 0.000 | 0.00 | 0.000 | 0.000 |
| FADE exit=target | 66 | 40 | 0.000 | 0.00 | 0.000 | 0.000 |
| FADE secs 30–120 | 58 | 38 | −0.200 | −7.58 | −0.188 | −0.208 |
| BOT/SPEC exit=pre_off | 10 | 8 | −0.633 | −8.22 | −0.810 | −0.515 |
| FADE first per race | 69 | 69 | −0.297 | −8.55 | −0.280 | −0.309 |
| FADE no cost | 497 | 69 | −0.072 | −9.07 | −0.087 | −0.065 |
| FADE exit=pre_off | 23 | 19 | −0.118 | −11.86 | −0.126 | −0.111 |
| FADE secs 120–300 | 185 | 64 | −0.256 | −12.12 | −0.331 | −0.217 |
| FADE exit=time | 153 | 45 | −0.201 | −12.59 | −0.246 | −0.177 |
| BOT/SPEC first per race | 69 | 69 | −0.520 | −12.65 | −0.550 | −0.499 |
| FADE band 3–5 | 168 | 48 | −0.266 | −13.59 | −0.302 | −0.248 |
| FADE band 2–3 | 69 | 27 | −0.197 | −13.62 | −0.209 | −0.193 |
| FADE band 5–8 | 260 | 60 | −0.239 | −13.88 | −0.279 | −0.219 |
| BOT/SPEC exit=time | 89 | 38 | −0.407 | −14.88 | −0.412 | −0.404 |
| BOT/SPEC secs 30–120 | 58 | 38 | −0.695 | −15.50 | −0.700 | −0.692 |

Whole-rule lines: BOT/SPEC one tick n 498 −0.546 t −35.52 (h1 −0.521, h2 −0.559), no cost −0.233 t −21.55, three ticks −1.130. FADE one tick n 497 −0.243 t −21.29. no_exit 0 in all three. Reproduction on 3 Nov: replay n 149, no cost −0.230, v the bot n 117, −0.220 on the same basis; the n gap is not explained.

**Read these with care:** a two-tick target less one tick each way nets exactly £0, so no trade can win under the house rule, which is why hit rates show 0. That is why the no-cost lines matter: both directions lose before any cost. BOT and SPEC match to three decimals, probably because the filter rarely binds, but they were not compared trade by trade. Trades per race are correlated, so t is inflated; the first-per-race lines are the fairer read. Only three racing days.

## Verdict

Nothing passes: 0 survivors. The bot loses −£0.54/£10 at house costs on its own trades (n 117), and the independent replay agrees at −£0.55 (n 498, both halves negative). Flipping the side, as job 459's inverted signal suggests, loses less but still loses, −£0.24 at one tick and −£0.07 at no cost. Fills are honest where it matters (no in-play trades, targets genuinely traded through), so this is a real loss and not a recording fault. Lead → item 53, as the two-tick target is what makes the scalp unable to pay.
