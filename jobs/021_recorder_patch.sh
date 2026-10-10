#!/bin/bash
# 021: liquidity recorder patch. Overnight log showed HTTP 400 on listMarketBook when many markets were live: EX_ALL_OFFERS
# weighs 17 per market, 20 markets = 340 > Betfair's 200 limit. Batches of 10 (=170). Also heartbeat while idle.
f=/root/pe-liq/liq_recorder.py
sed -i 's/range(0,len(ids),20)/range(0,len(ids),10)/; s/ids\[i:i+20\]/ids[i:i+10]/' $f
python3 - <<'PY'
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
s=s.replace("        if not ids: time.sleep(20); continue","        if not ids:\n            cur.execute(\"INSERT INTO liq_heartbeat (id,last_seen,live_markets,goals_seen) VALUES (1,NOW(),0,%s) ON CONFLICT (id) DO UPDATE SET last_seen=NOW(), live_markets=0, goals_seen=EXCLUDED.goals_seen\",(goals,))\n            time.sleep(20); continue")
open(p,'w').write(s)
PY
python3 -m py_compile $f || exit 1
grep -n "range(0,len(ids)" $f
pkill -f liq_recorder.py; sleep 2; echo "recorder restarted by cron within 60s"; tail -3 /root/pe-liq/recorder.log
