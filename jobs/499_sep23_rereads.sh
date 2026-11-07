#!/bin/bash
set -o pipefail
# 499_sep23_rereads (Finder 2026-11-07, queue items 265, 269, 342, 352): each job unchanged except the date window, reading only the games no earlier read has used now Soccer 2023-09 is DONE.
# 265 jobs/499_derivative_gap.sh on Sep 2023. 269 jobs/499_women_ou15_unseen.sh on Sep 2023 to Feb 2024 and its 2026 games. 342 jobs/499_foul_draw_unseen.sh, 352 jobs/499_script_run_unseen.sh on Sep to Oct 2023.
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
echo "== JOB 499_derivative_gap, Sep 2023, item 265"
rewrite $J/499_derivative_gap.sh "market_time>='2024-03-01' AND market_time<'2026-10-01'" "market_time>='2023-09-01' AND market_time<'2023-10-01'" | bash || echo "ERROR: derivative_gap failed"
echo "== JOB 499_foul_draw_unseen, Sep to Oct 2023, item 342"
rewrite $J/499_foul_draw_unseen.sh "WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))" "WINS=(('2023-09-01','2023-11-01'),)" | bash || echo "ERROR: foul_draw failed"
echo "== JOB 499_script_run_unseen, Sep to Oct 2023, item 352"
rewrite $J/499_script_run_unseen.sh "WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))" "WINS=(('2023-09-01','2023-11-01'),)" | bash || echo "ERROR: script_run failed"
echo "== JOB 499_women_ou15_unseen, Sep 2023 to Feb 2024 and its 2026 games, item 269"
rewrite $J/499_women_ou15_unseen.sh "market_time>='2024-01-01' AND market_time<'2024-03-01'" "market_time>='2023-09-01' AND market_time<'2024-03-01'" | bash || echo "ERROR: women_ou15 failed"
echo "== SURVIVORS: read each job's section above"
