#!/bin/bash
# fin 019 (own runner): (a) backfill the gap-fade sells/buys split for 17-20 Nov from the broker's own fills (fin state only);
# (b) proof the new five-day short rule can find its shares on the box: selection only for Friday 20 Nov, NO orders.
cd /root/pe-finq/repo/fin/bots || exit 1
echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)"
python3 - <<'PY' 2>&1 | grep -v -i warning
import json, os, fcntl, time, datetime as dt, tick as T
T.H = T._creds(); lk = open(os.path.join(T.BOTS, 'tick.lock'), 'w')
for _ in range(90):
    try: fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB); break
    except OSError: time.sleep(2)
for day in ('2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20'):
    p = os.path.join(T.BOTS, f'day_{day}.json'); st = json.load(open(p)); legs = [l for l in st.get('K2', {}).get('legs', []) if l.get('status', 999) < 300]
    sc, od = T.api('GET', '/orders', params={'status': 'closed', 'after': f'{day}T13:00:00Z', 'until': f'{day}T22:00:00Z', 'limit': 500, 'direction': 'asc'})
    out = {}
    for sd in ('sell', 'buy'):
        ks = {l['sym'] for l in legs if l['side'] == sd}; pnl = 0.0; nf = 0; net = {}
        for o in od:
            if o['symbol'] in ks and o.get('filled_avg_price') and float(o['filled_qty']) > 0:
                q = float(o['filled_qty']); pnl += q * float(o['filled_avg_price']) * (1 if o['side'] == 'sell' else -1); nf += 1; net[o['symbol']] = net.get(o['symbol'], 0) + (q if o['side'] == 'buy' else -q)
        assert all(abs(v) < 1e-6 for v in net.values()), (day, sd, net)
        out[f'K2_{sd}'] = {'pnl_usd': round(pnl, 2) if nf else None, 'fills': nf, 'n': len(ks)}
    tot = round(sum(v['pnl_usd'] or 0 for v in out.values()), 2); print(day, out, '| sides total', tot, 'board', st['settle']['K2']['pnl_usd'], 'MATCH' if abs(tot - st['settle']['K2']['pnl_usd']) < 0.02 else 'MISMATCH')
    if abs(tot - st['settle']['K2']['pnl_usd']) < 0.02: st['settle'].update(out); json.dump(st, open(p, 'w'))
T.summary(); print(open(os.path.join(T.BOTS, 'bots.md')).read()[:1400])
uni, ed = T.universe(); t0 = time.time(); c = T.k7_candidates(uni, dt.date(2026, 11, 20)); A = T.assets()
pick = sorted([x for x in c if x[1] >= 0.25 and x[2] >= 30e6 and x[3] >= 3 and all(T.can(A, x[0]))], key=lambda x: -x[1])
print('K7 check: daily history for', len(c), 'of', len(uni), 'shares in %.0fs | qualifying on 20 Nov:' % (time.time() - t0), len(pick), [(s, round(r, 2), round(dv / 1e6)) for s, r, dv, px in pick[:12]])
PY
