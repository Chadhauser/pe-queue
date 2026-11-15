import re,os,sys,psycopg2
sys.path.insert(0,'runner'); import creds
c=psycopg2.connect(creds.pg_local()).cursor()
c.execute("SELECT min(season),max(season),count(*) FROM af_fixtures"); print('af_fixtures seasons',c.fetchone())
# 1 jobs: rename, target must be free
for n in ('499_sep23_rereads','499_dnb_resting_pooled','499_cricket_touch_preoff','499_cricket_bands_truth','499_cricket_official_357','499_cricket_touch_inplay','499_reopen_racing','499_reopen_restored','499_reopen_tennis','499_tennis_log_no_replay'):
    a,b=f'jobs/{n}.sh.wip',f'jobs/{n}.sh'
    assert os.path.exists(a),a
    assert not os.path.exists(b),b
heads={'499_reopen_racing':"# STRUCK 2026-11-07: 90% of these reopens are replayed book states, see reports/finder_2026-11-07_items265-402.md. Its numbers are not a read of any market.\n",
       '499_reopen_restored':"# STRUCK 2026-11-07: total_matched falls at 59 of 59 rows, and returns to the same figure. The book shown is an old snapshot, not one you can trade. See reports/finder_2026-11-07_items265-402.md.\n",
       '499_reopen_tennis':"# VOID 2026-11-07: no trade reached a real exit, the reopens sit in a match's last minutes, and 67% are replayed states. See reports/finder_2026-11-07_items265-402.md.\n"}
for n in ('499_sep23_rereads','499_dnb_resting_pooled','499_cricket_touch_preoff','499_cricket_bands_truth','499_cricket_official_357','499_cricket_touch_inplay','499_reopen_racing','499_reopen_restored','499_reopen_tennis','499_tennis_log_no_replay'):
    a,b=f'jobs/{n}.sh.wip',f'jobs/{n}.sh'
    t=open(a).read()
    if n in heads:
        assert t.startswith('#!/bin/bash\nset -o pipefail\n')
        t=t.replace('#!/bin/bash\nset -o pipefail\n','#!/bin/bash\nset -o pipefail\n'+heads[n],1)
    open(a,'w').write(t); os.rename(a,b)
