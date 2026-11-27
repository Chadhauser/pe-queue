#!/bin/bash
# fin 029 (own runner): financial league, universe C (C crypto, D currencies and gold, A shares and funds). Read-only on prices;
# writes results into fin state only. No orders.
cd /root/pe-finq/repo/fin/league && timeout 1740 python3 engine.py C /root/pe-finq/state/league 2>&1 | grep -v -i warning
