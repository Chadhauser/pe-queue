#!/bin/bash
# fin 006 (own runner): read-only — after the 19 Nov open: is the leftover IWM closed, did the fixed close work?
cd /root/pe-finq/repo/fin/bots && python3 - <<'PY'
import tick as T
T.H=T._creds()
for s in ('IWM','QQQ','SPY','QQQM'): print(s,'position qty',T.position_qty(s))
sc,o=T.api('GET','/orders',params={'status':'closed','after':'2026-11-19T14:00:00Z','symbols':'IWM','limit':50,'direction':'asc'})
print([(x['side'],x['filled_qty'],x['filled_avg_price'],x['status'],x['filled_at']) for x in o] if sc==200 else o)
PY
grep -E "^2026-11-19 (09|1[0-9])" /root/pe-finq/state/bots/bots.log | grep -v "404" | tail -20
python3 -c "import json;d=json.load(open('/root/pe-finq/state/bots/day_2026-11-19.json'));print({k:d.get(k) for k in ('done','stray','stray_ids','ORB_IWM')})"
