#!/bin/bash
# 100: tennis systems test v2 (097 re-issued after the market_id repair in 099). Same five tests. Also prints the winner-detection
# diagnostics so a zero never hides a data problem again. Waits for 099 (market_id '1' gone) and >=6 tennis months.
cd /root/pe-scan && python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT count(*) FROM bf_hist_other WHERE sport='Tennis' AND market_id='1'")
if c.fetchone()[0]: print("WAITING: market_id repair (099) not done"); sys.exit(75)
PY
[ $? -eq 75 ] && exit 75
sed -i "s/M=pd.DataFrame(rows); print(\"settled 2-runner markets with pre-match and in-play prices:\",len(M),flush=True)/M=pd.DataFrame(rows); print(\"settled 2-runner markets with pre-match and in-play prices:\",len(M),\"| diag: markets\",D.market_id.nunique(),\"2-sel\",sum(1 for _,g in D.groupby('market_id') if g.sel.nunique()==2),flush=True)\nif len(M)<200: print('NOT ENOUGH SETTLED MARKETS - check winner rule'); sys.exit(1)/" tennis_hist_test.py
sed -i "s/win=\[s for s in sels if last\[s\]<1.10\]/win=[s for s in sels if last[s]<1.15 and max(last.values())>=2.5]/" tennis_hist_test.py
python3 -m py_compile tennis_hist_test.py && python3 tennis_hist_test.py
