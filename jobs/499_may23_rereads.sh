#!/bin/bash
set -o pipefail
# 499_may23_rereads (Finder 2026-11-07, queue items 342, 352, 292): each job unchanged except the date window, May 2023 only, games no earlier read has used. Same rewrite as jobs/499_jun23_rereads.sh and jobs/499_cup_older.sh. Item 137 is left out, as its first 300 games are burn-in and one month is all burn-in. Item 292 was removed after one run: cup_ties needs league history from the 60 days before a game, and the tape starts May 2023, so 967 games had no league class, no DIVS game was read, and the job's table step fell over on the empty line. Read only.
rewrite() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
t=open(sys.argv[1]).read()
a,b=sys.argv[2],sys.argv[3]
assert a in t, "window text not found in "+sys.argv[1]
print(t.replace(a,b))
PY
}
J=/root/pe-queue/jobs
OLD="WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))"
NEW="WINS=(('2023-05-01','2023-06-01'),)"
echo "== JOB 499_foul_draw_unseen, May 2023, item 342"
rewrite $J/499_foul_draw_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: foul_draw failed"
echo "== JOB 499_script_run_unseen, May 2023, item 352"
rewrite $J/499_script_run_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: script_run failed"
echo "== SURVIVORS: read each job's section above; all interim, under n 300"
