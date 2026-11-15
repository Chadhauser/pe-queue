p = 'watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n427. ' not in s and '\n428. ' not in s
if not s.endswith('\n'):
    s += '\n'
a = ("427. RUNNING 2026-11-07 (Finder's own, source c; table fd_matches; job 499_season_open) **A league's opening round, at the closes.** "
     "Rationale: item 96 read promoted and relegated sides only, item 139 first-half goals in August only, items 88, 107, 180 the end of a season; a search of queue, ledger and jobs for opening round, first round, season opener and matchday found no read of the whole opening round, when a price leans on last season and on summer signings no game has tested. "
     "Rule fixed before any close is read: same div and season, games played before that date counted per side, same-date games are not history. G1 both sides on none. G2_3 both on 1 or 2, printed, not scored. CONTROL both on 10 or more, cannot pass. "
     "Home, Draw, Away, Over 2.5, Under 2.5, back and lay, one tick, 2%, £10, held to the final score, one bet a game. Two sources read apart: Pinnacle close, 1X2 from 2012-13 and goals from 2019-20; Betfair exchange close BFEC, from 2024-25. 20 scored lines, G1 only. Standard bar, halves by date, and because a fill at a bookmaker's close collects its margin, the line must also beat the same line on CONTROL by 0.15 per £10. Also printed, not scored: win rate v de-vigged close, top divisions apart. A close is a proxy, so a pass only earns item 428's read.\n")
b = ("428. RUNNING 2026-11-07 (Finder's own, source c, from item 427; tables fd_matches, bf_hist_other, bf_hist_result; job 499_season_open) **A league's opening round, on the tape.** "
     "Rationale: the only real prints item 427 can have. Rule fixed before any price is read, and read in the same job whatever 427 shows: item 427's G1 games on the tape, tied by date and team words with lib_cand.loose, so Aug 2023, Aug 2024 and Aug 2026, as Nov 2024 to Apr 2026 is LISTFAIL; MATCH_ODDS and OVER_UNDER_25, last pre-off print T-20 to T-2 minutes, never earlier, worse of it and the next within 120 s, one tick, over 50 not traded, 2%, £10, official result, one bet a game, women and youth out. Ten scored lines, as 427. Standard bar, halves by date. Control, not scored: CONTROL games kicked off Oct 2023, Oct 2024 or Sep 2026. A pass earns a real-touch read when the next season opens, not a stake.\n")
open(p, 'w').write(s + a + b)
p = 'watchman/HYPOTHESES.md'
s = open(p).read()
if not s.endswith('\n'):
    s += '\n'
s += "2026-11-07 | c (fd_matches) | a league's opening round at the closes (499_season_open, item 427) | RUNNING\n"
s += "2026-11-07 | c (fd_matches, bf_hist_other, from item 427) | a league's opening round on the tape (499_season_open, item 428) | RUNNING\n"
open(p, 'w').write(s)
print('ok')
