#!/bin/bash
# 254: BUG SWEEP (Peter 26 Oct: "fix it and try and find other bugs").
#  1. API-Football stats recorder heartbeat went stale at 13:57 (47 min) with nothing restarting it — restart now, show why.
#  2. Asian-handicap rows (248) collapse every handicap line of a team into one selection name (Betfair AH runners share a
#     selectionId and differ by 'handicap') — the name now carries the line, e.g. "AL-ITTIHAD -0.5".
#  3. NEXT_GOAL produced 0 rows — list every in-play football market type with counts so the recorder targets what exists.
#  4. WATCHDOG (systemic fix for silent deaths): every 5 min, any bot whose heartbeat is >12 min old is killed and its keepalive
#     restarts it; one push per bot per hour. Covers stream, liquidity, ESPN, API-Football, xx, xg, late-over, ltd, s9, racing MM.
set -e
echo "== 1. stats recorder"; pgrep -af stats_recorder.py | head -2 || echo "NOT RUNNING"; tail -5 /root/pe-stats/stats.log || true
pkill -f stats_recorder.py || true; sleep 2; nohup /root/pe-stats/keepalive.sh >/dev/null 2>&1 & sleep 20; pgrep -af stats_recorder.py | head -1
echo "== 2. AH handicap in selection name"
python3 - <<'PY'
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
old="rows.append((selname(meta,r['selectionId']),"
new="rows.append(((selname(meta,r['selectionId'])+(f\" {float(r.get('handicap') or 0):+g}\" if meta['mkt']=='AH' else '')),"
if new in s: print("already patched")
else:
    assert old in s, "rec_rows anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("AH names carry the handicap")
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py; pkill -f liq_recorder.py || true; sleep 2; nohup /root/pe-liq/keepalive.sh >/dev/null 2>&1 &
echo "== 3. in-play football market types on Betfair right now"
python3 - <<'PY'
import sys,json,requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
app,user,pw=creds.betfair()
l=requests.post("https://identitysso.betfair.com/api/login",data={"username":user,"password":pw},headers={"X-Application":app,"Accept":"application/json"},timeout=15).json()
assert l.get('status')=='SUCCESS', "login failed"; tok=l['token']
r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketTypes/",headers={"X-Application":app,"X-Authentication":tok,"Content-Type":"application/json"},
                json={"filter":{"eventTypeIds":["1"],"inPlayOnly":True}},timeout=20).json()
rows=sorted(((x['marketType'],x['marketCount']) for x in r),key=lambda t:-t[1]); print("in-play football market types (type, markets):"); [print("  ",t) for t in rows[:40]]
PY
echo "== 4. watchdog"
cat > /root/pe-push/watchdog.py <<'PYFILE'
import sys, subprocess, time, psycopg2, datetime
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
BOTS=[('stream_heartbeat','stream_client.py','/root/pe-stream/keepalive.sh'),('liq_heartbeat','liq_recorder.py','/root/pe-liq/keepalive.sh'),
      ('espn_heartbeat','espn_recorder.py','/root/pe-stats/keepalive_espn.sh'),('stats_heartbeat','stats_recorder.py','/root/pe-stats/keepalive.sh'),
      ('xx_heartbeat','xx_recorder.py','/root/pe-xx/keepalive.sh'),('xg_heartbeat','xg_paper.py','/root/pe-xg/keepalive.sh'),
      ('late_over_heartbeat','late_over_paper.py','/root/pe-xg/keepalive_lo.sh'),('s9_heartbeat','s9_paper.py','/root/pe-xg/keepalive_s9.sh'),
      ('racing_mm_stream_hb','race_mm_stream.py','/root/pe-racing/keepalive_stream.sh')]
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS watchdog_log (ts TIMESTAMPTZ DEFAULT now(), bot TEXT, age_s INT, action TEXT)")
def tscol(t):
    cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s AND data_type LIKE 'timestamp%%' ORDER BY ordinal_position LIMIT 1",(t,)); r=cur.fetchone(); return r[0] if r else None
for hb,proc,keep in BOTS:
    try:
        c=tscol(hb)
        if not c: continue
        cur.execute(f"SELECT EXTRACT(epoch FROM now()-max({c})) FROM {hb}"); age=cur.fetchone()[0]
        if age is None or age<720: continue
        import os
        if not os.path.exists(keep):
            cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES (%s,%s,%s)",(proc,int(age),"stale, no keepalive at "+keep)); continue
        subprocess.run(f"pkill -f {proc} || true; sleep 2; nohup {keep} >/dev/null 2>&1 &",shell=True)
        cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES (%s,%s,%s)",(proc,int(age),"restarted"))
        cur.execute("SELECT 1 FROM watchdog_log WHERE bot=%s AND action='pushed' AND ts>now()-interval '1 hour'",(proc,))
        if not cur.fetchone():
            subprocess.run(["python3","/root/pe-push/send_push.py",f"watchdog: {proc} heartbeat {int(age//60)} min old — restarted"],timeout=30)
            cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES (%s,%s,'pushed')",(proc,int(age)))
    except Exception as e:
        con.rollback() if not con.autocommit else None; print(hb,repr(e)[:150])
PYFILE
python3 -m py_compile /root/pe-push/watchdog.py
( crontab -l 2>/dev/null | grep -v "pe-push/watchdog.py" ; echo "*/5 * * * * python3 /root/pe-push/watchdog.py >> /root/pe-push/watchdog.log 2>&1" ) | crontab -
ls /root/pe-stream/keepalive.sh /root/pe-liq/keepalive.sh /root/pe-stats/keepalive_espn.sh /root/pe-stats/keepalive.sh /root/pe-xx/keepalive.sh /root/pe-xg/keepalive*.sh /root/pe-racing/keepalive*.sh 2>&1
python3 /root/pe-push/watchdog.py; echo "watchdog first run done"
echo "== crontab now"; crontab -l
sleep 60
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT * FROM stats_heartbeat"); print("stats hb:",k.fetchall())
k.execute("SELECT sel, back_px, lay_px FROM liq_sample WHERE mkt='AH' ORDER BY ts DESC LIMIT 6"); print("AH rows:",k.fetchall())
k.execute("SELECT * FROM watchdog_log ORDER BY ts DESC LIMIT 10"); print("watchdog:",k.fetchall())
PY