# 2 queue
R='reports/finder_2026-11-07_items265-402.md'
done={
'265':f"DONE 2026-11-07 — nothing passes, scored at n 326 on every month 263 did not read, Sep 2023 to Feb 2024: n 326, 301 games, +0.172 t 0.31 h1 -0.560 h2 +1.063, +0.052 without the largest win; CHEAP back n 127 -0.998, DEAR lay n 199 +0.919; closed; jobs/499_dnb_resting_pooled.sh, {R}. —",
'269':f"DONE 2026-11-07 — nothing passes, scored at n 452: +0.734 t 0.63 h1 +2.072 h2 -0.603, largest win £254.80 so about +0.17 without it; won 0.208 v 0.189, senior control n 12,968 -0.500; closed; jobs/499_sep23_rereads.sh, {R}. —",
'283':f"DONE 2026-11-07 — cannot pass, same months; both leans shrink: 2R 6-20 lay n 585 +0.200 t 1.62 h1 +0.004 h2 +0.375 (official only n 193 +0.367 t 1.81); 2R <1.5 back n 2,558 +0.109 t 1.11 (official only n 532 +0.326 t 1.68); jobs/499_cricket_bands_truth.sh, {R}. —",
'362':f"DONE 2026-11-07 — cannot pass, same months; lean kept: OUT 1.5 lay on official n 456 +1.283 t 1.65 h1 +0.065 h2 +2.500, won 0.643 v 0.677, +0.144 without the 10 largest wins, so item 357's resolved-only -0.330 was the misleading read; OUT 1.3 n 389 +1.451 t 1.34 h1 -1.200; the real touch is item 397; jobs/499_cricket_official_357.sh, {R}. —",
'395':f"DONE 2026-11-07, a day early, no data gate — nothing passes, 14 days of tape: n 55 -0.874 t -1.13 h1 -1.980 h2 +0.193, at the print -0.637. Spread median 5 ticks, so not over the rule's 5; lay touch 3 ticks above the print; cost of the touch about £0.28 per £10 mean, £0.15 median, against a lean of +0.247 to +0.452; under £2,000 matched £0.44, £2,000 to £50,000 about £0.11. Replay rows dropped; next door item 402; jobs/499_cricket_touch_preoff.sh, {R}. —",
'397':f"DONE 2026-11-07 — nothing passes, 14 days of tape: LAY at the real touch n 92 -4.025 t -3.56 h1 -3.279 h2 -4.771, won 0.774 v 0.616; same at the print -0.495 t -0.28; spread median 3 ticks. Replay rows dropped. jobs/499_cricket_touch_inplay.sh, {R}. —",
'177':f"DONE 2026-11-07 — nothing passes, closed by its own rule: cricket_fav_tape is the recorder it waited for. X20 <1.5 n 12, median spread 60 ticks against 2 charged; FADE -4.552, FOLLOW -3.134; every other band negative both ways. Replay rows dropped. jobs/499_cricket_touch_inplay.sh, {R}. —",
'396':f"DONE 2026-11-07 — STRUCK, not a read: 90.0% of racing reopens on ip_reopen are replayed book states (4,756 with a prior tape row), so 'first reopen' is not the off and the book is not live; DRIFT back n 97 +10.255 t 3.37 means nothing. jobs/499_reopen_racing.sh, {R}. —",
'398':f"DONE 2026-11-07 — VOID, not a read: 0 of 204 trades reached a real exit, as the reopens sit about 2 min before the log ends, 67.1% are replayed states, and +1.315 t 3.74 is 159 trades at last-print odds; the 45 settled at the result read FADE -0.452. jobs/499_reopen_tennis.sh, {R}. —",
'399':f"DONE 2026-11-07 — STRUCK, not a read: WINNER back n 115 +12.311 t 6.49 won 0.965 v 0.553 is an old book snapshot: total_matched falls at 59 of 59 rows, median -11.5%, then returns to the same figure, e.g. 260,000.80, 231,473.03, 260,000.80. The stream shows racing reopens on 12 markets where REST shows thousands. jobs/499_reopen_restored.sh, {R}. —",
'400':f"BLOCKED 2026-11-07 — closed before running: item 399 is a recorder artefact, so there is nothing to read on new races ({R}). —",
}
keep={
'342':f"TODO (UPDATE 2026-11-07: Sep-Oct 2023 n 190 -0.170 t -0.15 h1 +1.278 h2 -1.178, won 0.284 v 0.272, other games 0.236 v 0.255, control n 1,055 -0.984; pooled with item 344 by hand n 1,036 about +0.372; jobs/499_sep23_rereads.sh, {R}; Aug 2023 will add few, as a side needs five games that season; older months: af_fixtures runs from 2016, af_stats on those seasons not checked)",
'352':f"TODO (UPDATE 2026-11-07: Sep-Oct 2023 BOTH home lay n 73 -0.354 t -0.30 won 0.466 v 0.468, RALLY under 2.0 n 20 +1.518 t 0.56; pooled by hand n 1,180 about +0.447; jobs/499_sep23_rereads.sh, {R}; Aug 2023 will add few, as a run needs two games that season)",
}
L=open('watchman/FINDER_QUEUE.md').read().split('\n'); seen=set()
for i,l in enumerate(L):
    m=re.match(r'(\d+)\. (RUNNING 2026-11-07|TODO)(.*)',l,re.S)
    if not m: continue
    n,st,rest=m.groups()
    if n in done and st.startswith('RUNNING') or (n in('177','400') and st=='TODO' and 'recurring' not in rest[:30]) :
        L[i]=f"{n}. {done[n]}{rest}"; seen.add(n)
    elif n in keep and st.startswith('RUNNING'):
        L[i]=f"{n}. {keep[n]}{rest}"; seen.add(n)
    elif n=='394' and st=='TODO':
        L[i]=f"{n}. TODO (NOTE 2026-11-07: item 393's five are on the stream and traded volume does not rewind at any of them, so this stands, but item 392's 27 of 31 came from a REST log, the feed that replays old books, so do not quote it as support; {R}){rest}"
    elif n=='382' and st=='TODO':
        L[i]=f"{n}. TODO (NOTE 2026-11-07: checked for replays, none: traded volume fell at the fill on 0 of 225 first-touch entries, 0.04% of stream ticks anywhere; the lead's feed is clean; {R}){rest}"
    elif n=='70' and rest.startswith(' (recurring'):
        L[i]=L[i].replace(' — ',f" — 2026-11-07 about 13:42 UTC: 265 files/min, disk 63 GB, local DB 56 GB; Soccer 2023-09 DONE, 2023-08 at 41,760 of 45,729 files ({R}). ",1)
