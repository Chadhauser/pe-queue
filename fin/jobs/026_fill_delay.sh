#!/bin/bash
# fin 026 (own runner): read-only — for every opening-break entry so far: when the order was sent, when the broker filled it, and what
# the delay cost in units of planned risk; same timing for gap-fade entries. No orders.
cd /root/pe-finq/repo/fin/bots || exit 1
python3 - <<'PY' 2>&1 | grep -v -i warning
import json, os, glob, datetime as dt, tick as T
T.H = T._creds(); tot = []; P = lambda s: dt.datetime.fromisoformat(s.replace('Z', '+00:00')[:26].rstrip('0').ljust(20, '0') + ('+00:00' if '+' not in s[10:] else '')) if s else None
def ts(s):
    if not s: return None
    s = s.replace('Z', ''); s = s[:26]; return dt.datetime.fromisoformat(s)
for f in sorted(glob.glob(os.path.join(T.BOTS, 'day_2026-11-*.json'))):
    st = json.load(open(f)); day = st['date']
    for key in ('ORB', 'ORB_SPY', 'ORB_IWM'):
        k = st.get(key, {}); oid = k.get('order_id')
        if not oid: continue
        sc, o = T.api('GET', f'/orders/{oid}')
        if sc != 200 or not o.get('filled_avg_price'): continue
        sgn = 1 if k['side'] == 'buy' else -1; fill = float(o['filled_avg_price']); slip = sgn * (fill - k['ref']) / k['R']; d = (ts(o['filled_at']) - ts(o['submitted_at'])).total_seconds()
        riskR = abs(fill - k['stop']) / k['R']; pnl = st.get('settle', {}).get(key, {}).get('pnl_usd')
        tot.append((slip, d, riskR)); print(day, key.ljust(8), k['side'].ljust(4), 'sent', o['submitted_at'][11:19], 'filled', o['filled_at'][11:19], 'delay %4.0fs' % d, '| planned', k['ref'], 'got', round(fill, 3), '| cost %+.2f of planned risk' % slip, '| risk actually taken %.2fx' % riskR, '| result $', pnl)
    legs = [l for l in st.get('K2', {}).get('legs', []) if l.get('status', 999) < 300][:4]
    if legs:
        sc, od = T.api('GET', '/orders', params={'status': 'closed', 'after': f'{day}T13:00:00Z', 'until': f'{day}T15:00:00Z', 'limit': 500, 'direction': 'asc'})
        ds = [(ts(o['filled_at']) - ts(o['submitted_at'])).total_seconds() for o in (od if sc == 200 else []) if (o.get('client_order_id') or '').startswith('k2-') and o.get('filled_at')]
        if ds: print(day, 'gap-fade entries:', len(ds), 'median delay %.0fs' % sorted(ds)[len(ds) // 2], 'max %.0fs' % max(ds))
n = len(tot); print('\nopening break entries', n, '| average cost of the delay %+.2f of planned risk a trade | median delay %.0fs | average risk actually taken %.2fx planned' % (sum(x[0] for x in tot) / n, sorted(x[1] for x in tot)[n // 2], sum(x[2] for x in tot) / n))
PY
