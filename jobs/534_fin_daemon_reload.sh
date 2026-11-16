#!/bin/bash
# 534: reload the team daemon so the K4 scoreboard section (532) and any fin_team.py changes since 526 go live — deferred until no
# hypothesis is mid-run, so the E1/M7 tests queued by 528 are not killed.
cd /root/pe-fin/team || exit 1
python3 -m py_compile fin_team.py || { echo "fin_team.py does not compile — NOT restarting"; exit 1; }
nohup bash -c 'while python3 -c "import json,sys; sys.exit(0 if any(h[\"status\"]==\"running\" for h in json.load(open(\"/root/pe-fin/team/hypotheses.json\"))[\"hypotheses\"]) else 1)"; do sleep 60; done; pkill -f fin_team.py; sleep 1; nohup /root/pe-fin/team/run_team.sh >/dev/null 2>&1 &' >/dev/null 2>&1 & disown
echo "daemon reload scheduled (waits for running hypotheses)"
