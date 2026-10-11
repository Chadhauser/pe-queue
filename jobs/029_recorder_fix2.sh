#!/bin/bash
# 029: recorder still 400s with 68 live markets: priceData EX_ALL_OFFERS(17)+EX_TRADED(17)=34 per market x10 = 340 > 200.
# Drop EX_TRADED (totalMatched comes anyway), batch 8 (17x8=136). Restart.
f=/root/pe-liq/liq_recorder.py
sed -i 's/"priceData":\["EX_ALL_OFFERS","EX_TRADED"\]/"priceData":["EX_ALL_OFFERS"]/; s/range(0,len(ids),10)/range(0,len(ids),8)/; s/ids\[i:i+10\]/ids[i:i+8]/' $f
grep -n 'priceData\|range(0,len(ids)' $f
python3 -m py_compile $f || exit 1
pkill -f liq_recorder.py; sleep 2; nohup bash /root/pe-liq/keepalive.sh >/dev/null 2>&1 &
sleep 45; pgrep -af liq_recorder.py; tail -4 /root/pe-liq/recorder.log
echo "errors in last 60s of log:"; tail -20 /root/pe-liq/recorder.log | grep -c "loop error"
