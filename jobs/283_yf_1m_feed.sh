#!/bin/bash
# 283: FREE 1-MINUTE FEED, FORWARD FROM TODAY. yfinance serves the last 7 days of 1-minute bars with no throttle; a daily pull that
# appends to parquet gives a growing 1m history for NQ/ES/GC/CL and becomes the live feed any bot runs on. Cron 23:50 UTC daily.
mkdir -p /root/pe-data/yf1m /root/pe-fin && cd /root/pe-fin
cat > yf1m_collect.py <<'PYFILE'
import os, warnings, pandas as pd, yfinance as yf
warnings.filterwarnings('ignore'); BASE='/root/pe-data/yf1m'
for tk in ('NQ=F','ES=F','GC=F','CL=F','EURUSD=X','GBPUSD=X'):
    df=yf.download(tk,period='7d',interval='1m',progress=False,auto_adjust=False,threads=False)
    if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
    df=df.dropna(subset=['Close']); df.index=pd.to_datetime(df.index,utc=True)
    p=f"{BASE}/{tk.replace('=','_')}.parquet"
    if os.path.exists(p): old=pd.read_parquet(p); df=pd.concat([old,df]); df=df[~df.index.duplicated(keep='last')].sort_index()
    df.to_parquet(p); print(tk,"bars",len(df),df.index[0],"->",df.index[-1])
PYFILE
python3 -m py_compile yf1m_collect.py && python3 yf1m_collect.py
( crontab -l 2>/dev/null | grep -v yf1m_collect; echo "50 23 * * * cd /root/pe-fin && python3 yf1m_collect.py >> yf1m.log 2>&1" ) | crontab -
crontab -l | grep -c yf1m_collect && echo "283 done — 1m feed accumulating daily"
