p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
assert '\n445. ' not in t
item = ("445. TODO (re-check 12 Nov 2026, when Soccer 2023-02 reads DONE, then each older month as the loader adds it; Finder's own, source a, from items 414 and 444's controls; tables bf_hist_other, bf_hist_result; job 499_jump_down_lay to write from jobs/499_jump_up_ou25.sh and jobs/499_jump_up_delay.sh) "
        "**Lay a runner whose first in-play print sits 2-4 implied points UNDER its last pre-off print (shortened at the off), MO and OU25, on months no read has used.** "
        "Rationale: the DOWN 2-4 back has been negative wherever it has been printed as a control: item 444 OU25 DOWN 2-4 back OVER n 631 -0.718 t -2.06 (h1 -0.766, h2 -0.666), all OU25 n 1,419 -0.401 t -1.49; MO April 2023 DOWN 2-4 D5 n 161 -1.573, D10 n 157 -2.342 (jobs/499_apr23_rereads.sh). "
        "Never tested as a lay, and every read so far was a control on months chosen for the UP signal, so only months before Mar 2023 count. "
        "Rule fixed now: item 414/444 code with the state DN24 (gap -4 < g <= -2 points); lay at the worse of the first in-play print and the next within 120 s (the higher), one tick adverse, GBP 10 liability, 2%, prices over 50 not traded, one bet a game per market (the larger gap), official bf_hist_result winner, never dropped, women and youth out. "
        "Scored lines, standard bar each: MO ONE lay, OU25 OVER lay. Halves by date. Printed: OU25 UNDER lay, MO by role, D5 entry, and the same lines on Mar 2023 to Sep 2026 as an audit that cannot pass. "
        "About 190 MO and 200 OU25 trades a month at the rates seen, so two older months should reach n 300 per line. A pass earns a real-touch read on liq_sample, as a lay at a shortened price meets the spread item 415 measured.")
if not t.endswith('\n'):
    t += '\n'
t += item + '\n'
open(p, 'w').write(t)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
s = open(h).read()
old = "| item 414's jump-up back on Over/Under 2.5 at the off, a market the signal never read (499_jump_up_ou25, item 444) | RUNNING | -"
assert s.count(old) == 1
s = s.replace(old, "| item 414's jump-up back on Over/Under 2.5 at the off, a market the signal never read (499_jump_up_ou25, item 444) | DONE | nothing passes; ONE E1 n 1,365 -0.019 t -0.06 h1 +0.404 h2 -0.501; 2023 +0.556, 2024 -0.316, 2026 -1.573")
if not s.endswith('\n'):
    s += '\n'
s += "2026-11-08 | a (bf_hist_other, bf_hist_result, from 414, 444 controls) | lay a runner shortened 2-4 points at the off, MO and OU25, months before Mar 2023 (item 445) | TODO (re-check 12 Nov) | -\n"
s += "2026-11-08 | re-reads (bf_hist_other, af_*, from 342, 352, 406, 420-423, 435) | April and March 2023, months no read had used (499_apr23_rereads, 499_mar23_rereads) | DONE, interim | nothing passes; every line under n 300; jump-up E1 Mar-May n 515 about +0.22\n"
open(h, 'w').write(s)
print('ok')
