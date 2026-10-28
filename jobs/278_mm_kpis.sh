#!/bin/bash
# 278: BOOK 1 KPIs — where does the racing market-maker earn and where does it get picked off? Per book: by minutes-to-off,
# spread at quote, price band, rank, venue. Capture rate, adverse rate, net ticks, P&L per £10-equivalent. This is the evidence
# for the desk rules (where to quote, where to stand aside). Re-runnable; nightly from tomorrow (03:50).
set -e
cat > /root/pe-race/mm_kpis.py <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT book, venue, quoted_ts, quoted_sto, spread_ticks, back_px::float back_px, rank, exit_reason, ticks::float ticks, pnl_per_10::float pnl FROM racing_mm_stream WHERE exit_reason IS NOT NULL",con)
if d.empty: print("no rounds yet"); sys.exit(0)
stake=d.book.map({'50through':50,'200through':200}).fillna(10); d['p10']=d.pnl*10/stake
d['cap']=(d.exit_reason=='CAPTURED').astype(int); d['adv']=d.exit_reason.isin(['STOP','FLAT_PRE_OFF']).astype(int)|d.exit_reason.str.startswith('MARKET_').astype(int)
d['sto_b']=pd.cut(d.quoted_sto,[0,60,120,240,480,10**6],labels=['<1m','1-2m','2-4m','4-8m','8m+'])
d['px_b']=pd.cut(d.back_px,[1,2,3,5,10,1000],labels=['1-2','2-3','3-5','5-10','10+'])
d['hour']=pd.to_datetime(d.quoted_ts).dt.hour
def tab(by):
    g=d.groupby(['book',by],observed=True).agg(rounds=('p10','size'),capture=('cap','mean'),adverse=('adv','mean'),net_ticks=('ticks','mean'),p10=('p10','mean')).round(3)
    print(f"\n== by {by}"); print(g.to_string())
for by in ['sto_b','spread_ticks','px_b','rank','hour','venue']: tab(by)
print("\n== totals"); print(d.groupby('book').agg(rounds=('p10','size'),capture=('cap','mean'),adverse=('adv','mean'),net_ticks=('ticks','mean'),p10_mean=('p10','mean'),p10_sum=('p10','sum')).round(3).to_string())
PY
python3 /root/pe-race/mm_kpis.py 2>&1 | grep -v Warning
( crontab -l 2>/dev/null | grep -v "pe-race/mm_kpis.py" ; echo "50 3 * * * python3 /root/pe-race/mm_kpis.py > /root/pe-race/mm_kpis.txt 2>&1" ) | crontab -
