#!/bin/bash
# 098: M1 push text rewritten as tap-by-tap instructions (Peter 17 Oct: "it wasn't obvious enough what I needed to do").
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
old_e='''n=push(f"M1 ENTRY — {p['ev']}",f"{p['minute']}' {p['team']} scored. LAY {p['team']} @ {px:.2f}, £{STAKE}. Exit at {exit_min}' or next goal.",f"m1e-{mid}-{int(gts.timestamp())}")'''
new_e='''n=push(f"M1 ENTRY — {p['ev']}",f"{p['minute']}' {p['team']} scored. Open Betfair > Football > {p['ev']} > Match Odds. Tap the PINK box next to {p['team']}. Price {px:.2f}, stake £{STAKE}. Place bet. Then wait — EXIT push comes at {exit_min}' (or on the next goal).",f"m1e-{mid}-{int(gts.timestamp())}")'''
old_x='''push(f"M1 EXIT — {t['event_name']}",f"BACK {t['team']} now"+(f" @ {bp:.2f}" if bp else "")+(" — new goal/suspension" if newg else " — 10 minutes up")+". Record: entry "+f"{float(t['entry_px']):.2f}"+(f" exit {bp:.2f}" if bp else ""),f"m1x-{t['id']}")'''
new_x='''push(f"M1 EXIT — {t['event_name']}",f"Same market. Tap the BLUE box next to {t['team']}."+(f" Price {bp:.2f}," if bp else " Take the price showing,")+f" stake £{STAKE}. Place bet. Done"+(" (new goal/suspension)" if newg else " (10 minutes up)")+f". Write down: {float(t['entry_px']):.2f} -> "+(f"{bp:.2f}" if bp else "?"),f"m1x-{t['id']}")'''
assert old_e in s and old_x in s, "patterns not found"
s=s.replace(old_e,new_e).replace(old_x,new_x); open(p,'w').write(s); print("patched")
PY
python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; echo "alerter restarts via keepalive"; sleep 70; pgrep -af m1_alert.py
echo "--- today's M1 alerts:"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT event_name, minute, team, entry_px, exit_px, exit_reason, reason FROM m1_alerts WHERE entry_sent IS NOT NULL ORDER BY entry_sent"); print(c.fetchall())
PY
