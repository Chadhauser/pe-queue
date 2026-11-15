Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
item = ("447. RUNNING 2026-11-08 (Finder's own, source c thin books, from item 446's drop counts; tables bf_hist_other, bf_hist_result; job 499_ht_state_thin) "
"**Item 446 on the games it could not read: half-time timed from the first in-play print, not the half-time markets.** Rationale: item 446 dropped 32,823 of 68,824 games "
"as 'half-time not clear', where the HALF_TIME and first-half goal markets stop printing before 46 min; these are the thin books item 446 never priced. "
"The first in-play print cannot come before the kick-off, so the first half is over by 55 min after it bar extreme stoppage. Rule fixed now, before any price: "
"item 446 unchanged except the entry window, first print of the line 55 to 62 min after the first in-play print, and one more guard, the Over (G+0.5) must NOT have printed at 1.05 or under before entry "
"(no second-half goal yet). Scored on the games item 446 dropped as half-time not clear only (UNSEEN); the same rule on all games printed as an audit, not scored. "
"Lines, bands, fills, settlement, bar as item 446.\n")
s = open(Q).read()
assert '\n447.' not in s
s = s.replace("446. RUNNING 2026-11-08 (Finder's own", "446. DONE 2026-11-08 — nothing passes, 0 of 82 lines; trades 9,338 on 5,387 games; Under won within 1-4 points of implied at every G; best n>=300 N2 G2 back U HIGH n 393 +0.561 t 0.91 h1 -0.389; jobs/499_ht_state_lines.sh, reports/finder_2026-11-08_items446-447.md (Finder's own", 1)
open(Q, 'w').write(s + item)
h = open(H).read()
h = h.replace("OU4.5 included (499_ht_state_lines, item 446) | RUNNING | -", "OU4.5 included (499_ht_state_lines, item 446) | DONE | nothing passes; 0 of 82; n 9,338, Under won v implied within 1-4 points; best N2 G2 back U HIGH n 393 +0.561 t 0.91")
h += "2026-11-08 | c thin books (bf_hist_other, bf_hist_result, from 446) | item 446 on the games its half-time markets could not time, window from the first in-play print (499_ht_state_thin, item 447) | RUNNING | -\n"
open(H, 'w').write(h)
print('ok')
