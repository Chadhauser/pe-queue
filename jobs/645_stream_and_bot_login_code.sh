#!/bin/bash
# 645 (Tue 17 Nov 2026, 14:10). Read only. The stream tape was silent 06:33-09:08 UTC: its REST catalogue call kept failing with
# JSONDecodeError (non-JSON reply, usually an expired session) and retried every 60 s without logging in again; after re-auth Betfair
# then closed the stream as "not subscribed and idle 15000 ms". The paper bot died on the same JSONDecodeError. Show the login, REST
# call and connect/subscribe code of both, so the fix can be exact. Report: reports/login_code_645.md
R=/root/pe-queue/reports/login_code_645.md
S=$(ls /root/pe-stream/stream_client*.py 2>/dev/null | head -1); B=/root/pe-sports/bookie/bookie_v2.py
{ echo "# 645 — $(date -u '+%F %H:%M') UTC"; echo "stream file: $S"
echo '```python'; grep -nE "def |login|SSO|session|retry in|JSONDecode|listMarketCatalogue|subscribe|op.:.market|socket|ssl|while True|except" "$S" | head -80; echo '```'
for f in login api catalogue cat subscribe connect run main; do N=$(grep -nE "^def ${f}|^    def ${f}" "$S" | head -1 | cut -d: -f1); [ -n "$N" ] && { echo "### $S def $f (line $N)"; echo '```python'; sed -n "$N,$((N+30))p" "$S" | sed -E 's/(password|pw|PW)[^,)]*/\1=***/g'; echo '```'; }; done
echo "### bot login/api"; echo '```python'; sed -n 23,35p $B | sed -E 's/(password|pw|PW)[^,)]*/\1=***/g'; echo '```'
} > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "645: stream and bot login code" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
