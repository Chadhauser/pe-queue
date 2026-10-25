#!/bin/bash
# 223: FINANCIAL LINE — step 1 of the 25 Oct brief.
#  A) engine health: row counts + last run_date of v4_fin_results / v4_fin_xsmom / v4_intraday / robustness_results.
#  B) synthetic leak test: fin_sweep.py --synthetic must still give ~0 survivors at t>=3.5 (if random walks pass, the engine leaks).
#  C) intraday data probe (step 2a of the brief — change the data, not the indicators):
#     C1 yfinance 1h bars, 730 days, for ES/NQ/GC/CL/EURUSD/GBPUSD — bars, date range, biggest gap, % bars with volume.
#     C2 Dukascopy public bi5 tick file (no key) for one hour of EURUSD — HTTP status, bytes, decoded tick count.
#  Nothing is written to the DB. Output only.
cd /root/pe-factory/v4 || { echo "no v4 dir"; exit 1; }
echo "== A) engine health"; date -u
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
for t,datecol in (('v4_fin_results','run_date'),('v4_fin_xsmom','run_date'),('v4_intraday',None),('robustness_results',None)):
    try:
        c.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name='{t}'"); cols=[r[0] for r in c.fetchall()]
        if not cols: print(t,": MISSING"); continue
        dc=datecol or next((x for x in cols if 'date' in x or x in ('ts','run_ts','created_at')),None)
        if dc: c.execute(f"SELECT count(*), max({dc}), min({dc}) FROM {t}")
        else: c.execute(f"SELECT count(*), NULL, NULL FROM {t}")
        print(t,": rows/max/min =",c.fetchone(),"| cols:",cols[:12])
    except Exception as e: print(t,": ERR",repr(e)[:120])
c.execute("SELECT count(*) FILTER (WHERE oos_t>=3.5 AND is_sharpe>0), count(*) FROM v4_fin_results WHERE run_date=(SELECT max(run_date) FROM v4_fin_results)"); print("v4_fin_results latest run: survivors t>=3.5 / cells =",c.fetchone())
PY
echo; echo "== B) synthetic leak test (expect survivors at t>=3.5 ~ chance, i.e. 0-1)"
[ -f fin_sweep.py ] || { echo "fin_sweep.py missing"; exit 1; }
timeout 1700 python3 fin_sweep.py --synthetic 2>&1 | grep -v Warning | sed -n 1,10p
echo; echo "== C1) yfinance 1h intraday probe (730d)"
timeout 600 python3 - <<'PY'
import warnings; warnings.filterwarnings('ignore')
import yfinance as yf, pandas as pd
for t in ('ES=F','NQ=F','GC=F','CL=F','EURUSD=X','GBPUSD=X','^GDAXI'):
    try:
        df=yf.download(t,period='730d',interval='1h',progress=False,auto_adjust=True,threads=False)
        if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
        df=df.dropna(subset=['Close'])
        if not len(df): print(t,"EMPTY"); continue
        gaps=df.index.to_series().diff().dropna(); big=gaps.max(); vol=(df.Volume>0).mean() if 'Volume' in df else float('nan')
        hours=pd.Series(df.index.hour).value_counts().sort_index()
        print(f"{t}: bars={len(df)} {df.index[0]} -> {df.index[-1]} tz={df.index.tz} max_gap={big} vol>0={vol:.2f} hours_covered={len(hours)}")
    except Exception as e: print(t,"ERR",repr(e)[:100])
PY
echo; echo "== C2) Dukascopy bi5 probe: EURUSD 2024-06-03 10:00 UTC (public URL, no key)"
timeout 120 python3 - <<'PY'
import urllib.request, lzma, struct
url="https://datafeed.dukascopy.com/datafeed/EURUSD/2024/05/03/10h_ticks.bi5"   # month is 0-based: 05 = June
req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
try:
    r=urllib.request.urlopen(req,timeout=60); raw=r.read(); print("HTTP",r.status,"bytes",len(raw))
    data=lzma.decompress(raw); n=len(data)//20; print("ticks decoded:",n)
    for i in range(min(3,n)):
        ms,ask,bid,av,bv=struct.unpack('>3i2f',data[i*20:(i+1)*20]); print(f"  +{ms}ms ask={ask/1e5:.5f} bid={bid/1e5:.5f}")
except Exception as e: print("Dukascopy ERR",repr(e)[:160])
PY
echo "== done 223"
