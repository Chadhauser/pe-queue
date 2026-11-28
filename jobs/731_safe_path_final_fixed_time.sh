#!/bin/bash
# 731: job 728 misfired at 05:28 UTC 28 Nov (the start-time file held a text note, so its 48-hour wait never ran). This replaces
# it with a fixed time: the dry run restarted 28 Nov 06:58 UTC, so the closing check runs after 30 Nov 07:00 UTC. Places nothing.
[ "$(date -u +%s)" -ge "$(date -u -d '2026-11-30 07:00:00' +%s)" ] || exit 75
nohup setsid /root/pe-builder/run_safe_path_final.sh > /dev/null 2>&1 < /dev/null &
