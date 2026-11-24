#!/bin/bash
# fin 023 (own runner): read-only history test of opening-break exits (bank profits / protect a green trade). No orders.
cd /root/pe-finq/repo/fin/research && timeout 1700 python3 -I orb_exits.py 2>&1 | grep -v -i warning
