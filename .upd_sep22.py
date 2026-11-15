p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
R='reports/finder_2026-11-09_sep22-rereads.md'
claim=' RUNNING 2026-11-09 02:30 UTC (Soccer 2022-09 read DONE, Sep 2022 re-read, code unchanged) ('
notes={
'445':"(UPDATE 2026-11-09 02:45 UTC: Soccer 2022-09 DONE, Aug 2022 part-loaded; UNSEEN Aug 2022-Feb 2023 MO ONE lay n 1,181 +0.222 t 0.81 h1 +0.045 h2 +0.398, shrinking again (+0.511 on 690, +0.365 on 971); MO FAV lay n 594 +0.398 t 0.81 h1 -0.355 h2 +1.150, one half now negative; OU25 OVER lay n 430 -0.302 t -0.57; a greened 10-15 min exit on the same signal loses (item 479); re-check when Aug 2022 reads DONE; jobs/499_jump_down_lay.sh unchanged, "+R+") (",
'448':"(UPDATE 2026-11-09 02:45 UTC: Sep 2022 N1 G2 NOT_LEVEL lay U n 25 +0.244 t 0.31 h1 +0.596 h2 -0.034, Under won 0.120 v 0.150 implied; pooled Sep-Feb n 74 about +0.72, interim; jobs/499_sep22_rereads.sh, "+R+") (",
'450':"(UPDATE 2026-11-09 02:45 UTC: Sep 2022 ONE FAV back n 37 +0.314 t 0.30 h1 +0.144 h2 +0.495, won 0.650 of non-draws v 0.617 implied; pooled Sep-Feb n 131 about +0.26, interim; jobs/499_sep22_rereads.sh, "+R+") (",
'465':"(UPDATE 2026-11-09 02:45 UTC: Sep 2022 SH4 back HOLD one a game n 4 +4.334 (2 of 4 won); pooled Sep-Oct 2022 n 8 about +3.09; jobs/499_sep22_rereads.sh, "+R+") (",
}
for it,nt in notes.items():
    old='\n'+it+'.'+claim
    assert s.count(old)==1, it
    s=s.replace(old,'\n'+it+'. TODO '+nt,1)
old479='\n479. RUNNING 2026-11-09 02:50 UTC ('
assert s.count(old479)==1
s=s.replace(old479,"\n479. DONE 2026-11-09 — nothing passes: MO ONE green n 3,127 -0.167 t -2.30 h1 -0.122 h2 -0.212, MO FAV green n 1,469 -0.242 t -1.87; before Mar 2023 ONE n 1,181 -0.089; exited trades only n 2,553 -0.236 t -5.52 v the FLAT control's round trip -0.265 n 30,250 (91.5% exited), so the shortened runner gives back only about 0.03 per £10 more in 10-15 min, far less than two crossings cost; DRAW green n 642 +0.015 v FLAT DRAW -0.156, read only, taken to item 480; jobs/499_dn24_green_exit.sh, "+R+" (claimed 02:25 UTC; ",1)
assert '\n480. ' not in s
s=s.rstrip('\n')+'\n'+("480. TODO (re-check 22 Nov 2026 with items 455, 460, 462, when local liq_sample holds about four weeks of MO books from 27 Oct; first count games whose Draw's first in-play touch sits 2-4 points under its last pre-off touch; Finder's own, source c, next door of items 445 and 479; table liq_sample (MATCH_ODDS, real touch with sizes); job 499_dn24_draw_rest to write from jobs/499_dn24_green_exit.sh) "
"**Lay a Draw that shortened 2-4 points at the off at the real lay touch, and get out with a resting back one tick above the back touch within 10-15 min.** "
"Rationale: item 479 on prints, DRAW green n 642 +0.015 against the FLAT Draw control -0.156 n 19,447, so a Draw that comes in at the off gives back about 0.17 per £10 more than a quiet one in 10-15 min, but a taker pays two crossings; a resting exit saves one. Read only on tonight's months, so in-sample, never scored. "
"Rule fixed now: DN24 on the Draw from touches (mid of back and lay), lay at the lay touch one tick adverse, £10 liability; rest a back one tick above the back touch, filled only when a later snapshot's lay touch is at or under it; unfilled by 15 min, cross at the back touch; a goal before the fill is crossed at the first touch after it, never dropped; 2%; one a game; standard bar, halves by date median; FLAT control the same.\n")
open(p,'w').write(s)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
old="| lay the MO runner that shortened 2-4 points at the off, green out 10-15 min later (499_dn24_green_exit, item 479) | RUNNING | 445 to result n 971 +0.365 t 1.21, FAV n 488 +0.817\n"
assert t.count(old)==1
t=t.replace(old,"| lay the MO runner that shortened 2-4 points at the off, green out 10-15 min later (499_dn24_green_exit, item 479) | DONE | nothing passes; ONE n 3,127 -0.167 t -2.30; FLAT control -0.265; drifts back less than two crossings\n")
t=t.rstrip('\n')+'\n'+"2026-11-09 | c structural (liq_sample, from 479) | lay a Draw that shortened 2-4 points at the off at the real touch, out by a resting back within 10-15 min (item 480) | TODO (re-check 22 Nov) | 479 DRAW green n 642 +0.015 v FLAT Draw -0.156, in-sample\n"
open(h,'w').write(t)
print('ok')
