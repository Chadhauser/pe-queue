#!/bin/bash
# 515: FIX THE FAILS (Peter 10:16). Gate 08:29 had 3 FAIL: archive ip_tape watermark 6117 min, archive stream_ticks not started, "tape
# pruned since last run" (baseline counter; n_tup_del unchanged since the trap went in and delete_trap has 0 events, so the pruning has
# stopped and this check passes once the baseline is today's). This job drives the archive to within 3 h on all tables (repeats the
# hourly script until the watermarks are current, up to 2.5 h), then re-runs the integrity suite and prints it.
set -o pipefail
cd /root/pe-data
for i in $(seq 1 6); do
  flock -n /root/pe-data/.arch.lock timeout 1500 python3 tape_archive.py 2>&1 | grep -v Deprecation | tail -5
  python3 - <<'PY' && break
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()).cursor(); c.execute("select tbl, round(extract(epoch from now()-wm)/60) from tape_archive_wm order by 1"); r=c.fetchall(); print("watermark ages (min):",r)
sys.exit(0 if all(a is not None and a<180 for _,a in r) and len(r)>=3 else 1)
PY
done
echo "== integrity suite re-run"; python3 /root/pe-data/integrity_suite.py 2>&1 | grep -v Deprecation | tail -34
echo "== team"; pgrep -f sports_team.py >/dev/null && echo "daemon up" || echo "DAEMON DOWN"; tail -4 /root/pe-sports/team/team.log; grep -c RESULT /root/pe-sports/team/hypotheses.json
