#!/bin/bash
set -o pipefail
# 499_feb23_rereads (Finder 2026-11-08, queue items 435, 406, 420, 421, 422, 423, 342, 352): each lead job unchanged except the date window, February 2023 only. Soccer 2023-02 read DONE on the loader at 06:22 UTC 8 Nov (bf_hist_months, 51,782 of 51,782 files), so February is a month no read has used. Same rewrite pattern as jobs/499_mar23_rereads.sh: the text replaced must exist (assert), nothing else in any job moves. Then items 422 and 423 pooled Feb to May 2023 in one read, as jobs/499_jump_up_unseen_pool.sh did for Mar to May. Read only, no tables written. One month cannot reach n 300 on most of these, so single-month lines are interim reads; the pooled 422/423 lines are scored.
rewrite() {
  python3 - "$@" <<'PY'
import sys
t=open(sys.argv[1]).read()
pairs=sys.argv[2:]
assert len(pairs)%2==0
for a,b in zip(pairs[0::2],pairs[1::2]):
    assert t.count(a)>=1, "window text not found in "+sys.argv[1]+": "+a
    t=t.replace(a,b)
print(t)
PY
}
J=/root/pe-queue/jobs
echo "== JOB 499_pen_other_unseen, February 2023, item 435 (PEN OTHER BACK MOVED)"
rewrite $J/499_pen_other_unseen.sh "A,B='2023-04-01','2026-10-01'" "A,B='2023-02-01','2023-03-01'" | bash || echo "ERROR: pen_other failed"
echo "== JOB 499_ht_identity_may23 with the window February 2023, item 420"
rewrite $J/499_ht_identity_may23.sh "for y,m in [(2023,5)]:" "for y,m in [(2023,2)]:" | bash || echo "ERROR: ht_identity failed"
echo "== JOB 499_ht_youth_may23 with the window February 2023, item 421"
rewrite $J/499_ht_youth_may23.sh "for y,m in [(2023,5)]:" "for y,m in [(2023,2)]:" | bash || echo "ERROR: ht_youth failed"
echo "== JOB 499_ht_cards_older with the window February 2023, item 406"
rewrite $J/499_ht_cards_older.sh "A,B='2023-05-01','2023-08-01'" "A,B='2023-02-01','2023-03-01'" | bash || echo "ERROR: ht_cards failed"
OLD="WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))"
NEW="WINS=(('2023-02-01','2023-03-01'),)"
echo "== JOB 499_foul_draw_unseen, February 2023, item 342"
rewrite $J/499_foul_draw_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: foul_draw failed"
echo "== JOB 499_script_run_unseen, February 2023, item 352"
rewrite $J/499_script_run_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: script_run failed"
echo "== JOB 499_jump_up_delay, February to May 2023 pooled in one read, items 422 (ONE E1) and 423 (ONE D5); era label UNSEEN, the CHOSE audit is empty by design"
rewrite $J/499_jump_up_delay.sh \
  "for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):" "for y,ms in ((2023,range(2,6)),):" \
  "MAY23" "UNSEEN" \
  "ITEM 422 May 2023" "ITEM 422 Feb to May 2023" \
  | bash || echo "ERROR: jump_up_delay pool failed"
echo "== SURVIVORS: the bar applies to UNSEEN ONE E1 and UNSEEN ONE D5 (Feb-May 2023 pooled); every other section is an interim one-month read under n 300"
