#!/bin/bash
# 646 (Tue 17 Nov 2026, 14:20). Read only. stream_client.py lines 75-140 (connect/subscribe loop and main loop), and what the Betfair
# login endpoint returned during the 06:33-09:08 gap if logged anywhere. Report: reports/stream_loop_646.md
R=/root/pe-queue/reports/stream_loop_646.md; S=/root/pe-stream/stream_client.py
{ echo "# 646 — $(date -u '+%F %H:%M') UTC"; echo '```python'; sed -n 75,140p $S | sed -E 's/(password|PW)=[^,)]*/\1=***/g'; echo '```'
echo '```'; sed -n 16300,16332p /root/pe-stream/stream.log | cut -c1-200; echo '```'
echo "liq recorder log in the gap:"; echo '```'; grep -hE "2026-11-17 0[6-9]" /root/pe-liq/*.log 2>/dev/null | grep -iE "login|json|error" | head -8 | cut -c1-200; echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "646: stream loop code" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
