#!/bin/bash
# fin 033 (own runner): financial league, universe C, rerun (A: loader path fixed; C and D: holds of 2, 3 and 7 days and longer look-backs added).
cd /root/pe-finq/repo/fin/league && timeout 1740 python3 engine.py C /root/pe-finq/state/league 2>&1 | grep -v -i warning
