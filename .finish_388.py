import os, re
p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
L = open(p).readlines()
R = 'reports/finder_2026-11-07_items17-393.md'
V = {
 '17': f"nothing passes; 0 of 20 scored, every R<0.5 ALL line negative at the real touch: 11:30 out at last touch n 459 -0.114 t by race -8.63 h1 -0.143 h2 -0.084; 13:00 n 700 -0.100 t -8.37; out at BSP n 700 -0.079 t -6.69; even with no extra tick 13:00 n 700 -0.066. Median spread at entry 7 ticks, median stake £0.23, under Betfair's £1 minimum at £10 liability. Job 463's +0.20 on morning WAP was the spread. Racing_bsp join 5,889 runners, BSP within 2% on 1.000. No recorder needed: jobs/499_touch_log_racing.sh ({R})",
 '172': f"nothing passes; DRIFT 3-6 n 112 of 151 signals, -0.174, t by race -3.41, h1 -0.160 h2 -0.189, fill 0.742; FLAT control n 576 -0.149, so no better than no signal; crossing -0.188. Under n 300, and negative both halves: jobs/499_touch_log_racing.sh ({R})",
 '129': f"nothing passes; tennis only, cricket's log not read; FADE rest n 64 of 145 triggers, -2.057, t -6.98, h1 -2.288 h2 -1.826, fill 0.441; median spread at the trigger 18%, so X10 mostly marks a thin book; crossing fade -1.793, follow -2.126: jobs/499_touch_log_tennis.sh ({R})",
 '390': f"nothing passes; RESTED R<0.5 11:30 n 212 of 535 -0.057 t -2.55, 13:00 n 335 of 803 -0.052 t -2.69, both halves negative; control 13:00 n 820 -0.114. Half the loss of crossing and ahead of its control, but still negative at about 40% fills: jobs/499_touch_log_racing.sh ({R})",
 '391': f"nothing passes; X5 FADE n 100 -0.534 t -9.28, FOLLOW n 100 -0.599 t -5.38, both halves negative; X10 on a tight book only 7 games; both directions lose by about the round trip: jobs/499_touch_log_tennis2.sh ({R})",
 '392': f"NOT a pass, NXT lines struck by me: Q 1.1 n 69 +22.267 t 4.06, Q 1.2 n 85 +20.080 are a collapsed book near the post, e.g. 1.10 then back 27 lay 140, under n and void. SAME, the win rate against the price at the sampled row, gives no support: Q 1.1 n 95 -0.322 t -1.02 won 0.926 v 0.948; Q 1.2 n 129 0.000 t 0.16 won 0.930 v 0.923, against item 380's +0.742 and +0.898. Row sampling lags the first touch by up to 34 s, so it weakens item 380, does not refute it; item 382 stands: jobs/499_touch_log_inplay.sh ({R})",
 '393': f"exists, too small and thin; 5 of 119 touches collapsed past 2.0 on an OPEN market, 4 won, won 0.800 v implied 0.444, sum £25.64 at stakes capped by the size shown, £10.15 without the largest; size on show £1.59 to £7.98, median £2.74. Goes on as item 394: jobs/499_touch_collapse.sh ({R})",
}
done = set()
for i, l in enumerate(L):
    m = re.match(r'^(17|172|129|390|391|392|393)\. RUNNING 2026-11-07\s*(.*)', l, re.S)
    if m:
        n, rest = m.group(1), m.group(2)
        rest = re.sub(r'^\(data found on the box:.*?\) — ', '(data found 2026-11-07: Railway bf_racing_log and bf_tennis_log, 30 s real touch since 7 Sep 2026) ', rest)
        rest = re.sub(r'^— ', '', rest)
        L[i] = f"{n}. DONE 2026-11-07 — {V[n]} — {rest}"
        done.add(n)
assert done == set(V), done
for i, l in enumerate(L):
    if l.startswith('70. TODO (recurring, every run'):
        a = 'jobs/499_loader_progress.sh) — '
        assert a in l
        L[i] = l.replace(a, a + f"2026-11-07 about 10:45 UTC: 15,840 files in the last hour, about 264 a minute, disk 68 GB, local DB 51 GB; Soccer 2023-12 still 47,622 of 47,631; 18 months still LISTFAIL, 25 stale ({R}). ", 1)
        break
else:
    raise SystemExit('item 70 not found')
