p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
n = s.count('reports/finder_2026-11-09_items488-489.md')
assert n == 2, n
s = s.replace('reports/finder_2026-11-09_items488-489.md', 'reports/finder_2026-11-09_items488-490.md')
old = "490. RUNNING 2026-11-09 (claimed about 08:50 UTC,"
assert s.count(old) == 1
s = s.replace(old, ("490. DONE 2026-11-09 — nothing passes; FOLLOW ALL 5% n 348,152 on 18,400 games -0.143 per £10, t_game -3.04, h1 -0.127 h2 -0.158; "
"back shorteners -0.260, lay drifters -0.056; won 0.3162 v 0.3184 implied at entry, so the move is fully priced by the next print and item 489's "
"asymmetry was the move itself; FADE control -0.537; late bands T=76/91 -0.012/-0.016; best BTTS lay drift n 4,910 +0.114 t 0.85; 10% reading -0.103; "
"jobs/499_inplay_follow_move.sh, reports/finder_2026-11-09_items488-490.md (claimed about 08:50 UTC,"))
assert '\n491. ' not in s
s = s.rstrip('\n') + '\n' + ("491. TODO (re-check 22 Nov 2026 with items 455, 460, 462, when local liq_sample holds about four weeks of BTTS, OU and MO books from 27 Oct; "
"first count late in-play drifters with a real lay touch in the 3 min after the move; Finder's own, source a, next door of item 490; tables liq_sample "
"(real back/lay touch with sizes), goal_timeline; job 499_late_drift_touch to write from jobs/499_inplay_follow_move.sh) **Lay a late in-play drifter "
"at the real lay touch, not the print plus a tick.** Rationale: on 285,131 unseen tape markets item 490's lay drifters won 0.2456 v 0.2492 implied at "
"the next print, and the late bands T=76/91 lost only -0.012/-0.016 per £10, which is about the one adverse tick charged on prints; BTTS lay drift "
"n 4,910 +0.114 t 0.85; a real lay touch says whether that tick is actually paid. Rule fixed now: liq_sample, BTTS/OU1.5-3.5/MO, decisions at match "
"minute 60 and 75 (goal_timeline minute), drift = last LTP over 3 min at least 5% longer than the LTP before; lay at the first recorded lay touch "
"after the move, no extra tick, £10 liability, 2%, held to the result; one entry per market per decision; bar as standard with t on per-game sums, "
"halves by date.\n")
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
o2 = "follow a 5% in-play move seen over 3 min, entered at the next print, 15 football types (490) | RUNNING | "
assert t.count(o2) == 1
t = t.replace(o2, "follow a 5% in-play move seen over 3 min, entered at the next print, 15 football types (490) | DONE | nothing passes; n 348,152 -0.143 t_game -3.04 both halves negative; won = implied at entry")
t = t.rstrip('\n') + "\n2026-11-09 | a moves (liq_sample, from 490) | lay a late in-play drifter at the real lay touch, minutes 60/75, BTTS/OU/MO (491) | TODO (re-check 22 Nov) | 490 late bands -0.012/-0.016 on prints, the tick is the cost\n"
open(h, 'w').write(t)
print('ok')