assert seen>=set(done)|set(keep),set(done)|set(keep)-seen
t='\n'.join(L)
if not t.endswith('\n'): t+='\n'
t+=f"""401. DONE 2026-11-07 — nothing passes, verdicts unchanged, sizes not: with replay rows dropped X10 triggers 145 to 59, FADE rest n 64 to 13, -2.561 t -3.69; X5 on a tight book n 100 to 30, FADE -0.500 t -4.81, FOLLOW -0.438 t -8.13; jobs/499_tennis_log_no_replay.sh, {R}. (Finder's own, from item 399's audit) **Items 129 and 391 without replay rows.** Rationale: bf_tennis_log's total_matched falls on 3.8% of pre-off and 18% of in-play rows over 2 days, and a replay is a fake shock. Same months, so it keeps or kills. Racing items 17, 172, 390 not re-run: 0.8% of finder_rlog pre-off rows fall, against losses at t -2.5 to -8.6.
402. TODO (from 21 Nov, about two weeks of new tape, then every two weeks; about 34 of these a fortnight, so n 300 is about 4 months and it will read the cost long before any verdict; Finder's own, source a, from item 395; table cricket_fav_tape, replay rows dropped, job 499_cricket_touch_preoff unchanged except the book filter) **Item 271's cricket outsider lay, books of £2,000 or more matched, at the real touch.** Rationale: item 395, cost of the touch £0.44 per £10 under £2,000 matched, about £0.11 from £2,000 to £50,000, against a lean of +0.247 to +0.452, so the thin books take the lean and the rest may keep it; over £250,000 costs £0.27 on 15 games, so it is kept in, not cut out. n 34 at £2,000 or more, a cut made after seeing costs and per-band results, so only new games count. Rule fixed now, no new cuts: as item 395, total matched at entry £2,000 or more, games after 7 Nov 2026 only, standard bar, halves by date. A pass earns a paper read, not a stake.
"""
open('watchman/FINDER_QUEUE.md','w').write(t)
# 3 ledger
s=open('watchman/HYPOTHESES.md').read()
for a,b in (("(499_reopen_racing, item 396) | RUNNING | -","(499_reopen_racing, item 396) | STRUCK | replayed book states, 90% of reopens; DRIFT back +10.255 t 3.37 not a read"),
            ("(499_cricket_touch_inplay, item 397) | RUNNING | -","(499_cricket_touch_inplay, item 397) | DONE | nothing passes; n 92 -4.025 t -3.56, at the print -0.495"),
            ("(499_reopen_tennis, item 398) | RUNNING | -","(499_reopen_tennis, item 398) | VOID | no real exit, reopens at a match's end, 67% replays"),
            ("(499_reopen_restored, item 399) | RUNNING | -","(499_reopen_restored, item 399) | STRUCK | old snapshot; total matched falls at 59 of 59 rows; WINNER back +12.311 t 6.49 not a read"),
            ("item 399 on unseen races | TODO (item 400, from 21 Nov) | -","item 399 on unseen races | BLOCKED (item 400) | closed, artefact"),
            ("cricket outsider lay at the real touch, rule fixed | TODO (item 395, from 8 Nov) | -","cricket outsider lay at the real touch (499_cricket_touch_preoff, item 395) | DONE | nothing passes; n 55 -0.874 t -1.13; cost £0.28 mean, £0.15 median")):
    assert s.count(a)==1,a
    s=s.replace(a,b)
if not s.endswith('\n'): s+='\n'
s+="""2026-11-07 | a (cricket_fav_tape, from 395) | cricket outsider lay on books of £2,000 or more matched, real touch | TODO (item 402, from 21 Nov) | -
2026-11-07 | audit (ip_reopen, ip_tape, stream_ticks) | REST recorders replay old books: bf_tennis_log, cricket_fav_tape, ip_tape, ip_reopen; stream clean (499_tennis_log_no_replay, item 401) | DONE | tennis verdicts hold, X10 triggers 145 to 59
"""
open('watchman/HYPOTHESES.md','w').write(s)
print('done',sorted(seen,key=int))
