#!/bin/bash
# fin 012 (own runner): read-only — show the untested ideas' test scripts and where opening-break history for the three funds lives.
cd /root/pe-fin/team || exit 1
for f in mech_events.py mech_m7door3.py; do echo "=== $f"; sed -E 's#(postgres(ql)?://)[^"'"'"' ]+#\1<hidden>#g' $f | cut -c1-400; done
echo "=== where M23/M24 (opening break on the other two funds) are tested"; grep -l -E "M23|M24" *.py | head; grep -n -E "M23|M24" *.py | cut -c1-300 | head -12
echo "=== minute data on disk"; ls /root/pe-data/alpaca | head -30; ls /root/pe-data/alpaca/* 2>/dev/null | head -20; ls /root/pe-data/events
