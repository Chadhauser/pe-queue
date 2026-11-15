p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
old = "433. TODO (second part, items 84 and 130, next run; first part DONE 2026-11-07, item 179) — "
assert s.count(old) == 1
s = s.replace(old, "433. DONE 2026-11-07 — item 179 read with the guard (below); items 84 and 130 not re-read, as both leads were already closed on unseen games, item 404 VAR_GOAL_OFF n 282 +0.323 h2 negative, item 135 burst trailer n 92 +0.080, so a guard cannot reopen them — ", 1)
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
old_h = "| PART DONE | item 179 not an artefact: PEN OTHER back MOVED n 456 +6.321 t 1.72, UNMOVED -0.532; items 84, 130 TODO\n"
assert t.count(old_h) == 1
t = t.replace(old_h, "| DONE | item 179 not an artefact: PEN OTHER back MOVED n 456 +6.321 t 1.72, UNMOVED -0.532; 84 and 130 already closed by 404 and 135\n")
open(h, 'w').write(t)
r = '/root/pe-queue/reports/finder_2026-11-07_items433-434.md'
u = open(r).read()
old_r = "Verdict: item 179's lead is not a clock artefact; it sits in the moved prints. Items 84 and 130 not yet re-read (item 433 stays open for them)."
assert u.count(old_r) == 1
u = u.replace(old_r, "Verdict: item 179's lead is not a clock artefact; it sits in the moved prints. Items 84 and 130 not re-read: both were already closed on unseen games (item 404 n 282 +0.323, h2 negative; item 135 n 92 +0.080), so item 433 is closed.")
u = u.replace("Scratch files, untracked, not committed: .claim_433.py, .mk433.py, .claim_434.py, .fin434.py.", "Scratch files, untracked, not committed: .claim_433.py, .mk433.py, .claim_434.py, .fin434.py, .fin433.py.")
open(r, 'w').write(u)
print('ok', len(u.split('\n')))
