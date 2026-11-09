#!/bin/bash
# 539 (Mon 9 Nov 2026). Betfair stream recorder, two faults the Watchman has logged for three days:
#  (a) SILENT STALL: the read loop treats a 30 s socket timeout as "carry on". Betfair heartbeats every 5 s, so 60 s with no message of
#      any kind means the connection is dead; the client sat on dead sockets for 11 h 34 min on 7 Nov and three times on 8 Nov until the
#      watchdog restarted it. Fix: no message for 60 s -> reconnect itself.
#  (b) RACING DROPPED: `sorted(ids)[:200]` capped the subscription alphabetically; racing ids sort above football, so with 250+ markets
#      the racing WIN markets (the time-critical ones) fell off while "subscribed 252" was logged. Fix: priority order — racing WIN,
#      football in-play, tennis in-play, football pre-match — then the cap, and the log says how many were cut.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-stream && cp stream_client.py stream_client.py.bak_539
python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; s=open(p).read()
old='send({"op":"marketSubscription","id":2,"marketFilter":{"marketIds":sorted(ids)[:200]}'
new='''pri={'racing':0,'football_inplay':1,'tennis':2,'football':3}
                    def _rank(m):
                        meta=universe.get(m,{}); sp=meta.get('sport','');
                        return (pri.get('football_inplay' if sp=='football' and meta.get('start') and meta['start']<=datetime.datetime.now(datetime.timezone.utc) else sp,9),m)
                    sub=sorted(ids,key=_rank)[:200]
                    if len(ids)>200: print("subscription cap: subscribing",len(sub),"of",len(ids),"(cut:",len(ids)-200,"lowest priority = football pre-match)",flush=True)
                    send({"op":"marketSubscription","id":2,"marketFilter":{"marketIds":sub}'''
assert s.count(old)==1, "cap anchor"; s=s.replace(old,new)
old2='''                try: line=f.readline()
                except socket.timeout: continue
                if not line: raise ConnectionError("stream closed")'''
new2='''                try: line=f.readline(); last_msg=time.time()
                except socket.timeout:
                    if time.time()-last_msg>60: raise ConnectionError("no message for 60 s (heartbeat expected every 5 s) — reconnecting")   # 539
                    continue
                if not line: raise ConnectionError("stream closed")'''
assert s.count(old2)==1, "stall anchor"; s=s.replace(old2,new2)
old3="state['conn']='connected'; backoff=2; state['sub_ids']=set(); last_sub=0"
assert s.count(old3)==1, "connected anchor"; s=s.replace(old3,old3+"; last_msg=time.time()")
open(p,'w').write(s); print("stream_client patched: priority cap + 60 s stall reconnect")
PY
python3 -m py_compile stream_client.py && echo "compiles" || { cp stream_client.py.bak_539 stream_client.py; echo "RESTORED (compile failed)"; exit 1; }
pkill -f stream_client.py; sleep 3; pgrep -f keepalive.sh >/dev/null || nohup /root/pe-stream/keepalive.sh >/dev/null 2>&1 &
sleep 60; echo "stream pids: $(pgrep -f stream_client.py | wc -l)"; tail -5 /root/pe-stream/stream.log 2>/dev/null || ls /root/pe-stream
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT last_seen, markets, ticks_last_min, conn_state FROM stream_heartbeat"); print("heartbeat:",c.fetchall())
c.execute("SELECT sport, count(*) FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes' GROUP BY 1"); print("ticks last 2 min by sport:",c.fetchall())
PY
echo "539 done"
