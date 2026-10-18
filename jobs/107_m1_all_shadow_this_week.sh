#!/bin/bash
# 107: Peter 18 Oct 11:47 — "do it all as dry runs, review Monday, start next week; when trading, trade every game we can".
# This week: NO M1 pushes at all; every qualifying goal (card, £500k and tier-1/2) is recorded as SHADOW. A switch file controls it:
# /root/pe-push/m1_mode = shadow|live. Next week: live = pushes for EVERY qualifying tier-1/2 goal (not just the card).
echo shadow > /root/pe-push/m1_mode
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
if 'm1_mode' not in s:
    s=s.replace("            why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else ('SHADOW' if TIER12.search(comp or '') else None))\n",
                "            why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else ('SHADOW' if TIER12.search(comp or '') else None))\n"
                "            try: MODE=open('/root/pe-push/m1_mode').read().strip()\n            except Exception: MODE='live'\n"
                "            if why and MODE=='shadow': why='SHADOW'\n"
                "            if why=='SHADOW' and MODE=='live' and TIER12.search(comp or ''): why='tier12'\n")
    open(p,'w').write(s); print("mode switch patched")
else: print("already patched")
PY
python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; sleep 70; pgrep -af m1_alert.py; cat /root/pe-push/m1_mode; tail -2 /root/pe-push/m1.log
