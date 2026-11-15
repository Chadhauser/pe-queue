p='watchman/FINDER_QUEUE.md'
s=open(p).read()
old='472. RUNNING 2026-11-09 (Finder lane default/top, 01:45 UTC: .diag472c.py trade-level check) (RESULT 2026-11-08'
assert s.count(old)==1
new=('472. DONE 2026-11-09 — artefact, nothing passes; trade-level check on Oct 2022-Dec 2023 (57 of the 87 GAP2 trades): 40 of 57 entries are the LAST print on both '
     'BTTS and OU1.5 (both markets closed at entry, the equaliser suspending them), won 0.950 v 0.558 implied, not fillable; the 17 where OU1.5 kept trading 10+ min '
     'n 17 +2.287 won 0.529 v 0.463, too small; real-touch door is item 478; jobs/499_btts_bound_diag.sh, reports/finder_2026-11-09_item472.md '
     '(RESULT 2026-11-08')
s=s.replace(old,new)
item=('\n478. TODO (re-check 22 Nov 2026, when local liq_sample holds about four weeks of BTTS books; local copy now 31 Oct-8 Nov 15:03, 1,880 BTTS markets, '
      'a row about every 75 s; Finder\'s own, source c structural, real-touch door of item 472 after its print read was an artefact of markets closing at a goal; '
      'tables liq_sample (mkt BTTS and MO, real touch with sizes), goal_timeline; job 499_btts_bound_touch to write from jobs/499_btts_bound_diag.sh and jobs/499_xx_rest.sh) '
      '**Back BTTS Yes at 1-0 or 0-1 when the real BTTS Yes back price breaks the MO bound, book open on both sides.** Rationale: P(Yes) >= P(Draw) + P(trailer wins) '
      'exactly at one goal; item 472\'s break at prints was the final print before a suspension, so only a book with a back and a lay on it, after the goal, can say '
      'whether the bound breaks at all. Rule fixed now, before any BTTS touch is read: score from goal_timeline (one goal, minute 20-80, at least 3 min after it); '
      'MO Draw and trailer implied from the lay touch (the conservative side) in the same liq_sample snapshot; GAP = that sum - 1/(BTTS Yes back touch); '
      'GAP2 (GAP >= 0.02, back size >= GBP 10, spread <= 4 ticks) back Yes at the back touch with one tick adverse, GBP 10, 2% on profit, held to the result '
      '(goal_timeline final, never dropped); replays dropped (total_matched falling); a later snapshot of the same market must show a book, else the trade is void '
      'and counted; one entry per game; first count how many games ever show GAP2 at the touch; standard bar, halves by date median.\n')
s=s.rstrip('\n')+'\n'+item.lstrip('\n')
open(p,'w').write(s)
h='watchman/HYPOTHESES.md'
t=open(h).read()
o2='| back BTTS Yes at 1-0 when its print implies less than MO Draw + MO trailer, an exact bound (499_btts_bound, item 472) | TODO (check artefact 9 Nov) | GAP2 back n 87 +5.835 t 5.37, won 0.816 v 0.540, likely a goal artefact, unverified'
assert t.count(o2)==1
t=t.replace(o2,'| back BTTS Yes at 1-0 when its print implies less than MO Draw + MO trailer, an exact bound (499_btts_bound, item 472) | DONE 9 Nov, artefact | 40 of 57 GAP2 entries were the final print on BTTS and OU1.5 (closed at a goal), won 0.950; live books n 17 +2.287 (499_btts_bound_diag)')
t=t.rstrip('\n')+'\n2026-11-09 | c structural (liq_sample, from 472) | back BTTS Yes at 1-0 when the real back touch breaks the MO Draw + trailer bound, book open (item 478) | TODO (re-check 22 Nov) | 472 print read was closed-market artefact; liq_sample BTTS 1,880 games 31 Oct-8 Nov\n'
open(h,'w').write(t)
print('ok')
