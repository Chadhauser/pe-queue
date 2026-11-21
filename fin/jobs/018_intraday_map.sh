#!/bin/bash
# fin 018 (own runner): data-led map of every share and fund with minute prices on disk. Read-only on data; one results file in fin state.
mkdir -p /root/pe-finq/state/research; ls /root/pe-data/alpaca | wc -l; grep -n "def bars" -A 9 /root/pe-fin/team/mech2.py | cut -c1-220
cd /root/pe-finq/repo/fin/research && timeout 1700 python3 intraday_map.py /root/pe-finq/state/research/intraday_map.csv 2>&1 | grep -v -i warning
