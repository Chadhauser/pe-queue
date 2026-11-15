p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
R='reports/finder_2026-11-08_nov22-rereads.md'
old445='\n445. RUNNING 2026-11-08 16:05 UTC (Nov 2022 read DONE, re-run unchanged) ('
assert s.count(old445)==1
s=s.replace(old445,'\n445. TODO (UPDATE 2026-11-08 16:20 UTC: Soccer 2022-11 DONE, UNSEEN now Oct 2022 (5 edge games) to Feb 2023, MO ONE lay n 690 +0.511 t 1.43 h1 +0.835 h2 +0.188, n clears 300 but t does not; MO FAV lay n 351 +0.994 t 1.58; MO ONE D5 lay n 560 +0.836 t 1.56; OU25 OVER lay n 212 +0.656 t 0.86; audit Mar 2023-Sep 2026 MO ONE n 1,946 +0.076, so the unseen lean is not on the months after; re-run as Oct 2022 and older months load; jobs/499_jump_down_lay.sh unchanged, '+R+') (',1)
U={
'448':'(UPDATE 2026-11-08 16:15 UTC: Nov 2022 N1 G2 NOT_LEVEL lay U n 13 +0.796 t 0.88 h1 +1.658 h2 -0.584; pooled Nov-Feb n 30 about +0.97, interim; jobs/499_nov22_rereads.sh, '+R+') ',
'450':'(UPDATE 2026-11-08 16:15 UTC: Nov 2022 ONE FAV back n 22 +1.412 t 1.70 h1 +2.254 h2 +0.570, won 0.909 of non-draws v 0.737 implied; pooled Nov-Feb n 57 about +0.80, interim; jobs/499_nov22_rereads.sh, '+R+') ',
'451':'(UPDATE 2026-11-08 16:15 UTC: Nov 2022 UNSEEN FAV E1 n 70 +0.904 t 0.73 h1 +2.401 h2 -0.593, won 0.557 v 0.513; pooled Nov-Jan n 239 about +0.14; ONE E1 n 159 +0.162; Oct 2022 and older not loaded; jobs/499_nov22_rereads.sh, '+R+') ',
}
for k,v in U.items():
    o='\n'+k+'. TODO ('
    assert s.count(o)==1,k
    s=s.replace(o,'\n'+k+'. TODO '+v+'(',1)
open(p,'w').write(s); print('ok')
