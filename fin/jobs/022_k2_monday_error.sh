#!/bin/bash
# fin 022 (own runner): read-only — the robot log around Monday's gap-fade entry.
grep -n -E "^2026-11-23 09:(3[0-9]|4[0-9])" /root/pe-finq/state/bots/bots.log | grep -v "position does not exist" | cut -c1-900 | head -30
echo ---; grep -n -E "ERROR|Traceback|K2" /root/pe-finq/state/bots/bots.log | tail -12 | cut -c1-900
echo ---; grep -c . /root/pe-finq/state/bots/bots.log; crontab -l | grep -i finq | cut -c1-200; ls -la /root/pe-finq/state/bots | tail -8
