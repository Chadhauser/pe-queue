#!/bin/bash
# 611 (Mon 16 Nov 2026, 16:00). Run the tape replay (610) every Sunday after the engine, so the out-of-sample record grows weekly.
S=/root/pe-sports/team/weekly_engine.sh
grep -q tape_replay.py $S || sed -i '/verifier done/a cd /root/pe-sports/team \&\& timeout 7200 nice -n 10 /usr/bin/python3 tape_replay.py > tape_replay.log 2>\&1; cd /root/pe-queue \&\& git add reports/tape_replay.md 2>/dev/null; cd /root/pe-sports/team' $S
bash -n $S && grep -n tape_replay $S | cut -c1-160
echo "611 done"
