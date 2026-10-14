#!/bin/bash
# 056: PG v3 placed NOTHING on Tue 13 Oct (pg_trades has no row since 12 Oct 00:26) although the heartbeat is alive. Read why:
# every skip reason the bot logged since the 046 restart, counted, plus the last 60 lines, plus whether goals were seen at all.
cd /root/pe-pg
echo "--- bot processes:"; pgrep -af pg_bot.py
echo "--- log lines since 13 Oct 05:38 by reason (first 6 words):"
awk '/2026-10-13 05:3[89]|2026-10-13 0[6-9]|2026-10-13 [1-2][0-9]|2026-10-14/{found=1} found' bot.log 2>/dev/null | awk '{print $1" "$2" "$3" "$4" "$5" "$6}' | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:,.]+//' | sort | uniq -c | sort -rn | head -40
echo "--- goal/suspension detections since restart:"; grep -ciE "goal|reopen|suspend" bot.log
echo "--- last 60 lines:"; tail -60 bot.log
echo "--- crontab:"; crontab -l | grep -i pg
