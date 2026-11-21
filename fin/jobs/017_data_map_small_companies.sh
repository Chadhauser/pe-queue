#!/bin/bash
# fin 017 (own runner): data-led map of the small-company daily history — every band and pair of bands scored on what the price did
# next, after our own measured costs. Read-only on data; writes one results file into fin state only. No orders.
mkdir -p /root/pe-finq/state/research
cd /root/pe-finq/repo/fin/research && timeout 1700 python3 data_map.py /root/pe-finq/state/research/data_map_small.csv 2>&1 | grep -v -i warning
