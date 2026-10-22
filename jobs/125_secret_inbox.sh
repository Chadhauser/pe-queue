#!/bin/bash
# 125: Peter has no shell on the server and the queue repo is public, so the new Betfair password reaches the server through the
# database: Peter inserts it himself in Railway's Data/Query tab into ops_inbox; this job picks it up, writes betfair.env, deletes
# the row, restarts the Betfair clients, and proves the login works. Waits (exit 75) until the row exists.
python3 - <<'PY'
import sys, re, subprocess, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS ops_inbox (key TEXT PRIMARY KEY, value TEXT, added TIMESTAMPTZ DEFAULT now())")
cur.execute("SELECT value FROM ops_inbox WHERE key='BETFAIR_PASSWORD'"); r=cur.fetchone()
if not r: print("WAITING for ops_inbox BETFAIR_PASSWORD"); sys.exit(75)
pw=r[0].strip()
p='/root/pe-logger/betfair.env'; s=open(p).read()
if re.search(r'^BETFAIR_PASSWORD=',s,re.M): s=re.sub(r'^BETFAIR_PASSWORD=.*$', 'BETFAIR_PASSWORD='+pw, s, flags=re.M)
else: s+='\nBETFAIR_PASSWORD='+pw+'\n'
open(p,'w').write(s)
cur.execute("DELETE FROM ops_inbox WHERE key='BETFAIR_PASSWORD'"); print("password written to betfair.env, inbox row deleted")
sys.path.insert(0,'/root/pe-queue/runner'); import importlib, creds; importlib.reload(creds); APP,U,P=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=15).json()
print("BETFAIR LOGIN:",r.get('status'),r.get('error',''))
if r.get('status')=='SUCCESS':
    subprocess.call("pkill -f liq_recorder.py; pkill -f ip_recorder.py; pkill -f race_swing.py; pkill -f pg_bot.py; pkill -f m1_alert.py",shell=True)
    print("recorders/bots restarted by keepalives with the new password")
else: print("LOGIN FAILED — password in the inbox was wrong; re-insert it and this job can be re-queued")
PY
