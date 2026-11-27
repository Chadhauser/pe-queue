#!/bin/bash
# 728: closing check of 727. Waits (exit 75 = retried every cycle) until the build session has ended AND the dry run has been
# going 48 hours, by file times only (no process-name checks). Places nothing.
S=/root/pe-real/dry_started; E=/root/pe-real/build_session_ended
[ -s "$S" ] && [ -s "$E" ] || exit 75
[ $(( $(date +%s) - $(cat "$S") )) -ge 172800 ] || exit 75
nohup setsid /root/pe-builder/run_safe_path_final.sh > /dev/null 2>&1 < /dev/null &
