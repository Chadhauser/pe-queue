#!/bin/bash
# 274: four faults found this afternoon, fixed together.
#  1. WATCHDOG restarted the crash-looping recorder 55 times without saying why. Now: after 3 restarts in 30 min with no
#     heartbeat recovery it records CRASH LOOP + the last 15 log lines in watchdog_log and stops restarting that bot (Claude
#     reads the table; a code fix is needed, not a 56th restart).
#  2. LTD probe: 'if not fin: continue' settles never when the 85' book is missing — same bug as xG (255). ESPN final-score fallback.
#  3. stream_ticks on the live key = ~11,000 rows/min (16M/day); 30-day retention would be ~500M rows. Retention 3 days + index.
#  4. Runner: a re-polling (exit 75) job is capped at 20 min per cycle and stays 'waiting' on timeout, so a long resumable
#     download cannot hold the queue 50 min of every 52 (today's Dukascopy job, erroring on every file).
set -e
echo "== 1. watchdog escalation"
python3 - <<'PY'
p='/root/pe-push/watchdog.py'; s=open(p).read()
old="""        subprocess.run(f"pkill -f {proc} || true; sleep 2; nohup {keep} >/dev/null 2>&1 &",shell=True)
        cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES (%s,%s,%s)",(proc,int(age),"restarted"))"""
new="""        cur.execute("SELECT count(*) FROM watchdog_log WHERE bot=%s AND action='restarted' AND ts>now()-interval '30 minutes'",(proc,)); nrest=cur.fetchone()[0]
        cur.execute("SELECT 1 FROM watchdog_log WHERE bot=%s AND action LIKE 'CRASH LOOP%%' AND ts>now()-interval '6 hours'",(proc,))
        if cur.fetchone(): continue                      # already escalated; a code fix is needed, not another restart
        if nrest>=3:
            logf=keep.rsplit('/',1)[0]
            tail=subprocess.run(f"tail -n 15 {logf}/*.log 2>/dev/null | tail -c 1500",shell=True,capture_output=True,text=True).stdout
            cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES (%s,%s,%s)",(proc,int(age),"CRASH LOOP — stopped restarting. log: "+tail)); continue
        subprocess.run(f"pkill -f {proc} || true; sleep 2; nohup {keep} >/dev/null 2>&1 &",shell=True)
        cur.execute("INSERT INTO watchdog_log(bot,age_s,action) VALUES (%s,%s,%s)",(proc,int(age),"restarted"))"""
assert old in s, "watchdog anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("watchdog escalation added")
PY
python3 -m py_compile /root/pe-push/watchdog.py
echo "== 2. ltd probe settle fallback"
python3 - <<'PY'
p='/root/pe-xg/ltd_paper.py'
import os
if not os.path.exists(p):
    import glob; c=[f for f in glob.glob('/root/pe-*/ltd_paper.py')]; p=c[0] if c else None
print("ltd bot file:",p)
s=open(p).read()
old="""            fin=final_book(mid)
            if not fin: continue
            w=min(fin,key=fin.get)
            if fin[w]>1.15: reason,pnl='UNKNOWN',None
            elif w=='DRAW': reason,pnl='SETTLE_LOSS',round(-STAKE*(float(lp)-1),2)
            else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
"""
new="""            fin=final_book(mid)
            if fin and min(fin.values())<=1.15:
                w=min(fin,key=fin.get)
                if w=='DRAW': reason,pnl='SETTLE_LOSS',round(-STAKE*(float(lp)-1),2)
                else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            else:
                cur.execute('SELECT hs, "as", minute FROM espn_stats WHERE market_id=%s AND hs IS NOT NULL ORDER BY ts DESC LIMIT 1',(mid,)); fs=cur.fetchone()
                if fs and fs[2] is not None and fs[2]>=85:
                    reason,pnl=('SETTLE_LOSS',round(-STAKE*(float(lp)-1),2)) if fs[0]==fs[1] else ('SETTLE_WIN',round(STAKE*(1-COMM),2))
                else:
                    cur.execute("SELECT entry_ts<now()-interval '6 hours' FROM ltd_inplay_paper WHERE id=%s",(pid,))
                    if not cur.fetchone()[0]: continue
                    reason,pnl='UNKNOWN',None
"""
if new in s: print("already patched")
else:
    assert old in s, "ltd settle anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("ltd settle fallback patched")
PY
LTD=$(ls /root/pe-*/ltd_paper.py | head -1); python3 -m py_compile "$LTD"; pkill -f ltd_paper.py || true; sleep 2
for k in /root/pe-xg/keepalive_ltd.sh /root/pe-ltd/keepalive.sh; do [ -x "$k" ] && nohup "$k" >/dev/null 2>&1 & done; sleep 5; pgrep -af ltd_paper.py | head -1 || echo "ltd bot not running — keepalive path?"; crontab -l | grep -i ltd || true
echo "== 3. stream retention 3 days"
sed -i "s/('stream_ticks','ts_recv',30)/('stream_ticks','ts_recv',3)/" /root/pe-factory/retention.sh && grep -n stream_ticks /root/pe-factory/retention.sh
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("CREATE INDEX IF NOT EXISTS stream_ticks_mkt_ts ON stream_ticks (market_id, ts_recv)"); k.execute("CREATE INDEX IF NOT EXISTS stream_ticks_ts ON stream_ticks (ts_recv)")
k.execute("SELECT count(*), pg_size_pretty(pg_total_relation_size('stream_ticks')) FROM stream_ticks"); print("stream_ticks rows, size:",k.fetchone())
PY
echo "== 4. runner cap for re-polling jobs"
python3 - <<'PY'
p='/root/pe-queue/runner/runner.sh'; print("runner.sh is pulled from the repo — patched there (see commit), not here")
PY
