#!/bin/bash
# 199: 195's patch asserted (the out.append line in factory.py differs from what I remembered) so the running factory is plain v3 —
# no factory_trades, no v4 gates. Print the exact lines so 200 can patch by index, plus the live LTD bot's first minute.
cd /root/pe-factory && grep -n -E "def emit|out.append|execute_values|def tstat|surv=|p1,|p2," factory.py | head -40
echo "== emit() body"; awk '/def emit\(/{f=1} f{print NR": "$0} /^def /&&!/def emit/{if(f&&NR>1)exit}' factory.py | head -60
echo "== factory running:"; pgrep -af "python3 factory.py" | head -2; tail -3 factory.log
echo "== ltd live bot"; pgrep -af ltd_live.py | head -1; tail -5 /root/pe-ltd/ltd_live.log 2>/dev/null
