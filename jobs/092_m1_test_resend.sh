#!/bin/bash
# 092: resend the M1 TEST push (first one accepted by Apple 11:40 but Peter reports nothing on the phone) and show the alerter is alive.
cd /root/pe-push && python3 m1_alert.py --test; echo "--- m1.log tail"; tail -3 m1.log; echo "--- keepalive procs"; pgrep -af m1_alert.py
