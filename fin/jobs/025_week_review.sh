#!/bin/bash
# fin 025 (own runner): read-only review 24-25 Nov: opening-break fills against plan (two losses were about twice the planned risk),
# whether a trade was open at the close and was closed cleanly, five-day bounce win count. No orders.
cd /root/pe-finq/repo/fin/bots || exit 1
grep -E "^2026-11-24 (09:3|15:5[5-9]|16:0)" /root/pe-finq/state/bots/bots.log | grep -v "does not exist" | cut -c1-260
grep -c "FLATTEN FAILED" /root/pe-finq/state/bots/bots.log; grep "FLATTEN FAILED\|ERROR\|UNFLAT" /root/pe-finq/state/bots/bots.log | tail -5 | cut -c1-200
python3 - <<'PY' 2>&1 | grep -v -i warning
import json, os, tick as T
T.H = T._creds()
for day in ('2026-11-24', '2026-11-25'):
    st = json.load(open(os.path.join(T.BOTS, f'day_{day}.json')))
    sc, od = T.api('GET', '/orders', params={'status': 'closed', 'after': f'{day}T13:00:00Z', 'until': f'{day}T22:00:00Z', 'limit': 500, 'direction': 'asc', 'nested': 'true'})
    for key, sym in (('ORB', 'QQQ'), ('ORB_SPY', 'SPY'), ('ORB_IWM', 'IWM')):
        k = st.get(key, {}); print(day, key, {x: k.get(x) for x in ('side', 'qty', 'ref', 'stop', 'R', 'range')})
        def walk(os_, d=0):
            for o in os_:
                if o['symbol'] == sym: print('   ' + '  ' * d, o['side'], o['type'], 'qty', o['qty'], 'filled', o.get('filled_qty'), '@', o.get('filled_avg_price'), 'stop', o.get('stop_price'), 'limit', o.get('limit_price'), o['status'], (o.get('filled_at') or '')[11:19])
                walk(o.get('legs') or [], d + 1)
        walk(od)
b = json.load(open(os.path.join(T.BOTS, 'k4_book.json'))); c = [p for p in b['closed'] if p.get('pnl_usd') is not None]
print('K4 closed', len(c), 'wins', sum(1 for p in c if p['pnl_usd'] > 0), 'total', round(sum(p['pnl_usd'] for p in c), 2), 'avg r5 at entry', round(sum(p['r5'] for p in c) / len(c), 3), 'open', len(b['open']))
by = {}
for p in c: by.setdefault(p['date'], []).append(p['pnl_usd'])
print({d: (len(v), round(sum(v), 2), sum(1 for x in v if x > 0)) for d, v in by.items()})
sc, a = T.api('GET', '/account'); print('equity', a.get('equity')); sc, ps = T.api('GET', '/positions'); print('open positions', len(ps), 'intraday funds held:', [(p['symbol'], p['qty']) for p in ps if p['symbol'] in ('QQQ', 'SPY', 'IWM', 'QQQM')])
PY
