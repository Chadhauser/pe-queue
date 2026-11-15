p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n391. ' not in s and '\n392. ' not in s
if not s.endswith('\n'): s += '\n'
s += ("391. RUNNING 2026-11-07 — (Finder's own, source a; table finder_tlog; job 499_touch_log_tennis2; from item 129, whose prints I have seen: median spread at the trigger was 18%, so most triggers were thin books, and a pass here still needs unseen games) "
      "**A tennis pre-off shock on a tight book, follow or fade, crossing.** Rule fixed now: item 129's trigger at X5 and X10, first per market, only where the book at the trigger row has lay/back - 1 <= 3%; enter at the next row within 120 s at the real touch, one tick adverse; out at the first touch 600 s on, or the last pre-off touch if the off comes first, one tick adverse. Four lines, X5 and X10, fade and follow. Standard bar, one per market.\n")
s += ("392. RUNNING 2026-11-07 — (Finder's own, source a; tables finder_rlog, finder_rresults; job 499_touch_log_inplay; a cross-check of item 380, it does not replace item 382, whose rule stands) "
      "**Item 380's first touch of 1.1 and 1.2, 30 s rows, races it never saw.** Rationale: item 380 read 166 races, 2 to 6 Nov; the log has about 2,000 races before those. Rule fixed now, before any price: first in-play row with back > Q, then the first later in-play row with back <= Q and a lay within 5% of that back, as item 385's real-book guard. NEXT, scored: back at the next row's back within 120 s, one tick adverse, to result; no next row, no trade, counted; a fill by then is 30 s late, far from item 380's 1 s, so a miss here does not refute it. SAME, not graded: back at the signal row's own back, one tick adverse, an upper read of win rate against price. Result finder_rresults, one winner only. Q 1.1 and 1.2 scored, 1.5 and 2.0 context. UNSEEN = off before 2 Nov 00:00 UTC is what is scored; 2 to 6 Nov printed apart. Standard bar, t by race.\n")
open(p, 'w').write(s)
j = '/root/pe-queue/jobs/499_touch_log_racing.sh.wip'
t = open(j).read()
a = "fr = h.filled.mean() if kd == 'RESTED' else np.nan"
assert t.count(a) == 1
open(j, 'w').write(t.replace(a, "fr = h.filled.astype(bool).mean() if kd == 'RESTED' else np.nan"))
print('ok')
