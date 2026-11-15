import os,re
R='/root/pe-queue/'
RP='reports/finder_2026-11-07_items353-359.md'
# ---- jobs: out of .wip, names checked free
for j in ('tennis_own_error','cricket_own_error','style_cor_yel','course_winner','yel_over_unseen','tennis_error_close'):
    a=R+f'jobs/499_{j}.sh.wip'; b=R+f'jobs/499_{j}.sh'
    assert os.path.exists(a) and not os.path.exists(b),j
    os.rename(a,b)
# ---- queue
p=R+'watchman/FINDER_QUEUE.md'; q=open(p).read()
DONE={
353:f"nothing passes, 0 of 16 (jobs/499_tennis_own_error.sh, {RP}; 10,658 scored matches; best HIGH lay CHALLENGER n 162 +1.992 t 1.38, HIGH lay ALL n 894 +0.244 t 0.52 h1 +0.593 h2 -0.104; it read as reversion, HIGH won 0.511 v 0.531, LOW 0.562 v 0.536)",
354:f"nothing passes, 0 of 4 (jobs/499_cricket_own_error.sh, {RP}; 7,438 games; best LOW back n 226 -0.433 t -0.46; every line negative, no persistence)",
355:f"nothing passes, 0 of 36 (jobs/499_style_cor_yel.sh, {RP}; 10,445 games; best YEL HIGH Under lay n 1,503 +0.535 t 1.96 h1 +0.675 h2 +0.366, YEL HIGH Over back +0.451 t 1.67, nearly the same bet)",
356:f"nothing passes, 0 of 24 (jobs/499_course_winner.sh, {RP}; 14,258 races, 88,129 runners with history; best CW all lay n 5,044 +0.101 t 1.69, CW <=5 lay n 1,053 +0.347 t 1.62 h1 +0.529 h2 +0.216)",
357:f"nothing passes, 0 of 16; the job is jobs/499_cricket_own_error.sh, not the name in the rule ({RP}; best OUT 1.5 lay n 4,135 +0.516 t 1.85, but resolved games read n 3,701 -0.330 t -1.18 and the 434 unresolved carry +£3,356, so no lead)",
358:f"did not hold (jobs/499_yel_over_unseen.sh, {RP}; HIGH Over back n 784 +0.142 t 0.38 h1 +0.584 h2 -0.879, won 0.506 v 0.493; control n 4,585 -0.308)",
359:f"not supported (jobs/499_tennis_error_close.sh, {RP}; HIGH n 1,290 z -1.00, LOW n 487 z 0.68 v bar 2; same sign as item 353; lay HIGH at closes +0.589 t 0.93)",
}
for k,v in DONE.items():
    a=f"\n{k}. RUNNING 2026-11-07 ("
    assert q.count(a)==1,k
    q=q.replace(a,f"\n{k}. DONE 2026-11-07 — {v} — (")
