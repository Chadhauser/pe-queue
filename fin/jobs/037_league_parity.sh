#!/bin/bash
# fin 037 (own runner): proof that the league paper robot reads the same facts as the test. Reruns the shares test (which now writes
# the facts it used for its last day), then recomputes that day from the broker's own bars with the robot's code and compares.
S=/root/pe-finq/state; cd /root/pe-finq/repo/fin/league
timeout 1300 python3 engine.py A $S/league 2>&1 | grep -v -i warning | head -4 | cut -c1-300
timeout 400 python3 league_bot.py --parity 2>&1 | grep -v -i warning | cut -c1-300