s = ''.join(L)
assert not re.search(r'^39[45]\. ', s, re.M)
if not s.endswith('\n'): s += '\n'
s += ("394. TODO (needs data — stream_ticks racing after 7 Nov 09:00 UTC; about 1.2 entries a day, so n 300 is about 8 months, and at £2.74 on show it is small money even if it holds; re-run from 10 Nov with item 382, every 3 days, as the ticks roll at about 5 days; Finder's own, source a; tables stream_ticks, finder_rresults; job 499_touch_collapse unchanged except the window) **Back a horse at 1.1 whose back price collapses past 2.0, on races the test has not seen.** Rationale: item 393, 5 of 119 touches, 4 won, 0.800 v implied 0.444; item 392's audit on the log, 31 such runners, 27 won, status and size unknown. Reads like a close finish, untested. Rule fixed now, no new cuts: as item 393, new races only; save each entry, as the ticks roll.\n")
s += ("395. TODO (from 8 Nov; first step, read the range of Railway cricket_fav_tape, seen on 24 Oct 2026, range not read; Finder's own, source a; tables cricket_fav_tape, cricket_matches, from jobs/499_cricket_outsider.sh) **Item 271's cricket outsider lay at the real touch.** Rationale: cricket_fav_tape has back_px and lay_px on two-runner cricket and no Finder job has read it; item 272 says a real pre-off touch needs a recorder, and this may be one; item 271 is +0.402 at 1 tick, +0.191 at 5. Rule fixed now, no new cuts: job 499_cricket_outsider's entries, outsider at 3-20, T-20 to T-2, at the tape's real lay, one tick adverse, one per game, official winner where matched, else last-print odds, as item 272. It reads the spread first: if the median spread is over 5 ticks, the lean is gone at any size.\n")
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
if not t.endswith('\n'): t += '\n'
t += """2026-11-07 | d census (pg_class v jobs/) | tables no Finder job has read: bf_racing_log, bf_tennis_log, bf_price_log, ip_reopen, cricket_fav_tape, racing_form_features | DONE | real touch since Aug-Sep 2026 found; golf_markets no pre-off price; no overseas racing on the box
2026-11-07 | b Webb (finder_rlog, racing_bsp) | morning money at the real touch (499_touch_log_racing, item 17) | DONE | nothing passes; 13:00 R<0.5 n 700 -0.100 t -8.37; no extra tick -0.066; job 463's +0.20 was the spread
2026-11-07 | b Webb (finder_rlog, racing_bsp) | morning money by resting (499_touch_log_racing, item 390) | DONE | nothing passes; 13:00 n 335 -0.052 t -2.69; control -0.114
2026-11-07 | a (finder_rlog) | lay a drifted 3-6 runner without crossing (499_touch_log_racing, item 172) | DONE | nothing passes; n 112 -0.174 t -3.41; FLAT control -0.149
2026-11-07 | a (finder_tlog) | tennis X10 pre-off shock, fade by resting (499_touch_log_tennis, item 129) | DONE | nothing passes; n 64 -2.057 t -6.98; median spread at trigger 18%
2026-11-07 | a (finder_tlog) | tennis X5, X10 shock on a tight book, follow or fade (499_touch_log_tennis2, item 391) | DONE | nothing passes; X5 FADE n 100 -0.534, FOLLOW n 100 -0.599
2026-11-07 | a (finder_rlog, finder_rresults) | item 380's first touch on 30 s rows, older races (499_touch_log_inplay, item 392) | DONE | NXT void, dead book; SAME Q 1.1 n 95 -0.322 t -1.02, Q 1.2 n 129 0.000; weakens item 380, item 382 stands
2026-11-07 | a (stream_ticks, finder_rresults) | horse at 1.1 whose back collapses past 2.0 (499_touch_collapse, item 393) | DONE | too small; 5 of 119, 4 won, 0.800 v 0.444, median £2.74 on show
2026-11-07 | a (stream_ticks, from 393) | back the collapse on unseen races, rule fixed | TODO (item 394, from 10 Nov) | -
2026-11-07 | a (cricket_fav_tape, from 271) | cricket outsider lay at the real touch, rule fixed | TODO (item 395, from 8 Nov) | -
"""
open(h, 'w').write(t)
J = '/root/pe-queue/jobs/'
for n in ('499_touch_log_pull', '499_touch_log_racing', '499_touch_log_tennis', '499_touch_log_tennis2', '499_touch_log_inplay', '499_touch_collapse'):
    assert not os.path.exists(J + n + '.sh'), n
    os.rename(J + n + '.sh.wip', J + n + '.sh')
print('queue, ledger, renames ok')