a="\n70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
assert q.count(a)==1
q=q.replace(a,a+f"2026-11-07 about 04:50 UTC: 16,176 files in the last hour, about 270 a minute, disk 76 GB, local DB 49 GB; Soccer 2023-10 still loading, 18 months still LISTFAIL, 24 stale ({RP}). ")
if not q.endswith('\n'): q+='\n'
q+="""360. TODO (needs data — complete UK/IE win races after 4 Nov 2026, from the Betfair historical files, as items 94 and 105; about 18 CW <=5 runners a month on the box, so long unless the racing history grows; Finder's own, source d; table racing_bsp, job 499_course_winner) **Lay a course winner at a morning price of 5.0 or under, on unseen races.** Rationale: item 356, CW <=5 lay n 1,053 +0.347 t 1.62 h1 +0.529 h2 +0.216, won 0.276 v implied 0.301, control -0.062; it is the best of 24, so chance could give it. Rule fixed now, no new cuts: CW as item 356, morning WAP <= 5, lay at BSP one tick adverse, standard bar plus t by race, halves by date.
361. TODO (needs data — Tennis MATCH_ODDS after Mar 2026, loader 347, results run to Sep 2026; Finder's own, source d; tables bf_hist_other, tennis_results_2026, job 499_tennis_own_error) **Lay a tennis player who has beaten their price, on unseen months.** Rationale: item 353 HIGH won 0.511 v 0.531 and item 359 at closes won 0.613 v 0.640, same sign, z -1.00, below the bar of 2, so a weak lead. Rule fixed now, no new cuts: HIGH as item 353, lay, ALL only, history from the whole tape, scored only on markets after 31 Mar 2026, standard bar.
362. TODO (from 8 Nov, about 5 min, with item 283; Finder's own, source a; tables bf_hist_other, cricket_matches, job 499_cricket_own_error) **Item 357's OUT lines on official cricket results.** Rationale: OUT 1.5 lay reads +0.516 on all games and -0.330 on resolved games, so the 434 unresolved games decide it, and last-print odds near 50-50 against a lay stake of about £300 are not a fair read. Rule fixed now, no new cuts: 357's entries, official winners on cricket_matches to 27 Apr 2026, matched games only, unmatched counted. Same months, so this only keeps or kills the lean and cannot pass.
"""
open(p,'w').write(q)
# ---- ledger
p=R+'watchman/HYPOTHESES.md'; h=open(p).read()
if not h.endswith('\n'): h+='\n'
h+="""2026-11-07 | d (bf_hist_other, tennis_results_2026) | a tennis player's own price error, walked forward (499_tennis_own_error, item 353) | DONE | nothing passes; 0 of 16; HIGH lay ALL n 894 +0.244 t 0.52; reads as reversion
2026-11-07 | d (bf_hist_other) | a cricket team's own price error, walked forward (499_cricket_own_error, item 354) | DONE | nothing passes; 0 of 4, all negative
2026-11-07 | d (af_stats, bf_hist_price) | corners, yellows, blocked shots, first price (499_style_cor_yel, item 355) | DONE | nothing passes; 0 of 36; YEL HIGH Under lay n 1,503 +0.535 t 1.96
2026-11-07 | d (racing_bsp) | course winner, ran here, new to the course, at BSP (499_course_winner, item 356) | DONE | nothing passes; 0 of 24; CW <=5 lay n 1,053 +0.347 t 1.62
2026-11-07 | a (bf_hist_other) | cricket, first in-play touch of a price, hold to result (499_cricket_own_error, item 357) | DONE | nothing passes; 0 of 16; OUT 1.5 lay +0.516 t 1.85 all, -0.330 t -1.18 resolved, no lead
2026-11-07 | d (af_stats, bf_hist_other) | Over 2.5 between two high-yellow sides, unseen (499_yel_over_unseen, item 358) | DONE | did not hold; n 784 +0.142 t 0.38 h2 -0.879
2026-11-07 | d (tennis_matches) | player price error reverts, Pinnacle closes, unseen dates (499_tennis_error_close, item 359) | DONE | not supported; HIGH z -1.00, LOW z 0.68
2026-11-07 | d (racing_bsp, from 499_course_winner) | lay a course winner at 5.0 or under, unseen races, rule fixed | TODO (item 360, needs data) | -
2026-11-07 | d (bf_hist_other, from 499_tennis_own_error) | lay a tennis player who has beaten their price, unseen months, rule fixed | TODO (item 361, needs data) | -
2026-11-07 | a (cricket_matches, from 499_cricket_own_error) | item 357's OUT lines on official results, rule fixed | TODO (item 362, from 8 Nov) | -
"""
open(p,'w').write(h)
# ---- report
open(R+RP,'w').write("""# Finder 2026-11-07, items 353-359; item 70

Money: nothing here supports a stake, so this run adds no money line. Every open queue item is blocked on data or dated later (283, 339 from 8 Nov), and item 0i is with the parallel run, so 353-359 are the Finder's own. Rules were pushed before any price (8228779 and the 358, 359 commits).

Data health: Railway still slow, a catalogue query hit a 60 s limit, full pulls ran. Loader about 270 files a minute, disk 76 GB, local DB 49 GB; Soccer 2023-10 loading, 18 months LISTFAIL, 24 stale. So items 342 and 352 wait.

Data: bf_hist_other Tennis 10,658 scored matches of 36,549 markets, Cricket 7,438 games; af_stats, af_fixtures, bf_hist_price 10,445 games; racing_bsp 14,258 races; tennis_matches ATP 12,619 matches. LTP only, inferred cricket results, so any pass would be an upper bound. Logs are in the session, as /root/pe-queue-logs needs approval from an unattended run.

| Item | Line (best by t, then the ones that matter) | n | per £10 | t | h1 | h2 | Games | Bar |
|---|---|---|---|---|---|---|---|---|
| 355 corners, yellows, blocks | YEL HIGH Under lay | 1,503 | +0.535 | 1.96 | +0.675 | +0.366 | 1,503 | fail |
| 355 | YEL HIGH Over back | 1,503 | +0.451 | 1.67 | +0.581 | +0.293 | 1,503 | fail |
| 355 | BLK HIGH Draw back | 2,269 | +0.364 | 0.99 | +0.944 | -0.067 | 2,269 | fail |
| 357 cricket first touch | OUT 1.5 lay, all games | 4,135 | +0.516 | 1.85 | +0.426 | +0.605 | 4,063 | fail |
| 357 | OUT 1.5 lay, resolved only | 3,701 | -0.330 | -1.18 | | | | fail |
| 357 | OUT 1.3 lay, all games | 3,555 | +0.638 | 1.75 | +0.102 | +1.173 | 3,506 | fail |
| 357 | OUT 1.15 back | 2,852 | +0.126 | 1.01 | -0.006 | +0.258 | 2,837 | fail |
| 356 course form | CW all lay | 5,044 | +0.101 | 1.69 | +0.082 | +0.111 | 3,465 | fail |
| 356 | CW <=5 lay | 1,053 | +0.347 | 1.62 | +0.529 | +0.216 | 1,000 | fail |
| 353 tennis own error | HIGH lay CHALLENGER | 162 | +1.992 | 1.38 | +1.906 | +2.075 | 162 | fail, n |
| 353 | LOW back ATP | 172 | +0.642 | 0.73 | +0.197 | +1.088 | 172 | fail, n |
| 353 | HIGH lay ALL | 894 | +0.244 | 0.52 | +0.593 | -0.104 | 894 | fail |
| 354 cricket own error | LOW back | 226 | -0.433 | -0.46 | -0.924 | +0.058 | 226 | fail |
| 358 yellows, unseen | HIGH Over back | 784 | +0.142 | 0.38 | +0.584 | -0.879 | 784 | fail |
| 359 closes, ATP | HIGH lay, proxy | 1,290 | +0.589 | 0.93 | +0.194 | +0.981 | 1,290 | cannot pass |

Survivors: none. 353 0 of 16, 354 0 of 4, 355 0 of 36, 356 0 of 24, 357 0 of 16, 358 0 of 1, 359 not supported, z -1.00 and 0.68 v a bar of 2.

## Verdict

NOT YET, nothing passes.

What the data does support, and it is thin. Laying a course winner at a morning price of 5.0 or under: won 0.276 v implied 0.301, both halves positive, against a control of -0.062. Fading a tennis player who has beaten their price: won 0.511 v 0.531 on the tape, 0.613 v 0.640 at closes, the same sign twice, neither near the bar. Paper only, no stake supported.

Did not hold: item 355's yellow-card lead. On unseen games the second half is -0.879. Do not chase it. It was the best of 36 anyway, and its top two lines are nearly one bet.

Item 354 finds no team to follow or fade; item 353 set out to find persistence and found none.

Next door, all with rules fixed in the queue: item 362, 357's OUT lines on official cricket results, 8 Nov with item 283; items 360 and 361 when the data arrives.

## Review

Faults found in my own work before this report:
1. Item 357's lead is a scoring effect. Unresolved games are 10% of OUT 1.5 lay and carry +£3,356 against -£1,222 on the resolved 90%. Two short last prints score near 50-50 against a lay stake of about £300. Diagnostics added to the job, printed above; the verdict is unchanged, and item 362 settles it. The earlier memory note that last-print odds are the honest scoring holds for lays at longer prices; at very short lay prices it is not safe.
2. A resolved lay at a fill of 1.1 or under reads +21.161 on n 56, won 0.804 v implied 0.956. A print at 1.05 straight after 1.5 looks like a junk print (item 281), and the next one may not be there to lay. No new item from it.
3. First cricket run died on memory, a code fault, fixed once with a chunked pull. Nothing cut.
4. The rule for item 357 names a job that was never written; both cricket items run in jobs/499_cricket_own_error.sh. The queue says so.
5. Three scratch files, .claim_353.py, .claim_359.py, .make_358.py, and one more for this finish, stay untracked in the repo root, as rm was refused. They hold no secrets.

## Limits

99 lines read tonight, so a t of about 2.5 is what chance gives the best of them; nothing here reaches it. Tennis lost 16,638 of 36,549 markets to no unique results match, not broken down by tour. Tennis and cricket history is on the tape only, so a player needs 20 matched matches and a team 15 before a state exists. Racing history is the box's part of racing, so CW is understated. Item 358 matched 0.789 of unseen fixtures by name and lost 923 with no print within 5 minutes. Item 359 is ATP only.

Blocked in one line: seeds and qualifier status, as tennis_results_2026 has no seed or entry column; would come from the full match files.

Item 0i: with the parallel run, not touched here. Item 70: as Data health.
""")
print('ok')
