#!/bin/bash
set -o pipefail
# 499_apr23_rereads (Finder 2026-11-08, queue items 406, 420, 421, 422, 423, 342, 352): each lead job unchanged except the date window, April 2023 only. Soccer 2023-04 read DONE on the loader about 01:50 UTC 8 Nov, after every one of these leads had read May 2023, so April is a month no read has used. Same rewrite pattern as jobs/499_may23_rereads.sh: the text replaced must exist (assert), nothing else in any job moves. Read only, no tables written. One month cannot reach n 300 on any of these, so all lines are interim reads; a lead's verdict comes when the seasons pool.
# Only the 5 jobs below. Items 429 and 435 read before Apr 2023 only (their months), so April is not theirs; item 137's first 300 games are burn-in, left out as on May.
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
echo "== JOB 499_jump_up_delay, April 2023, items 422 (ONE E1) and 423 (ONE D5); era label APR23, the CHOSE audit is empty by design"
rewrite $J/499_jump_up_delay.sh \
  "for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):" "for y,ms in ((2023,range(4,5)),):" \
  "T.dt<pd.Timestamp('2023-06-01',tz='UTC')" "T.dt<pd.Timestamp('2023-05-01',tz='UTC')" \
  "MAY23" "APR23" \
  "ITEM 422 May 2023" "ITEM 422 April 2023" \
  | bash || echo "ERROR: jump_up_delay failed"
echo "== JOB 499_ht_identity_may23 with the window April 2023, item 420"
rewrite $J/499_ht_identity_may23.sh "for y,m in [(2023,5)]:" "for y,m in [(2023,4)]:" | bash || echo "ERROR: ht_identity failed"
echo "== JOB 499_ht_youth_may23 with the window April 2023, item 421"
rewrite $J/499_ht_youth_may23.sh "for y,m in [(2023,5)]:" "for y,m in [(2023,4)]:" | bash || echo "ERROR: ht_youth failed"
echo "== JOB 499_ht_cards_older with the window April 2023, item 406"
rewrite $J/499_ht_cards_older.sh "A,B='2023-05-01','2023-08-01'" "A,B='2023-04-01','2023-05-01'" | bash || echo "ERROR: ht_cards failed"
OLD="WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))"
NEW="WINS=(('2023-04-01','2023-05-01'),)"
echo "== JOB 499_foul_draw_unseen, April 2023, item 342"
rewrite $J/499_foul_draw_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: foul_draw failed"
echo "== JOB 499_script_run_unseen, April 2023, item 352"
rewrite $J/499_script_run_unseen.sh "$OLD" "$NEW" | bash || echo "ERROR: script_run failed"
echo "== SURVIVORS: read each job's section above; all interim, one month, under n 300"
