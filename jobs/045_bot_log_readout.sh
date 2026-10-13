#!/bin/bash
# 045: READ-ONLY. v3 placed zero orders on Monday despite 70+ goals in whitelist leagues. Show why from the bot log, and why 041 loaded no Understat data.
echo "== bot.log skip reasons since v3 (08:25 Mon) =="
grep -c "skip (league" /root/pe-pg/bot.log; grep -c "skip (spread/size)" /root/pe-pg/bot.log; grep -c "retry" /root/pe-pg/bot.log; grep -c "ENTRY LAY" /root/pe-pg/bot.log; grep -c "loop error" /root/pe-pg/bot.log
echo "-- last 40 non-skip-league lines:"; grep -v "skip (league" /root/pe-pg/bot.log | tail -40
echo "-- sample of league skips:"; grep "skip (league" /root/pe-pg/bot.log | awk -F'skip \\(league not in backtest\\): ' '{print $2}' | cut -d' ' -f1-3 | sort | uniq -c | sort -rn | head -20
echo "-- whitelist as loaded:"; python3 -c "import sys; sys.path.insert(0,'/root/pe-prematch'); from fts_collector import LEAGUES; print(sorted(LEAGUES))"
echo "== 041 understat log =="; tail -30 /root/pe-queue-logs/041_understat_pull_v2.log
