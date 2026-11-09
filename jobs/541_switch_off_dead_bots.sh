#!/bin/bash
# 541 (Mon 9 Nov 2026). Switch off two paper bots that still run while marked stopped (Watchman 7-8 Nov: "late_over and racing_mm still beat
# while marked stopped"): late_over_paper (-£1.40/£10 over 123 dry trades) and the racing market-maker race_mm_size.py (preoff_scalp
# "loses the spread both ways"). Processes killed, keepalives removed, STOPPED files written so nothing relaunches them. Rows stay.
set -o pipefail
for pat in 'late_over' 'race_mm_size.py' 'preoff_scalp'; do pkill -f "$pat" && echo "killed $pat" || echo "$pat not running"; done
( crontab -l 2>/dev/null | grep -v 'late_over\|race_mm_size\|mm_footpre\|mm_tennis\|preoff_scalp' ) | crontab -
for d in /root/pe-race /root/pe-bot /root/pe-sports; do [ -d $d ] && touch $d/STOPPED_late_over $d/STOPPED_racing_mm; done
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
for b in ('late_over_paper','preoff_scalp_paper','racing_mm'):
    try: k.execute("UPDATE bot_status SET status='stopped', note='switched off 9 Nov 2026 (541)' WHERE bot=%s",(b,)); print(b,'bot_status rows',k.rowcount)
    except Exception as e: print(b,'bot_status:',str(e)[:80]); c.rollback()
PY
sleep 30; echo "still running: $(pgrep -fa 'late_over|race_mm_size|preoff_scalp' | wc -l) processes"
echo "541 done"
