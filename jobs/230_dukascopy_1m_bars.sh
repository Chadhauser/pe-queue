#!/bin/bash
# 230: FINANCIAL — free intraday history. Dukascopy public bi5 tick files (proven in 223: HTTP 200, 2,693 ticks for one hour of EURUSD)
# downloaded hour by hour for USATECHIDXUSD (Nasdaq-100 CFD = NQ proxy for JJ Simon's rule), EURUSD, GBPUSD; built into 1-minute
# OHLC bars (bid/ask mid, plus mean spread) and stored as parquet under /root/pe-data/duka/<SYM>/1m_<YYYY-MM>.parquet.
# Resumable: skips any month already on disk. 2 years back from last full month. Rate-limited (0.15s/hour-file) and tolerant of 404s
# (weekends/holidays). Prints per-symbol: months done, bars, date range, mean spread in points — the number that sets the cost table.
# Nothing written to the DB. Reads ~17,500 small files per symbol so this runs long; exit 75 = not finished, runner re-polls next cycle.
mkdir -p /root/pe-data/duka /root/pe-fin && cd /root/pe-fin
pip install -q pyarrow --break-system-packages 2>&1 | tail -1
cat > duka_1m.py <<'PYFILE'
import sys, os, io, lzma, struct, time, datetime, urllib.request, numpy as np, pandas as pd
SYMS={'USATECHIDXUSD':1000.0,'EURUSD':1e5,'GBPUSD':1e5}   # price divisor per Dukascopy point convention (indices 1000, FX 1e5)
BASE='/root/pe-data/duka'; UA={'User-Agent':'Mozilla/5.0'}
today=datetime.date.today(); first=(today.replace(day=1)-datetime.timedelta(days=1)).replace(day=1)  # last full month
months=[]; m=first
for _ in range(24): months.append(m); m=(m-datetime.timedelta(days=1)).replace(day=1)
def fetch_hour(sym,d,h):
    url=f"https://datafeed.dukascopy.com/datafeed/{sym}/{d.year}/{d.month-1:02d}/{d.day:02d}/{h:02d}h_ticks.bi5"
    try:
        r=urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=30); raw=r.read()
        if not raw: return None
        data=lzma.decompress(raw); n=len(data)//20
        a=np.frombuffer(data[:n*20],dtype=np.dtype('>i4,>i4,>i4,>f4,>f4'))
        base=pd.Timestamp(d.year,d.month,d.day,h,tz='UTC')
        return pd.DataFrame({'ts':base+pd.to_timedelta(a['f0'],unit='ms'),'ask':a['f1'],'bid':a['f2']})
    except urllib.error.HTTPError as e:
        return None if e.code==404 else 'ERR'
    except Exception: return 'ERR'
budget=time.time()+3300; unfinished=False
for sym,div in SYMS.items():
    os.makedirs(f"{BASE}/{sym}",exist_ok=True); done=0; errs=0
    for m0 in months:
        out=f"{BASE}/{sym}/1m_{m0:%Y-%m}.parquet"
        if os.path.exists(out): done+=1; continue
        if time.time()>budget: unfinished=True; break
        m1=(m0.replace(day=28)+datetime.timedelta(days=4)).replace(day=1); frames=[]; d=m0
        while d<m1:
            for h in range(24):
                f=fetch_hour(sym,d,h)
                if isinstance(f,str): errs+=1
                elif f is not None and len(f): frames.append(f)
                time.sleep(0.15)
            d+=datetime.timedelta(days=1)
        if not frames: print(sym,m0,"no ticks"); continue
        t=pd.concat(frames); t['mid']=(t.ask+t.bid)/2/div; t['spread']=(t.ask-t.bid)/div; t=t.set_index('ts').sort_index()
        b=t.mid.resample('1min').ohlc().dropna(); b['spread']=t.spread.resample('1min').mean().reindex(b.index); b['ticks']=t.mid.resample('1min').count().reindex(b.index)
        b.to_parquet(out); done+=1; print(sym,m0.strftime('%Y-%m'),"bars",len(b),"spread",round(b.spread.mean(),3),"errs",errs,flush=True)
    files=sorted(os.listdir(f"{BASE}/{sym}"))
    if files:
        allb=pd.concat(pd.read_parquet(f"{BASE}/{sym}/{f}") for f in files)
        print(f"== {sym}: months {len(files)}/24 | bars {len(allb)} | {allb.index[0]} -> {allb.index[-1]} | mean spread {allb.spread.mean():.3f} pts | NY 09:30-11:00 bars/day {(allb.index.tz_convert('America/New_York').hour.isin([9,10])).sum()/max(1,len(np.unique(allb.index.date))):.0f}")
sys.exit(75 if unfinished else 0)
PYFILE
python3 -m py_compile duka_1m.py || exit 1
timeout 3500 python3 duka_1m.py; rc=$?
echo "exit $rc (75 = more months to fetch, runner re-polls)"; exit $rc
