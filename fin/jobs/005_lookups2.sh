#!/bin/bash
# fin 005 (own runner): read-only — the scoreboard rows for the rules now on paper (history-test numbers).
grep -n -E "\*\*WORKS\*\*|K2|K4|E1|crumb|FOMC" /root/pe-fin/team/scoreboard.md | cut -c1-700
echo "=== tail"; tail -c 3500 /root/pe-fin/team/scoreboard.md
