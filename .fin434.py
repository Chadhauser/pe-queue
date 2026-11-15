p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "433. DONE 2026-11-07, first part (item 179) — "
assert s.count(old) == 1
s = s.replace(old, "433. TODO (second part, items 84 and 130, next run; first part DONE 2026-11-07, item 179) — ", 1)
s = s.replace("items 84 and 130 not re-read yet, TODO next run; jobs/499_goal_type_guard.sh (reports/finder_2026-11-07_item430.md)", "jobs/499_goal_type_guard.sh (reports/finder_2026-11-07_items433-434.md)", 1)
old = "434. RUNNING 2026-11-07 (lane A; "
assert s.count(old) == 1
s = s.replace(old, "434. DONE 2026-11-07 — nothing passes; PEN OTHER back MOVED n 447 +2.509 t 1.21 h1 +0.488 h2 +3.962, less top win +1.218, won 0.145 v implied 0.114; NORMAL control MOVED n 2,000 -0.622; jobs/499_pen_other_unseen.sh (reports/finder_2026-11-07_items433-434.md) — (lane A; ", 1)
assert '\n435. ' not in s
s = s.rstrip('\n') + '\n' + ("435. TODO (re-check 12 Nov with item 429, then as the loader adds each older season; Finder's own, source a, from items 179, 433, 434; tables bf_hist_other, af_events, af_fixtures; job 499_pen_other_unseen unchanged except the window) "
    "**Back the side that conceded a first-goal penalty once the price has moved, months neither read has used.** "
    "Rationale: two disjoint samples lean the same way, item 433 (2024-2025 mapped games) MOVED n 456 +6.321 t 1.72, item 434 (unmapped games Apr 2023 to Sep 2026) n 447 +2.509 t 1.21, both with both halves positive; open-play control flat to negative on both; long-price backs, median 10.5, so a few wins carry the mean. "
    "Rule fixed now, no new cuts: item 434's rule exactly; months: market_time before 2023-04-01 only (Soccer 2019-2023 as the loader reaches it; af_fixtures from 2016, af_events on those seasons to be counted first); score once n >= 300 new games, standard bar, halves by date; pool with 433 and 434 only if the new read is positive, and read without the largest win.") + '\n'
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old_h = "2026-11-07 | d (af_events, bf_hist_price, bf_hist_other, from 430-432) | priced-in guard on older af-minute goal-entry leads (items 179, 84, 130) | TODO (item 433, from 8 Nov) | -\n"
assert t.count(old_h) == 1
t = t.replace(old_h, "2026-11-07 | d (af_events, bf_hist_price, from 430-432) | priced-in guard on older af-minute goal-entry leads, item 179 first (499_goal_type_guard, item 433) | PART DONE | item 179 not an artefact: PEN OTHER back MOVED n 456 +6.321 t 1.72, UNMOVED -0.532; items 84, 130 TODO\n")
t = t.rstrip('\n') + '\n'
t += "2026-11-07 | a (bf_hist_other, af_events, from 179, 433) | back the side that conceded a first-goal penalty, moved prints, unseen games (499_pen_other_unseen, item 434) | DONE | nothing passes; n 447 +2.509 t 1.21 h1 +0.488 h2 +3.962; control -0.622\n"
t += "2026-11-07 | a (bf_hist_other, af_events, from 434) | the penalty-conceder back on months before Apr 2023, rule fixed | TODO (item 435, re-check 12 Nov) | -\n"
open(h, 'w').write(t)
print('ok')
