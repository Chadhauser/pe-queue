#!/bin/bash
# 215: report the survivorship-fixed price-only sweep (waits on 214's run).
pgrep -f sport_sweep.py >/dev/null && { echo "sweep still running"; tail -2 /root/pe-factory/v4/sport_sweep_214.log; exit 75; }
grep -v -E "UserWarning|pd.read_sql| processed|batch" /root/pe-factory/v4/sport_sweep_214.log | sed -n '/SURVIVORS/,$p' | head -120
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT * FROM v4_sport_results WHERE run_date=(SELECT max(run_date) FROM v4_sport_results) AND trig LIKE 'CLOCK%%' AND n>=200 ORDER BY t DESC LIMIT 20",c)
print("\n=== CLOCK cells after the fix (top 20 by t) ===\n",d.to_string(index=False))
e=pd.read_sql("SELECT * FROM v4_sport_results WHERE run_date=(SELECT max(run_date) FROM v4_sport_results) AND trig IN ('CLOCK60g0','CLOCK75g0','CLOCK46g0') AND role='draw' AND dir='lay' ORDER BY trig, exit, band",c)
print("\n=== the LTD cells specifically ===\n",e.to_string(index=False))
PY
