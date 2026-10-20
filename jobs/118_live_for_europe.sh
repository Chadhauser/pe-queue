#!/bin/bash
# 118: Peter 20 Oct 12:18 "yes" to live for Europe: M1 pushes for UEFA competitions only (UCL/UEL/UECL), £10; everything else shadow.
# Also: factory v2 status, post-fix minute check, commission by market.
echo europe > /root/pe-push/m1_mode
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
if "MODE=='europe'" not in s:
    s=s.replace("            if why and MODE=='shadow': why='SHADOW'\n",
                "            if why and MODE=='shadow': why='SHADOW'\n            if why and MODE=='europe': why=('europe' if (comp or '').upper().startswith('UEFA') else 'SHADOW')\n")
    open(p,'w').write(s); print("europe mode patched")
PY
python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; sleep 70; pgrep -af m1_alert.py; cat /root/pe-push/m1_mode
echo "== factory v2 =="; pgrep -af factory.py || echo "not running"; tail -6 /root/pe-factory/factory_run.log 2>/dev/null; tail -6 /root/pe-factory/factory.log 2>/dev/null; free -m | head -2
python3 - <<'PY'
import sys,psycopg2,requests; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT count(*) FILTER (WHERE minute>95), count(*) FROM liq_goal_depth WHERE offset_s=0 AND ts>'2026-10-19 06:45'"); print("goal rows since recorder fix: minute>95 / total:",c.fetchone())
c.execute("SELECT event_name, minute, to_char(goal_ts AT TIME ZONE 'Europe/London','HH24:MI') FROM liq_goal_depth WHERE offset_s=0 AND ts>'2026-10-19 18:00' AND mkt='MO' GROUP BY 1,2,3 ORDER BY 3 LIMIT 15"); print("last night's goals:",c.fetchall())
APP,U,P=creds.betfair()
tok=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=15).json()['token']
import datetime; now=datetime.datetime.now(datetime.timezone.utc); frm=now-datetime.timedelta(days=30)
r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listClearedOrders/",json={"betStatus":"SETTLED","settledDateRange":{"from":frm.isoformat().replace('+00:00','Z'),"to":now.isoformat().replace('+00:00','Z')},"groupBy":"MARKET","recordCount":1000},headers={"X-Authentication":tok,"X-Application":APP,"Content-Type":"application/json"},timeout=30).json()
ms=r.get('clearedOrders',[]); wins=[m for m in ms if (m.get('profit') or 0)>0]; comm=sum(m.get('commission') or 0 for m in ms); gw=sum(m['profit'] for m in wins)
print(f"BETFAIR 30d: markets {len(ms)}, winning markets {len(wins)}, gross wins £{gw:.2f}, commission £{comm:.2f} = {100*comm/gw if gw else 0:.1f}% of winning-market profit")
PY
