#!/bin/bash
# fin 028 (own runner): read-only inventory of every price series on the box, for the financial league table.
echo "== alpaca minute dirs"; ls /root/pe-data/alpaca | tr '\n' ' '; echo; ls /root/pe-data/alpaca/BTCUSD | head -3; ls /root/pe-data/alpaca/BTCUSD | wc -l; ls /root/pe-data/alpaca | grep USD
echo "== oanda"; ls /root/pe-data/oanda | head -40; d=$(ls -d /root/pe-data/oanda/* | head -1); ls $d | head -5; ls $d | wc -l
echo "== yf1m / duka"; ls /root/pe-data/yf1m | head; ls /root/pe-data/duka | head
echo "== loaders"; sed -n 1,8p /root/pe-fin/team/mech2.py | cut -c1-300; grep -n "def load" -A 8 /root/pe-fin/team/mech2.py /root/pe-fin/*.py 2>/dev/null | cut -c1-260 | head -40
ls /root/pe-fin/*.py | head -30; grep -n "def \|read_parquet" /root/pe-fin/team/mech_crypto.py /root/pe-fin/team/mech_fx.py | cut -c1-220 | head -40
python3 - <<'PY' 2>&1 | grep -v -i warn
import pandas as pd, glob, os
for pat in ('/root/pe-data/alpaca/BTCUSD/*.parquet', '/root/pe-data/alpaca/SPY/*.parquet'):
    fs = sorted(glob.glob(pat)); d = pd.read_parquet(fs[-1]); print(pat, len(fs), fs[0][-18:], fs[-1][-18:], list(d.columns), d.index[:2].tolist(), len(d))
for root in ('/root/pe-data/oanda', '/root/pe-data/yf1m', '/root/pe-data/duka'):
    fs = sorted(glob.glob(root + '/**/*.parquet', recursive=True)) + sorted(glob.glob(root + '/**/*.csv', recursive=True))
    print(root, len(fs), fs[:2], fs[-1:] )
    if fs:
        try: d = pd.read_parquet(fs[-1]) if fs[-1].endswith('parquet') else pd.read_csv(fs[-1], nrows=5); print(list(d.columns), d.index[:2].tolist(), len(d)); print(d.tail(2))
        except Exception as e: print('ERR', e)
PY
free -g | head -2; nproc; df -h /root | tail -1
