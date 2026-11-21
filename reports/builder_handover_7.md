Perfect hindsight: a £50 trader taking prices in every market at once could have made £104,800 a day on Betfair, 31 Oct-19 Nov (£72,900 counting each two-runner market once); 94% of it was in play, 42% tennis and 40% football, mostly reversals. Hindsight only, not a result (reports/winners_map.md).
Step 3 found 300 conditions (237 single, 63 pairs) that separated winners on the first half (31 Oct-9 Nov). 0 survived the second half (10-19 Nov) as rules. Kept per £100, all 8.16 million test orders together: first half -15.6, second half -13.0.
Rules that hold: none. Nothing was added to earn_ways and nothing went onto paper.

What the numbers say (reports/winners_check.md has both halves side by side):
- As a pattern the conditions are real. On the unseen half they still pick moments with a winning trade after them 69% of the time (median; 50% by chance). As trades they lose. A rule has to fix its exit in advance and pays the back-lay gap going in. Stops fired 6.8 million times, targets 0.75 million.
- Most conditions say the same thing: back just after the price rose, lay just after it fell, or (racing) the first in-play moment. They catch a bounce that hindsight can use and a rule cannot.
- Rules in profit: 8 of 600 on the first half, 14 on the second, 0 on both.
- By sport, first half / second half per £100: racing before the start -0.5 / -0.6 (closest to break-even), football before the start -4.8 / -5.0, cricket in play -10.4 / -5.5, tennis in play -13.4 / -15.5, football in play -15.0 / -15.1, racing in play -20.3 / -17.2.
- Nearest miss: cricket in play, lay when £12,280+ traded in the last minute and the gap is 1 tick: second half +11.9, but first half -12.2 (3,825 / 4,784 orders). It fails the both-halves bar.
- Verdict: NOT YET. Next door, 22 Nov: the same racing-before-the-start conditions entered by OFFERING (resting) instead of taking. Taking loses only 0.5-0.6 per £100, about what the gap costs, and resting earns the gap instead of paying it.

Built (all new files in /root/pe-sports/grid): winners.py (table grid.winners: 124,749 take and 80,166 offer trades over 20 days, plus 3,513 on Matchbook), s7feat.py (what was known at each quote), s7build.py, s7split.py (step 3, first half only), s7rule.py (onetest kind 'cond': entry on the condition; exit = target, stop and time limit fixed from first-half winners, or a tight 3%), s7check.py (step 4), s7map.py, s7report.py.
Checked:
- test_known.py ALL PASS, 186 checks. 32 are new hand-worked S7 checks: the back 2.00 / lay 1.90 trade (+£2.5789); the £50 cap on the closing back; no trade under 30 s; no exit at or after the result is known; an offer filled only by a trade THROUGH its price; handicap-line markets dropped; the target, stop and time-limit exits.
- No look-ahead: features up to 15:20 are identical when every later price is changed. A fact received at 15:10 is invisible at 15:10:00 and visible at 15:10:10.
Found and fixed:
- Handicap and points-total markets (basketball, American football, ice hockey) carry many handicap lines under one selection id. This made £244k of fake winners; those markets are now left out. The existing league does not filter them.
- Exits at a race's last quote, which already shows the result, are not allowed.
- Two-runner mirror trades were counted twice; the map now gives both figures.
Could not do:
- 20-21 Nov are not cached yet (the 36-hour rule).
- Offering entries went only into the map, not steps 3-4.
- Other exchanges: Matchbook starts 13 Nov, so it has no first half; Smarkets is not cached.
- Racing draw is known only for 2-9 Nov; expected goals stop 9 Nov.
- Betfair's in-play bet delay is not modelled (fills at the quote of the moment), so the hindsight figures are generous.
Shared edits: onetest.py run() gained two lines dispatching kind 'cond' (backup onetest.py.bak_session7); the S7 section was appended to test_known.py (backups *.bak_session7, *.bak_session7b). Builder session 9 worked in the same files at the same time (grid/SESSION7_NOTE.md). Paper only, no orders, nothing deleted; the paper trader stayed up.
