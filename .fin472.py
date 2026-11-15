r = '/root/pe-queue/reports/finder_2026-11-08_oct22-rereads.md'
s = open(r).read()
sec = """## Item 472 (new, Finder's own): back BTTS Yes at 1-0 when its print implies less than MO Draw + MO trailer
68,629 games with MO and BTTS in play, Oct 2022 to Oct 2026 as loaded; 10,925 read (18,570 dropped as scorer unclear, 13,281 for no MO print around the goal). One trade per game per class.
| line | n | per £10 | t | h1 | h2 | won | implied |
|---|---|---|---|---|---|---|---|
| GAP2 back Yes * | 87 | +5.835 | 5.37 | +6.167 | +5.496 | 0.816 | 0.540 |
| GAP2 lay Yes (mirror) | 87 | -6.389 | -7.53 | -6.747 | -6.022 | | |
| GAP2 back, min 46-80 | 61 | +6.843 | 4.99 | +7.106 | +6.572 | 0.820 | 0.522 |
| CTRL (GAP 0-0.02) back | 4 | +0.488 | 0.08 | | | | |
Median GAP 0.172, 90th percentile 0.512. By year: 2022 +6.57 (17), 2023 +5.67 (40), 2024 +6.84 (24), 2026 +0.86 (6).
Fixes: the first run found almost no OU0.5 print at 1.05 or under (the market closes at the goal), so the goal detector was fixed once before any price was scored. A MemoryError on the Sep 2026 chunk was fixed once with 5-day chunks.
UNVERIFIED, and most likely an artefact. A real bound break would be a few points, not a median of 17. The OU1.5 market also closes at a goal without printing 1.10, so the second-goal guard cannot see an equaliser. A BTTS Yes print matched as the equaliser goes in would win about 0.8 of the time, which is the "entry just after a goal" trap (false t 3.52 before). The trade-level check (.diag472c.py: does OU1.5 keep printing after entry, and when is the next BTTS print) was killed at its 25-min timeout before printing anything."""
v = ("Nothing passes. 0 of 1 scored lines on item 472 (n 87 is under 300, and the line is not trusted); 451 closes with nothing passing; 445, 448, 450 and 465 are interim reads and stay TODO.\n"
     "- Item 472 next door (next run, 9 Nov): run .diag472c.py with timeout 3000. If the GAP2 wins are trades where OU1.5 stops printing within about 2 min of entry, the line is a goal artefact and is closed. "
     "If OU1.5 keeps trading for 10+ min after entry and the edge holds, it becomes a liq_sample real-touch test.")
s = s.replace('ITEM472', sec).replace('VERDICT472', v)
open(r, 'w').write(s)
q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(q).read()
a = "472. RUNNING 2026-11-08 22:45 UTC (lane A, jobs/499_btts_bound.sh; "
assert t.count(a) == 1
t = t.replace(a, "472. TODO (RESULT 2026-11-08, UNVERIFIED, likely artefact: GAP2 back Yes n 87 +5.835 t 5.37 h1 +6.167 h2 +5.496, won 0.816 v 0.540 implied, median GAP 0.172, under n; "
              "OU1.5 closes at a goal without printing 1.10, so the guard cannot see an equaliser, and a print matched as the equaliser goes in would look like this; "
              "next run: .diag472c.py (OU1.5 printing after entry, next BTTS print) with timeout 3000, killed at 1500 s tonight; goal detector and chunk size fixed once each; "
              "reports/finder_2026-11-08_oct22-rereads.md) (from 9 Nov; jobs/499_btts_bound.sh; ")
open(q, 'w').write(t)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
x = open(h).read()
b = "(499_btts_bound, item 472) | TODO (from 9 Nov) | Mar 2023 week: BTTS in-play prints on 773 markets, about 14 each, thin"
assert x.count(b) == 1
x = x.replace(b, "(499_btts_bound, item 472) | TODO (check artefact 9 Nov) | GAP2 back n 87 +5.835 t 5.37, won 0.816 v 0.540, likely a goal artefact, unverified")
x = x.rstrip('\n') + "\n2026-11-08 | a moves (bf_hist_other, from 414, 422) | item 451 jump-up favourite back on unseen months | DONE | nothing passes; pooled unseen Oct 2022-Jan 2023 n 334 about +0.11\n"
open(h, 'w').write(x)
print('ok', len(s.split('\n')), 'report lines')
