#!/bin/bash
# 290: STREAM SILENT DEATH 23:06 Thu → 09:30 Fri (10 h, 0 ticks) while the heartbeat said "connected": a half-dead TCP socket never
# raises; the read loop's 30 s timeout just 'continue's forever, and the DB heartbeat (written by the main thread) stayed fresh,
# so the watchdog saw nothing wrong. Fix: (1) any 90 s without a message from Betfair (heartbeats come every 5 s) = reconnect;
# (2) the DB heartbeat carries ticks_last_min — the watchdog now restarts the stream when markets>0 and ticks_last_min=0 for
# 10 min in daytime; (3) restart now and prove ticks.
set -e
python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; s=open(p).read(); o=s
s=s.replace("            s.settimeout(30)\n","            s.settimeout(30); last_msg=time.time()\n",1)
s=s.replace("                except socket.timeout: continue\n","                except socket.timeout:\n                    if time.time()-last_msg>90: raise ConnectionError('no message from Betfair for 90 s')\n                    continue\n                last_msg=time.time()\n",1)
assert s!=o and "last_msg=time.time()" in s and "no message from Betfair" in s, "anchors missing"
open(p,'w').write(s); print("dead-connection detection added")
PY
python3 -m py_compile /root/pe-stream/stream_client.py
pkill -f stream_client.py || true; sleep 2; nohup /root/pe-stream/keepalive.sh >/dev/null 2>&1 &
python3 - <<'PY'
p='/root/pe-push/watchdog.py'; s=open(p).read()
add='''
# stream-specific: connected but silent (markets>0, ticks_last_min=0) for 10 min in daytime = restart
try:
    cur.execute("SELECT markets, ticks_last_min, EXTRACT(epoch FROM now()-last_seen) FROM stream_heartbeat LIMIT 1"); r=cur.fetchone()
    import datetime as _dt; hr=_dt.datetime.utcnow().hour
    if r and r[0] and r[0]>0 and (r[1] or 0)==0 and 7<=hr<=23:
        cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES ('stream_client.py',0,'silent-check')")
        cur.execute("SELECT count(*) FROM watchdog_log WHERE bot='stream_client.py' AND action='silent-check' AND ts>now()-interval '10 minutes'"); n=cur.fetchone()[0]
        cur.execute("SELECT 1 FROM watchdog_log WHERE bot='stream_client.py' AND action='restarted-silent' AND ts>now()-interval '15 minutes'")
        if n>=2 and not cur.fetchone():
            subprocess.run("pkill -f stream_client.py || true; sleep 2; nohup /root/pe-stream/keepalive.sh >/dev/null 2>&1 &",shell=True)
            cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES ('stream_client.py',0,'restarted-silent')")
except Exception as e: print("stream silent check",repr(e)[:120])
'''
if 'restarted-silent' not in s: s=s+add; open(p,'w').write(s); print("watchdog silent-stream rule added")
PY
python3 -m py_compile /root/pe-push/watchdog.py
sleep 90
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT * FROM stream_heartbeat"); print("stream hb:",k.fetchall())
k.execute("SELECT sport, mkt, count(*) FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes' GROUP BY 1,2"); print("ticks last 2 min:",k.fetchall())
PY
tail -n 5 /root/pe-stream/stream.log
