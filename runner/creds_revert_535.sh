#!/bin/bash
# one-command revert: Railway DSN back for everything
cp /root/pe-queue/runner/creds.py.bak_535 /root/pe-queue/runner/creds.py && pkill -f 'liq_recorder.py|stream_client|xx_recorder|bookie_paper.py|bookie_xx.py|sports_team.py|player_recorder|goal_signal|coach' ; echo reverted
