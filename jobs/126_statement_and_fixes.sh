#!/bin/bash
# 126: re-run of the evidence pass now the new Betfair password is on the server (123 could not log in) + fixes:
#  - copy_pros.py: numpy floats -> float before INSERT (cells were never written), 'minute' alias collision in the tape cells
#  - factory: print why strategy_results is still empty after 3 nights (log tail + process check)
# Evidence pass, no secrets printed:
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
s=requests.post("https://api.betfair.com/exchange/account/rest/v1.0/getAccountStatement/",json={"recordCount":40,"includeItem":"ALL"},headers=H,timeout=15).json()
for it in s.get('accountStatement',[]): print("   ",it.get('itemDate'),it.get('amount'),it.get('balance'),(it.get('itemClassData') or {}).get('unknownStatementItem') or it.get('legacyData',{}).get('marketName'))
print("== 4. secret files on this server (names only)")
import glob,os
for p in sorted(glob.glob('/root/pe-*/*.env')+glob.glob('/root/pe-*/vapid.env')):
    keys=[l.split('=')[0] for l in open(p) if '=' in l and not l.startswith('#')]; print("  ",p,keys)
PY

echo "== copy_pros fixes"; python3 - <<'PY2'
p='/root/pe-factory/copy_pros.py'; s=open(p).read()
s=s.replace("out.append((today,sport,strat,str(band),len(g),len(a),round(p1,2),round(t1,2),len(b),round(p2,2),round(t2,2),round(g[col].mean()*100,2),surv,",
            "out.append((today,sport,strat,str(band),int(len(g)),int(len(a)),float(round(p1,2)),float(round(t1,2)),int(len(b)),float(round(p2,2)),float(round(t2,2)),float(round(g[col].mean()*100,2)),bool(surv),")
s=s.replace("SELECT event_name, goal_ts, min(minute) minute FROM liq_goal_depth","SELECT event_name, goal_ts, min(minute) AS mn FROM liq_goal_depth")
s=s.replace("for t,m in zip(g.goal_ts,g.minute):","for t,m in zip(g.goal_ts,g.mn):")
open(p,'w').write(s); print("patched")
PY2
python3 -m py_compile /root/pe-factory/copy_pros.py && echo compiled
echo "== factory: why empty?"; pgrep -af factory.py || echo "factory not running now"; ls -la /root/pe-factory/; tail -40 /root/pe-factory/factory.log 2>/dev/null; cat /root/pe-factory/resume.sh 2>/dev/null | head -20; crontab -l | grep -E "factory|resume"
