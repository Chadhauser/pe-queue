#!/bin/bash
# 281: DUKASCOPY DOWNLOAD AS A SERVER DAEMON (270 died on 28 Oct with a pyarrow abort and, being a run-once queue job, never restarted;
# four backtests have been polling "73 days" for two days). A multi-day fetch does not belong in the queue.
#  - duka_daemon.py: same v3 logic, no wall-clock deadline, run under nohup with a @reboot cron and a 5-min keepalive
#  - purge step uses pyarrow directly (the pandas->pyarrow abort was in the purge, not the fetch)
#  - progress -> /root/pe-fin/duka_daemon.log and a one-line status file /root/pe-data/duka/STATUS the backtests and I can read
set -e; cd /root/pe-fin
python3 - <<'PY'
import os, pyarrow.parquet as pq
base='/root/pe-data/duka'
for sym in sorted(os.listdir(base)):
    d=f"{base}/{sym}"; purged=kept=0
    for f in sorted(os.listdir(d)):
        if not f.startswith('day_'): continue
        try: n=pq.read_metadata(f"{d}/{f}").num_rows
        except Exception: n=-1
        if n<1000: os.remove(f"{d}/{f}"); purged+=1
        else: kept+=1
    print(f"{sym}: complete days kept {kept} | removed {purged}")
PY
cat > duka_daemon.py <<'PYFILE'
import sys, os, lzma, time, datetime, urllib.request, urllib.error, numpy as np, pandas as pd
from concurrent.futures import ThreadPoolExecutor
STATUS={}; slow_until=None
SYMS={'USATECHIDXUSD':1000.0,'EURUSD':1e5,'GBPUSD':1e5}
BASE='/root/pe-data/duka'; UA={'User-Agent':'Mozilla/5.0'}; DEADLINE=time.time()+10**9
end=datetime.date.today()-datetime.timedelta(days=1); start=end-datetime.timedelta(days=730)
def fetch(sym,d,h):
    url=f"https://datafeed.dukascopy.com/datafeed/{sym}/{d.year}/{d.month-1:02d}/{d.day:02d}/{h:02d}h_ticks.bi5"
    for attempt in range(3):
        try:
            raw=urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=10).read()
            if not raw: return None
            data=lzma.decompress(raw); n=len(data)//20
            if n==0: return None
            a=np.frombuffer(data[:n*20],dtype=np.dtype('>i4,>i4,>i4,>f4,>f4'))
            base=pd.Timestamp(d.year,d.month,d.day,h,tz='UTC')
            return pd.DataFrame({'ts':base+pd.to_timedelta(a['f0'],unit='ms'),'ask':a['f1'].astype(float),'bid':a['f2'].astype(float)})
        except urllib.error.HTTPError as e:
            STATUS[e.code]=STATUS.get(e.code,0)+1
            if e.code==404: return None
            time.sleep(1+attempt)
        except Exception: time.sleep(1)
    return 'ERR'
unfinished=False
for sym,div in SYMS.items():
    os.makedirs(f"{BASE}/{sym}",exist_ok=True); d=start; done=0; new=0; errs=0
    while d<=end:
        out=f"{BASE}/{sym}/day_{d:%Y%m%d}.parquet"
        if d.weekday()==5 or os.path.exists(out): done+=1; d+=datetime.timedelta(days=1); continue
        if time.time()>DEADLINE: unfinished=True; break
        slow = slow_until is not None and d<=slow_until
        if slow:
            res=[]
            for h in range(24): res.append(fetch(sym,d,h)); time.sleep(0.4)
        else:
            with ThreadPoolExecutor(4) as ex: res=list(ex.map(lambda h:fetch(sym,d,h),range(24)))
        n_err=sum(1 for r in res if isinstance(r,str)); errs+=n_err
        if n_err and not slow: slow_until=d+datetime.timedelta(days=30); print(f"throttled on {d} ({n_err} hours): 1 worker/0.4s until {slow_until}",flush=True)
        if n_err:                      # COMPLETENESS RULE: never save a day with a missing hour — leave it for the next cycle
            time.sleep(2+min(n_err,10)); d+=datetime.timedelta(days=1); continue
        frames=[r for r in res if isinstance(r,pd.DataFrame)]
        if frames:
            t=pd.concat(frames); t['mid']=(t.ask+t.bid)/2/div; t['spread']=(t.ask-t.bid)/div; t=t.set_index('ts').sort_index()
            b=t.mid.resample('1min').ohlc().dropna(); b['spread']=t.spread.resample('1min').mean().reindex(b.index); b['ticks']=t.mid.resample('1min').count().reindex(b.index)
            if sym=='USATECHIDXUSD': assert 10000<b.close.iloc[-1]<40000, f"divisor wrong? NQ mid {b.close.iloc[-1]}"
            b.to_parquet(out); new+=1
        else:
            pd.DataFrame(columns=['open','high','low','close','spread','ticks']).to_parquet(out)   # all 24 hours 404 = holiday
        done+=1
        if new and new%5==0: print(f"{sym} {d} bars={len(b) if frames else 0} spread={b.spread.mean():.3f} new_days={new} errs={errs}",flush=True)
        d+=datetime.timedelta(days=1)
    files=sorted(f for f in os.listdir(f"{BASE}/{sym}") if f.startswith('day_'))
    nonempty=[f for f in files if len(pd.read_parquet(f"{BASE}/{sym}/{f}"))>0]
    print("HTTP status counts:",STATUS)
    print(f"== {sym}: days on disk {len(files)} (with data {len(nonempty)}) of ~{(end-start).days*6//7} | new this run {new} | fetch errors {errs}",flush=True)
    if unfinished: break
print('cycle complete; unfinished=',unfinished,flush=True)
PYFILE
# wrap: run forever, re-scan every 30 min once a pass completes
cat > duka_loop.sh <<'SH'
#!/bin/bash
cd /root/pe-fin
while true; do
  python3 duka_daemon.py >> duka_daemon.log 2>&1
  python3 - <<'PY'
import os,json,datetime,pyarrow.parquet as pq
base='/root/pe-data/duka'; out={}
for sym in os.listdir(base):
    d=f"{base}/{sym}"; out[sym]=sum(1 for f in os.listdir(d) if f.startswith('day_') and pq.read_metadata(f"{d}/{f}").num_rows>=1000)
open(f"{base}/STATUS",'w').write(json.dumps({'ts':datetime.datetime.utcnow().isoformat(),'complete_days':out}))
PY
  sleep 1800
done
SH
chmod +x duka_loop.sh
python3 -m py_compile duka_daemon.py
pkill -f duka_loop.sh || true; pkill -f duka_daemon.py || true; sleep 2
nohup ./duka_loop.sh > /dev/null 2>&1 &
( crontab -l 2>/dev/null | grep -v duka_loop; echo "@reboot cd /root/pe-fin && nohup ./duka_loop.sh > /dev/null 2>&1 &"; echo "*/5 * * * * pgrep -f duka_loop.sh > /dev/null || (cd /root/pe-fin && nohup ./duka_loop.sh > /dev/null 2>&1 &)" ) | crontab -
sleep 90; pgrep -af duka_daemon.py | head -1; tail -5 duka_daemon.log; cat /root/pe-data/duka/STATUS 2>/dev/null; echo; echo "281 done — daemon running"
