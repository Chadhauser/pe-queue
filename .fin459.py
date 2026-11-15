p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "459. RUNNING 2026-11-08 (lane A, 14:25 UTC) "
assert s.count(old) == 1
s = s.replace(old, "459. DONE 2026-11-08 — nothing passes; 0 of 40; 48,030 trades on 13,029 games, Nov 2022-Sep 2026; best OU25 LEVEL UNDER lay n 1,185 -0.104 t -10.61; median move 0 in all 20 cells, but one-way drift at 0-0 (Draw longer 0.43 v shorter 0.35, Under 0.40 v 0.30, Home shorter 0.45 v 0.33), under two ticks; resting door filed as item 460; jobs/499_ht_break_drift.sh, reports/finder_2026-11-08_item459.md ")
assert '\n460. ' not in s
s += ("460. TODO (re-check 22 Nov 2026, when local liq_sample holds about four weeks of half-times from 27 Oct; first count 0-0 half-times with a real touch on MO and OU2.5 "
"in the 12 min after the whistle; Finder's own, source c, second door of the half-time-break family after item 459; table liq_sample; job 499_ht_break_rest to write from "
"jobs/499_ht_break_drift.sh) **Rest a back on the 0-0 Draw and Under 2.5 at the half-time whistle, filled on a trade-through, out before the restart.** Rationale: item 459 "
"found prints barely move in the break (median 0), but at 0-0 the Draw drifts out more often than in (0.43 v 0.35, n 3,284) and Under 2.5 likewise (0.40 v 0.30, n 2,961); "
"the taker loses two ticks (Draw back -0.276, Under back -0.197 per GBP 10), so the drift is only reachable by resting. Rule: at the first touch 1-4 min after half-time, "
"rest a back at best back + 1 tick on the Draw and on Under 2.5, filled only if a later print trades above it within 8 min; out by laying at the last lay touch "
"no later than half-time + 12 min, one tick adverse there; unfilled offers counted at 0; GBP 10 stake, 2%; halves by date; standard bar. Home-side lay (shortens 0.45 v 0.33) as a third line.\n")
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old = "(499_ht_break_drift, item 459) | RUNNING | -"
assert t.count(old) == 1
t = t.replace(old, "(499_ht_break_drift, item 459) | DONE | nothing passes; 0 of 40; 48,030 trades; best OU25 LEVEL UNDER lay n 1,185 -0.104 t -10.61; median move 0, one-way drift at 0-0 under two ticks")
t += "2026-11-08 | c structural (liq_sample, from 459) | rest a back one tick above the touch on the 0-0 Draw and Under 2.5 at the whistle, out before the restart | TODO (item 460, re-check 22 Nov) | item 459 Draw longer 0.43 v 0.35, Under 0.40 v 0.30\n"
open(h, 'w').write(t)
print('ok')
