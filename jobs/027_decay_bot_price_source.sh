#!/bin/bash
# 027: READ-ONLY. The PG dry-run entries look like PRE-goal prices (e.g. lay Over 2.5 at 3.05 one minute after a goal at 37').
# Show how decay_bot.py sources the entry price, how often it polls, and how it detects goals, so the dry run can be made honest.
f=/root/pe-decay/decay_bot.py
echo "== file =="; ls -la $f; wc -l $f
echo "== poll / sleep =="; grep -n "sleep\|POLL\|interval" $f | head -20
echo "== price source =="; grep -n "lastPriceTraded\|availableToLay\|availableToBack\|ltp\|lay_price\|best_lay\|best_back\|priceData\|EX_BEST\|listMarketBook" $f | head -40
echo "== goal detection =="; grep -n "goal\|score\|SUSPENDED\|inplay\|status" $f | head -40
echo "== entry function =="; awk '/def .*(enter|open|place)/{p=1} p{print NR": "$0; n++} n>60{exit}' $f
echo "== recent bot log =="; ls -la /root/pe-decay/*.log 2>/dev/null; tail -40 /root/pe-decay/decay.log 2>/dev/null || tail -40 /root/pe-decay/*.log 2>/dev/null | tail -40
