#!/bin/bash
# 094: INSTANT CHANNEL FOR M1. Web push is accepted by Apple but never shows on Peter's phone (notifications enabled, app on Home
# Screen) and email is too slow for a 60-second entry. Telegram was the channel before 26 Sept and is instantaneous: find the bot
# token + chat id already on this server, send "M1 TEST" to it, and make every M1 push also go to Telegram.
python3 - <<'PY'
import os, re, sys, glob, subprocess, requests
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars()
tg={k:v for k,v in E.items() if 'TELEGRAM' in k.upper() or k.upper() in ('TG_TOKEN','TG_CHAT_ID','BOT_TOKEN','CHAT_ID')}
print("telegram var names:",sorted(tg))
# also look in python files for a hard-coded token/chat id
hits=subprocess.run("grep -rhoE '[0-9]{8,10}:[A-Za-z0-9_-]{35}' /root/pe-*/*.py /root/pe-*/*.env /root/*.py 2>/dev/null | sort -u | head -3",shell=True,capture_output=True,text=True).stdout.split()
chats=subprocess.run("grep -rhoiE '(chat_id|TELEGRAM_CHAT)[\"'\\''= :]+-?[0-9]{6,12}' /root/pe-*/*.py /root/pe-*/*.env /root/*.py 2>/dev/null | grep -oE -- '-?[0-9]{6,12}' | sort -u | head -3",shell=True,capture_output=True,text=True).stdout.split()
print("tokens found in code:",len(hits),"chat ids found:",chats)
tok=next((v for k,v in tg.items() if 'TOKEN' in k.upper()),None) or (hits[0] if hits else None)
cid=next((v for k,v in tg.items() if 'CHAT' in k.upper()),None) or (chats[0] if chats else None)
if not tok: print("NO TELEGRAM TOKEN on server"); sys.exit(0)
if not cid:
    u=requests.get(f"https://api.telegram.org/bot{tok}/getUpdates",timeout=15).json()
    ids={str(m['message']['chat']['id']) for m in u.get('result',[]) if 'message' in m}
    print("chat ids from getUpdates:",ids); cid=next(iter(ids),None)
if not cid: print("NO CHAT ID - Peter must send the bot any message once, then re-run"); sys.exit(0)
r=requests.post(f"https://api.telegram.org/bot{tok}/sendMessage",json={"chat_id":cid,"text":"M1 TEST — Weekend Card alerts will arrive here instantly. ENTRY: lay the scorer. EXIT: back them 10 min later."},timeout=15).json()
print("telegram test:",r.get('ok'),str(r)[:150])
if r.get('ok'):
    open('/root/pe-push/telegram.env','w').write(f"TELEGRAM_BOT_TOKEN={tok}\nTELEGRAM_CHAT_ID={cid}\n")
    s=open('/root/pe-push/m1_alert.py').read()
    if 'telegram.env' not in s:
        s=s.replace("def push(title,body,tag):\n","""TG={}
try:
    for _l in open('/root/pe-push/telegram.env'):
        if '=' in _l: _k,_v=_l.strip().split('=',1); TG[_k]=_v
except Exception: pass
import requests as _rq
def push(title,body,tag):
    if TG.get('TELEGRAM_BOT_TOKEN'):
        try: _rq.post(f"https://api.telegram.org/bot{TG['TELEGRAM_BOT_TOKEN']}/sendMessage",json={"chat_id":TG['TELEGRAM_CHAT_ID'],"text":title+"\\n"+body},timeout=10)
        except Exception as e: print("tg err",repr(e)[:80],flush=True)
""")
        open('/root/pe-push/m1_alert.py','w').write(s)
    subprocess.run("python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; echo restarted-by-keepalive",shell=True)
    print("M1 alerter now sends Telegram + web push")
PY
