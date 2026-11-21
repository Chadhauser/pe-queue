#!/bin/bash
# fin 020 (own runner): rewrite the scoreboard with the gap-fade count restarted from 23 Nov (Peter: "Restart") and show it. No orders.
cd /root/pe-finq/repo/fin/bots && echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)" && python3 -c "
import tick as T, os
T.summary(); print(open(os.path.join(T.BOTS, 'bots.md')).read()[:1500])"
