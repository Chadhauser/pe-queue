p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
R='reports/finder_2026-11-08_item456.md'
def sub(a,b):
    global s
    assert s.count(a)==1, a
    s=s.replace(a,b)
sub("456. RUNNING 2026-11-08 (lane A, 13:40 UTC run)",
    "456. DONE 2026-11-08 — nothing passes; 0 of 30, every line negative in both halves and every year; 59,978 games, 405,306 trades; best W24 8-20 lay n 1,254 -0.055 t -5.04 h1 -0.063 h2 -0.044; median runner ends at the same print, 8-20 runners drift out +10.3% from 24 h; next door item 457; jobs/499_mo_premarket_drift.sh, "+R+" (lane A, 13:40 UTC run)")
sub("451. TODO (", "451. TODO (UPDATE 2026-11-08 14:10 UTC: Dec 2022 UNSEEN FAV E1 n 77 -0.626 t -0.50 h1 +0.739 h2 -2.027; pooled Dec-Jan n 169 about -0.18, weakening; ONE E1 n 194 -1.038; Nov 2022 still loading; jobs/499_dec22_rereads.sh, "+R+") (")
sub("448. TODO (", "448. TODO (UPDATE 2026-11-08 14:10 UTC: Dec 2022 N1 G2 NOT_LEVEL lay U n 3 +2.192; pooled Dec-Feb n 17 about +1.10, interim; jobs/499_dec22_rereads.sh, "+R+") (")
sub("450. TODO (", "450. TODO (UPDATE 2026-11-08 14:10 UTC: Dec 2022 ONE FAV back n 6 +2.744, all won; pooled Dec-Feb n 35 about +0.42, interim; jobs/499_dec22_rereads.sh, "+R+") (")
assert '\n457. ' not in s and s.rstrip().splitlines()[-1].startswith('456. ')
s=s.rstrip('\n')+'\n'+("457. TODO (re-check 22 Nov 2026 with item 455: first count whether local liq_sample or stream_ticks holds MATCH_ODDS touches 6 h and 24 h before kick-off, as the recorders may only start near the off; Finder's own, source a, second door of the pre-match swing family after item 456; "
"tables liq_sample, stream_ticks; job 499_mo_longshot_rest to write from jobs/499_mo_premarket_drift.sh) **Rest a lay on an 8-20 MO runner hours before kick-off, out at the last pre-off touch.** "
"Rationale: item 456 found 8-20 runners drift out +10.3% from 24 h and +4.9% from 6 h on average, and the taker lay lost only -0.055 per GBP 10 at W24 (n 1,254, h1 -0.063 h2 -0.044) after two ticks; resting saves the entry tick. "
"Rule: at KO-24 h and KO-6 h, offer a lay at the current back touch on every MO runner priced 8-20, filled only if a later print trades through within 60 min; out by backing at the last pre-off back touch, one tick adverse there, GBP 10 liability, 2% on profit; unfilled offers counted; halves by date.\n")
open(p,'w').write(s)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
a="(499_mo_premarket_drift, item 456) | RUNNING | -"
assert t.count(a)==1
t=t.replace(a,"(499_mo_premarket_drift, item 456) | DONE | nothing passes; 0 of 30; best W24 8-20 lay n 1,254 -0.055 t -5.04; median runner ends at the same print; 8-20 drift +10.3% from 24 h")
t=t.rstrip('\n')+'\n'+("2026-11-08 | re-reads (bf_hist_other, bf_hist_result, items 448, 450, 451) | Dec 2022, a month no read had used (499_dec22_rereads) | DONE, interim | nothing passes; 451 FAV E1 n 77 -0.626, pooled n 169 about -0.18; 448 n 3 +2.192; 450 n 6 +2.744; all stay TODO\n"
"2026-11-08 | a (liq_sample, stream_ticks, from 456) | rest a lay on 8-20 MO runners 24 h and 6 h out, filled on a trade-through, out at the last pre-off touch | TODO (item 457, re-check 22 Nov) | item 456 taker lay W24 8-20 n 1,254 -0.055, drift +10.3%\n")
open(h,'w').write(t)
print('ok')
