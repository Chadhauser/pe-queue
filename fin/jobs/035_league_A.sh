#!/bin/bash
# fin 035 (own runner): financial league, shares and funds, corrected: stop and target exits priced two minutes after the breach
# (not at the stop level), and every share also scored against the same-moment average of all shares (hindsight in the share list).
cd /root/pe-finq/repo/fin/league && timeout 1740 python3 engine.py A /root/pe-finq/state/league 2>&1 | grep -v -i warning
