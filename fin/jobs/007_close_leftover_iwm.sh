#!/bin/bash
# fin 007 (own runner): 19 Nov the open-time close of the 88 leftover IWM shares failed (the retry cancelled its own closing order
# before it filled). tick.py is fixed in the same push (29/29 offline). Close the 88 now, mark the closing order as stray so it is
# never counted, and show proof. Paper account only. Fin state only. Only acts if the IWM position is exactly the 88 leftover.
cd /root/pe-finq/repo/fin/bots || exit 1
echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)"
python3 - <<'PY'
import json, os, fcntl, time, tick as T
T.H = T._creds()
lk = open(os.path.join(T.BOTS, 'tick.lock'), 'w')
for _ in range(90):
    try: fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB); break
    except OSError: time.sleep(2)
else: raise SystemExit('could not take the tick lock')
q = T.position_qty('IWM'); print('IWM before', q)
if q == 88:
    ids = T.flatten('IWM'); print('closing order ids', ids)
    p = os.path.join(T.BOTS, f'day_{T.now().date()}.json'); d = json.load(open(p))
    d.setdefault('stray_ids', []).extend(ids); json.dump(d, open(p, 'w')); print('stray_ids now', d['stray_ids'])
    for i in ids:
        sc, o = T.api('GET', f'/orders/{i}'); print('order', o.get('side'), o.get('filled_qty'), o.get('filled_avg_price'), o.get('status'), o.get('filled_at'))
else: print('not the 88 leftover: left alone')
for s in ('IWM', 'QQQ', 'SPY', 'QQQM'): print(s, 'position qty', T.position_qty(s))
PY
