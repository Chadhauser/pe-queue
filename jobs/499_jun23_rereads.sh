#!/bin/bash
set -o pipefail
# 499_jun23_rereads (Finder 2026-11-07, queue items 342, 352): each job unchanged except the date window, reading only the games no earlier read has used now Soccer 2023-06 and 2023-07 are DONE. Same rewrite as jobs/499_aug23_rereads.sh.
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
NEW="WINS=(('2023-06-01','2023-08-01'),)"
echo "== JOB 499_foul_draw_unseen, Jun-Jul 2023, item 342"
rewrite $J/499_foul_draw_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: foul_draw failed"
echo "== JOB 499_script_run_unseen, Jun-Jul 2023, item 352"
rewrite $J/499_script_run_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: script_run failed"
echo "== SURVIVORS: read each job's section above"
