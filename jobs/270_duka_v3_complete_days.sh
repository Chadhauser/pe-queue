#!/bin/bash
# 270: Dukascopy downloader v3 (replaces 240/265/267 patches, which left holes: a day was saved even when hours were throttled, so
# 268 saw only 58 complete ORB sessions in 280 days). Rules: a day is saved only when all 24 hours returned clean; adaptive throttle
# (1 worker/0.4s for 30 days after any refusal); HTTP status logged; divisor sanity. Then PURGE every existing day file with <1000 bars
# (a complete NQ CFD day is ~1,380) so holed days are refetched. Fails loudly. Resumable (exit 75).
set -e; cd /root/pe-fin
cat > duka_1m.py <<'PYFILE'
import sys, os, lzma, time, datetime, urllib.request, urllib.error, numpy as np, pandas as pd
from concurrent.futures import ThreadPoolExecutor
STATUS={}; slow_until=None
SYMS={'USATECHIDXUSD':1000.0,'EURUSD':1e5,'GBPUSD':1e5}
BASE='/root/pe-data/duka'; UA={'User-Agent':'Mozilla/5.0'}; DEADLINE=time.time()+3000
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
sys.exit(75 if unfinished else 0)
PYFILE
python3 -m py_compile duka_1m.py
python3 - <<'PY'
import os, pandas as pd
base='/root/pe-data/duka'
for sym in sorted(os.listdir(base)):
    d=f"{base}/{sym}"; purged=0; kept=0
    for f in sorted(os.listdir(d)):
        if not f.startswith('day_'): continue
        n=len(pd.read_parquet(f"{d}/{f}"))
        if 0<n<1000: os.remove(f"{d}/{f}"); purged+=1
        elif n>0: kept+=1
    print(f"{sym}: complete days kept {kept} | holed days purged {purged}")
PY
set +e; timeout 3000 python3 duka_1m.py; rc=$?; [ $rc -eq 124 ] && rc=75; echo "exit $rc"; exit $rc
