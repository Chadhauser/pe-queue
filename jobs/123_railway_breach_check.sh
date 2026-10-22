#!/bin/bash
# 123: Railway env-var breach (22 Oct 03:00). Evidence pass, no secrets printed:
#  1. who is connected to our Postgres right now (client IPs) — anything that is not Contabo, Railway-internal or Peter's laptop is a stranger
#  2. any Betfair bets in the last 3 days that none of our bots placed (bf_cleared vs pg_bot/tennis/m1 logs by time)
#  3. Betfair account funds now vs yesterday (getAccountFunds) and last 20 account statement items
#  4. which secrets exist on THIS server (names only) so Peter knows exactly what to rotate
python3 - <<'PY'
import sys, datetime, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
print("== 1. current DB connections by client address")
cur.execute("SELECT coalesce(client_addr::text,'local'), usename, application_name, count(*), min(backend_start) FROM pg_stat_activity WHERE datname=current_database() GROUP BY 1,2,3 ORDER BY 4 DESC")
for r in cur.fetchall(): print("  ",r)
print("== 2. Betfair cleared bets last 3 days by hour (any hour with bets while our bots were idle is suspicious)")
try:
    cur.execute("SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name='bf_cleared'"); print("   bf_cleared cols:",cur.fetchone()[0][:300])
    cur.execute("SELECT date_trunc('hour',placed_date) h, count(*), round(sum(coalesce(profit,0))::numeric,2) FROM bf_cleared WHERE placed_date>now()-interval '3 days' GROUP BY 1 ORDER BY 1")
    for r in cur.fetchall(): print("  ",r)
except Exception as e: print("   bf_cleared:",repr(e)[:120])
print("== 3. Betfair funds + last statement items")
APP,U,P=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=15).json()
if r.get('status')!='SUCCESS': print("   LOGIN FAILED (password already changed? good — update /root/pe-logger/betfair.env):",r.get('error')); sys.exit(0)
H={"X-Authentication":r['token'],"X-Application":APP,"Content-Type":"application/json"}
f=requests.post("https://api.betfair.com/exchange/account/rest/v1.0/getAccountFunds/",json={},headers=H,timeout=15).json(); print("   funds:",{k:f.get(k) for k in ('availableToBetBalance','exposure','retainedCommission')})
s=requests.post("https://api.betfair.com/exchange/account/rest/v1.0/getAccountStatement/",json={"recordCount":20,"includeItem":"ALL"},headers=H,timeout=15).json()
for it in s.get('accountStatement',[]): print("   ",it.get('itemDate'),it.get('amount'),it.get('balance'),(it.get('itemClassData') or {}).get('unknownStatementItem') or it.get('legacyData',{}).get('marketName'))
print("== 4. secret files on this server (names only)")
import glob,os
for p in sorted(glob.glob('/root/pe-*/*.env')+glob.glob('/root/pe-*/vapid.env')):
    keys=[l.split('=')[0] for l in open(p) if '=' in l and not l.startswith('#')]; print("  ",p,keys)
PY
