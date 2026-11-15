r='reports/finder_2026-11-08_item439.md'
s=open(r).read()
anchor='## Item 70, loader progress'
sec='''## Items 441 and 442, the next doors
441 BLOCKED: its first step failed its own bar. bf_hist_result holds CS winners for Aug 2024 only within Sep 2024 to Apr 2025 (2,853 markets; Sep to Apr 0 of 49,737).
442, item 439's rule unchanged on Mar 2023 to Aug 2024, settled to Betfair's official winner (jobs/499_cs_longshot_minor.sh, 359 s). 39,262 markets scored, 33,342 games: MINOR (no af/fd result) 20,791, MAJOR 12,551; 62 markets had no official winner. Check: the official winner equals the af/fd score on 12,898 of 12,905 MAJOR games (0.9995). Winning runners per game-window among traded: never above 1.

| grp | var | win | band | side | n | per £10 | t | h1 | h2 | won | implied |
|---|---|---|---|---|---|---|---|---|---|---|---|
| MINOR | ONE | W80 | 10-20 | L | 4,782 | +0.045 | 1.19 | +0.049 | +0.041 | 0.063 | 0.069 |
| MINOR | ALL | W80 | 10-20 | L | 5,933 | +0.027 | 0.79 (t_game 1.38) | +0.031 | +0.023 | 0.065 | 0.069 |
| MINOR | ONE | W20 | 20-50 | B | 10,588 | +0.385 | 0.73 | +0.407 | +0.363 | 0.037 | 0.035 |
| MINOR | ONE | W20 | 50-200 | B | 7,309 | +0.763 | 0.70 | -0.050 | +1.573 | 0.015 | 0.013 |
| MAJOR | ALL | W55 | 50-200 | L | 13,093 | +0.005 | 0.61 | +0.005 | +0.005 | 0.010 | 0.011 |
| BOTH | ALL | W20 | 10-20 | L | 61,782 | -0.078 | -6.70 | -0.100 | -0.056 | 0.078 | 0.072 |
| BOTH | ALL | W80 | 20-50 | B | 17,360 | -1.789 | -4.92 | -1.744 | -1.833 | 0.030 | 0.037 |

Survivors: none, 0 of 108. Verdict for the family: the long in-play CS lines are priced fair on both sets of months and in minor leagues as in major ones. The best line is +0.045 per £10 at t 1.19. At W20 the 10-20 lines win slightly more often than the lay price implies, so laying them early loses (BOTH ALL -0.078, t -6.70). Two doors read, both flat; one blocked on data. The third door is item 443, a resting lay inside the real CS touch, the only version a taker's spread does not already decide.

'''
assert s.count(anchor)==1; s=s.replace(anchor,sec+anchor)
s=s.replace("Untracked scratch files: .kw439.py, .c439.py, .c439b.py, .claim_439.py, .add_440.py, .upd70_439.py, .fin439.py.",
 "jobs/499_cs_longshot_minor.sh (item 442). Untracked scratch files: .kw439.py, .c439.py, .c439b.py, .claim_439.py, .add_440.py, .upd70_439.py, .fin439.py, .fix439.py, .fix439b.py, .c441.py, .claim_442.py, .tail442.py, .fin442.py.")
open(r,'w').write(s)
q='watchman/FINDER_QUEUE.md'; t=open(q).read()
old='442. RUNNING 2026-11-08 ('
assert t.count(old)==1
t=t.replace(old,("442. DONE 2026-11-08 — nothing passes, 0 of 108; 33,342 games Mar 2023 to Aug 2024 (MINOR 20,791, MAJOR 12,551), official winner v af/fd 0.9995; "
"best MINOR ONE W80 10-20 lay n 4,782 +0.045 t 1.19 h1 +0.049 h2 +0.041; W20 10-20 lay BOTH n 61,782 -0.078 t -6.70; minor leagues price the long lines as fairly as major; "
"jobs/499_cs_longshot_minor.sh, reports/finder_2026-11-08_item439.md — ("))
assert '\n443. ' not in t
line=("443. TODO (re-check 22 Nov 2026, when local liq_sample holds about four weeks of CS books from 27 Oct; Finder's own, source c, third door of the in-play CS family after "
"items 439, 442 (441 blocked); tables liq_sample (CORRECT_SCORE, real touch with sizes), goal_timeline; job 499_cs_rest_touch to write from jobs/499_cs_longshot_ip.sh and "
"jobs/499_xx_rest.sh) **Rest a lay one tick inside the real Correct Score touch on the long lines in running.** Rationale: items 439 and 442 found the long in-play CS lines "
"priced fair at the print, lay won 0.010-0.078 against 0.010-0.072 implied, so a taker pays the spread for nothing; the one version not yet read is a maker who earns it. "
"Rule fixed now, before any book is read: football CS in play, item 439's windows W20, W55, W80 by clock from the off; runners whose best lay is 10-200 with a back-lay spread "
"of 3 ticks or more; post a lay one tick under the best lay, filled only if a later snapshot within 120 s shows the best back at or above the posted price (touch through), "
"never on the posting snapshot; held to the final score from goal_timeline, so nothing drops; 2% on profit, GBP 10 liability; one entry per game per window; "
"halves by date; standard bar; report fills per post and the unfilled share.\n")
k=t.index('\n442. '); j=t.index('\n',k+1)
t=t[:j+1]+line+t[j+1:]
open(q,'w').write(t)
h='watchman/HYPOTHESES.md'; u=open(h).read()
o="| item 439's long-shot CS lay on the 38,438 markets af/fd do not hold, settled on Betfair's result (item 441) | TODO | -\n"
assert u.count(o)==1
u=u.replace(o,"| item 439's long-shot CS lay on the 38,438 markets af/fd do not hold, settled on Betfair's result (item 441) | BLOCKED | bf_hist_result has CS winners on Aug 2024 only in that window\n")
u+=("2026-11-08 | c lower leagues (bf_hist_other, bf_hist_result, from 439, 441) | item 439 on Mar 2023 to Aug 2024, official winner, MINOR v MAJOR (499_cs_longshot_minor, item 442) | DONE | nothing passes; 0 of 108; best MINOR ONE W80 10-20 lay n 4,782 +0.045 t 1.19\n"
"2026-11-08 | c (liq_sample, goal_timeline, from 439, 442) | rest a lay one tick inside the real CS touch on long lines in running (item 443) | TODO (re-check 22 Nov) | -\n")
open(h,'w').write(u); print('ok')
