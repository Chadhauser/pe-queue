#!/bin/bash
# 240: fixes 230 (timed out at 3508s with nothing written; runner saw 124 not 75 so never re-polled).
#  - per-DAY parquet files (resumable at day level), 8 parallel fetches, 10s timeout per file, 2 retries
#  - progress line every day; stops cleanly at 50 min and exits 75 so the runner re-polls until all days are down
#  - NQ proxy (USATECHIDXUSD) first, then EURUSD, GBPUSD; 2 years back from yesterday; weekends skipped (Dukascopy has none)
#  - 231 (ORB) now reads /root/pe-data/duka/<SYM>/day_*.parquet; a tiny loader shim is written for it
mkdir -p /root/pe-data/duka /root/pe-fin && cd /root/pe-fin
cat > duka_1m.py <<'PYFILE'
import sys, os, lzma, time, datetime, urllib.request, urllib.error, numpy as np, pandas as pd
from concurrent.futures import ThreadPoolExecutor
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
            if e.code==404: return None
            time.sleep(1)
        except Exception: time.sleep(1)
    return 'ERR'
unfinished=False
for sym,div in SYMS.items():
    os.makedirs(f"{BASE}/{sym}",exist_ok=True); d=start; done=0; new=0; errs=0
    while d<=end:
        out=f"{BASE}/{sym}/day_{d:%Y%m%d}.parquet"
        if d.weekday()==5 or os.path.exists(out): done+=1; d+=datetime.timedelta(days=1); continue
        if time.time()>DEADLINE: unfinished=True; break
        with ThreadPoolExecutor(8) as ex: res=list(ex.map(lambda h:fetch(sym,d,h),range(24)))
        frames=[r for r in res if isinstance(r,pd.DataFrame)]; errs+=sum(1 for r in res if isinstance(r,str))
        if frames:
            t=pd.concat(frames); t['mid']=(t.ask+t.bid)/2/div; t['spread']=(t.ask-t.bid)/div; t=t.set_index('ts').sort_index()
            b=t.mid.resample('1min').ohlc().dropna(); b['spread']=t.spread.resample('1min').mean().reindex(b.index); b['ticks']=t.mid.resample('1min').count().reindex(b.index)
            b.to_parquet(out); new+=1
        else:
            pd.DataFrame(columns=['open','high','low','close','spread','ticks']).to_parquet(out)   # empty marker = holiday / no data, not refetched
        done+=1
        if new and new%5==0: print(f"{sym} {d} bars={len(b) if frames else 0} spread={b.spread.mean():.3f} new_days={new} errs={errs}",flush=True)
        d+=datetime.timedelta(days=1)
    files=sorted(f for f in os.listdir(f"{BASE}/{sym}") if f.startswith('day_'))
    nonempty=[f for f in files if os.path.getsize(f"{BASE}/{sym}/{f}")>2000]
    print(f"== {sym}: days on disk {len(files)} (with data {len(nonempty)}) of ~{(end-start).days*6//7} | new this run {new} | fetch errors {errs}",flush=True)
    if unfinished: break
sys.exit(75 if unfinished else 0)
PYFILE
cat > duka_load.py <<'PYFILE'
import os, pandas as pd
def load(sym,base='/root/pe-data/duka'):
    d=f"{base}/{sym}"; fs=sorted(f for f in os.listdir(d) if f.startswith('day_') and os.path.getsize(f"{d}/{f}")>2000) if os.path.isdir(d) else []
    if not fs: return pd.DataFrame()
    b=pd.concat(pd.read_parquet(f"{d}/{f}") for f in fs).sort_index(); return b[~b.index.duplicated()]
PYFILE
python3 -m py_compile duka_1m.py duka_load.py || exit 1
timeout 3300 python3 duka_1m.py; rc=$?
[ $rc -eq 124 ] && rc=75
echo "exit $rc (75 = resume next cycle)"; exit $rc
