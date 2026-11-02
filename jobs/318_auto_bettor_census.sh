#!/bin/bash
# 318: AUTO-BETTOR CENSUS (report only, nothing changed) — what order-placing code exists on the box, which app key it uses,
# whether it has a dry-run switch, when it last ran, and what the live tables hold. Needed before Tuesday's first £2 live.
echo "== files that can place orders"; grep -rl "placeOrders" /root/pe-bot /root/pe-* 2>/dev/null | grep -v pe-queue | sort
echo; echo "== per file: dry-run / live switches, stake constants, key name"
for f in $(grep -rl "placeOrders" /root/pe-bot /root/pe-* 2>/dev/null | grep -v pe-queue | sort); do
  echo "--- $f ($(stat -c %y "$f" | cut -c1-16))"; grep -n -i -E "dry_run|DRY|LIVE|paper|stake|size *=|app_key|APP_KEY|X-Application" "$f" | head -20
done
echo; echo "== processes running now that mention bet/order/live"; ps -eo pid,etime,cmd | grep -i -E "bettor|order|live_" | grep -v grep
echo; echo "== live tables (latest rows)"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); k=c.cursor()
for t,col in (('football_signals','logged_at'),('live_positions','*'),('live_signals','signal_time')):
    try:
        k.execute(f"SELECT count(*), max({col if col!='*' else 'NULL'}::text) FROM {t}"); print(t, k.fetchone())
    except Exception as e: c.rollback(); print(t,'ERR',str(e)[:80])
k.execute("SELECT column_name FROM information_schema.columns WHERE table_name='live_positions' ORDER BY ordinal_position"); print('live_positions cols:',[r[0] for r in k.fetchall()])
k.execute("SELECT * FROM live_positions ORDER BY 1 DESC LIMIT 3"); print('live_positions last 3:',k.fetchall())
k.execute("SELECT auto_status, count(*), max(placed_at) FROM football_signals GROUP BY 1"); print('football_signals by auto_status:',k.fetchall())
PY
echo; echo "== Betfair account funds (read-only call)"
python3 - <<'PY'
import sys,requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    app,user,pw=creds.betfair()
    r=requests.post('https://identitysso.betfair.com/api/login',data={'username':user,'password':pw},headers={'X-Application':app,'Accept':'application/json'},timeout=20).json()
    tok=r.get('token'); print('login:',r.get('status'))
    if tok:
        f=requests.post('https://api.betfair.com/exchange/account/json-rpc/v1',json=[{"jsonrpc":"2.0","method":"AccountAPING/v1.0/getAccountFunds","params":{},"id":1}],headers={'X-Application':app,'X-Authentication':tok,'Content-Type':'application/json'},timeout=20).json()
        print('funds:',{k:v for k,v in f[0].get('result',{}).items() if k in ('availableToBetBalance','exposure','retainedCommission','pointsBalance')})
except Exception as e: print('funds check failed:',str(e)[:120])
PY
