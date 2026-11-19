#!/bin/bash
# fin 003 (own runner): 18 Nov the IWM ORB close was refused (403, shares held by the bracket legs), the 88 shares stayed open
# overnight and settle booked -$23,698.40 (the cost of the shares, not a loss). Void that row; show the position; the fixed tick
# closes the leftover at today's open (stray_flat) and never counts it. Paper account only. Touches fin state only.
cd /root/pe-finq/repo/fin/bots || exit 1
echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)"
python3 - <<'PY'
import json, os, tick as T
T.H = T._creds()
p = os.path.join(T.BOTS, 'day_2026-11-18.json'); d = json.load(open(p))
print('before:', d.get('settle', {}).get('ORB_IWM'))
d['settle']['ORB_IWM'] = {'pnl_usd': None, 'fills': 0, 'note': 'VOID: close refused 403, held overnight; not a rule trade'}
json.dump(d, open(p, 'w')); print('after:', d['settle']['ORB_IWM'])
for s in ('IWM', 'QQQ', 'SPY', 'QQQM'): print(s, 'position qty', T.position_qty(s))
sc, o = T.api('GET', '/orders', params={'status': 'open', 'limit': 100}); print('open orders:', [(x['symbol'], x['side'], x['type'], x['qty']) for x in o] if sc == 200 else o)
sc, a = T.api('GET', '/account'); print('equity', a.get('equity'), 'last_equity', a.get('last_equity'))
T.summary(); print(open(os.path.join(T.BOTS, 'bots.md')).read())
PY
