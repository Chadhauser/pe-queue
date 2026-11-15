p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
R = 'reports/finder_2026-11-09_aug22-item481.md'
claim = ' RUNNING 2026-11-09 04:05 UTC (Aug 2022 re-read once Soccer 2022-08 reads DONE, code unchanged) ('
notes = {
 '448': "(UPDATE 2026-11-09 05:00 UTC: Aug 2022 N1 G2 NOT_LEVEL lay U n 14 -0.953 t -0.73 h1 -1.229 h2 -0.842; pooled Aug-Feb n 88 about +0.45, interim; Aug 2022 is the oldest month on the box, re-check as older months load; jobs/499_aug22_rereads.sh, " + R + ") (",
 '450': "(UPDATE 2026-11-09 05:00 UTC: Aug 2022 ONE FAV back n 40 -0.439 t -0.67 h1 -0.711 h2 -0.167; pooled Aug-Feb n 171 about +0.10, now under the +0.15 bar; re-check as months older than Aug 2022 load; jobs/499_aug22_rereads.sh, " + R + ") (",
 '465': "(UPDATE 2026-11-09 05:00 UTC: Aug 2022 SH4 back HOLD one a game n 5 -4.452; pooled Aug-Oct 2022 n 13 about +0.19; re-check as months older than Aug 2022 load; jobs/499_aug22_rereads.sh, " + R + ") (",
}
for it, nt in notes.items():
    old = '\n' + it + '.' + claim
    assert s.count(old) == 1, it
    s = s.replace(old, '\n' + it + '. TODO ' + nt, 1)
old = '\n445.' + claim
assert s.count(old) == 1
s = s.replace(old, "\n445. DONE 2026-11-09 — nothing passes: with Soccer 2022-08 DONE, UNSEEN Aug 2022-Feb 2023 MO ONE lay n 1,262 +0.159 t 0.60 h1 -0.218 h2 +0.536, one half negative, which was the closure rule written at 02:45 UTC; shrank on four reads (+0.511, +0.365, +0.222, +0.159); MO FAV lay n 630 +0.276 t 0.58 h1 -0.506; OU25 OVER lay n 461 -0.322; door is item 480; jobs/499_jump_down_lay.sh unchanged, " + R + " (", 1)
old = '\n481. RUNNING 2026-11-09 04:30 UTC ('
assert s.count(old) == 1
s = s.replace(old, "\n481. DONE 2026-11-09 — nothing passes: LAY_RICH gap>=1 n 809 -0.025 t -0.22 h1 +0.049 h2 -0.100, BACK_CHEAP gap>=1 n 614 -0.789 t -0.54; 21,453 games, median gap 0.25 points, lay control -0.031, so the two books agree within a quarter point; LAY_RICH gap>=2 n 118 +0.480 t 1.63 both halves positive, read only, taken to item 483; jobs/499_cs00_u05_preoff.sh, " + R + " (", 1)
assert '\n483. ' not in s
s = s.rstrip('\n') + '\n' + (
 "483. TODO (re-check 22 Nov 2026 with items 443 and 455, when local liq_sample holds about four weeks of CORRECT_SCORE and OU05 books from 27 Oct; first count games with both books touched within 60 s of each other before the off and at 0-0 in play; Finder's own, source c structural, next door of item 481; table liq_sample (real touch with sizes); job 499_cs00_u05_touch to write from jobs/499_cs00_u05_preoff.sh) "
 "**Lay CS 0-0 or Under 0.5 when its lay touch implies 2+ points more than the other book's back touch.** "
 "Rationale: on prints (item 481) the two books agree within 0.25 points at the median and laying either at its last pre-off print is near fair (-0.031 n 21,453), but when the later print is dearer by 2+ points the lay reads n 118 +0.480 t 1.63, both halves positive; at about 4 a month on prints that cannot reach n 300, but the touch is quoted every snapshot, pre-off and in play, so the gap may be seen far more often. "
 "Rule fixed now: at each snapshot, gap = 100*(1/lay_touch_A - 1/back_touch_B) for A, B in {CS 0-0, Under 0.5}; when gap >= 2, lay A at its lay touch one tick adverse, £10 liability, held to the official result, never dropped; first qualifying snapshot only, one bet a game per state (pre-off, in play at 0-0); 2%; standard bar, halves by date median; control: lay A at the first snapshot with gap under 0.5.\n")
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old = "| CS 0-0 v Under 0.5 before the off, trade the later print: lay if dearer, back if cheaper (499_cs00_u05_preoff, item 481) | RUNNING | -\n"
assert t.count(old) == 1
t = t.replace(old, "| CS 0-0 v Under 0.5 before the off, trade the later print: lay if dearer, back if cheaper (499_cs00_u05_preoff, item 481) | DONE | nothing passes; LAY_RICH n 809 -0.025, BACK_CHEAP n 614 -0.789; gap>=2 lay n 118 +0.480 t 1.63 (483)\n")
t = t.rstrip('\n') + '\n' + "2026-11-09 | c structural (liq_sample, from 481) | lay CS 0-0 or Under 0.5 when its lay touch implies 2+ points over the other book's back touch, pre-off and at 0-0 in play (item 483) | TODO (re-check 22 Nov) | 481 gap>=2 lay n 118 +0.480 t 1.63 on prints\n"
open(h, 'w').write(t)
print('ok')
