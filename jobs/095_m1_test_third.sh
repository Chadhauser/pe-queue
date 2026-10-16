#!/bin/bash
# 095: third M1 TEST push - Peter now has notifications enabled; proves delivery is instant.
cd /root/pe-push && python3 m1_alert.py --test; echo "--- m1.log tail"; tail -3 m1.log; echo "--- keepalive procs"; pgrep -af m1_alert.py
