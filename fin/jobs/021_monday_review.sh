#!/bin/bash
# fin 021 (own runner): read-only review of Monday 23 Nov. (a) why the gap fade placed nothing; (b) the nine closed five-day-bounce
# trades name by name; (c) the opening break replayed from minute bars for every live day, next to what the robot actually got.
cd /root/pe-finq/repo/fin/bots || exit 1
grep -E "^2026-11-23 09:3" /root/pe-finq/state/bots/bots.log | grep -v "404" | cut -c1-300 | head -20
python3 - <<'PY' 2>&1 | grep -v -i warning
import json, os, datetime as dt, time, tick as T
T.H = T._creds(); st = json.load(open(os.path.join(T.BOTS, 'day_2026-11-23.json')))
print('K2 state 23 Nov:', {k: v for k, v in st.get('K2', {}).items() if k != 'legs'}, 'legs', len(st.get('K2', {}).get('legs', [])), [(l['sym'], l['side'], l['status']) for l in st.get('K2', {}).get('legs', [])][:30])
print('done list:', st.get('done'))
uni, ed = T.universe(); t0 = time.time(); G = T.official_gaps(uni, dt.date(2026, 11, 23)); print('official opens now for 23 Nov:', len(G), 'in %.0fs' % (time.time() - t0))
big = sorted(((s, round(o / p - 1, 3)) for s, (o, p) in G.items() if abs(o / p - 1) >= 0.05 and o >= 3), key=lambda x: -abs(x[1])); print('names that gapped 5%+ on 23 Nov:', len(big), big[:30])
b = json.load(open(os.path.join(T.BOTS, 'k4_book.json'))); print('K4 open', len(b['open']), 'closed', len(b['closed']))
for p in b['closed']: print('  K4', p['sym'], p['date'], '->', p.get('exit_date'), 'qty', p['qty'], 'ref', p.get('ref'), 'r5', p.get('r5'), 'pnl', p.get('pnl_usd'))
b7 = json.load(open(os.path.join(T.BOTS, 'k7_book.json'))); print('K7 open', [(p['sym'], p['qty'], p['ref'], p['r20']) for p in b7['open']])
for s in ('QQQ', 'SPY', 'IWM', 'QQQM'): print(s, 'position', T.position_qty(s))
sc, a = T.api('GET', '/account'); print('equity', a.get('equity'))
# opening break replay from minute bars (same logic as the history test)
NY = T.NY
for day in ('2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20', '2026-11-23'):
    d = dt.date.fromisoformat(day); op = dt.datetime.combine(d, dt.time(9, 30), tzinfo=NY); out = []
    for sym, key in (('QQQ', 'ORB'), ('SPY', 'ORB_SPY'), ('IWM', 'ORB_IWM')):
        j = T.data_get('/stocks/bars', symbols=sym, timeframe='1Min', start=op.isoformat(), end=(op + dt.timedelta(minutes=390)).isoformat(), feed='iex', limit=1000); b = (j.get('bars') or {}).get(sym) or []
        fb = b[:5]; rest = b[5:]
        if len(fb) < 3 or not rest: out.append(f'{sym} no bars'); continue
        o, c = fb[0]['o'], fb[-1]['c']; hi = max(x['h'] for x in fb); lo = min(x['l'] for x in fb); side = 1 if c > o else -1; entry = rest[0]['o']; stop = lo if side > 0 else hi; R = abs(entry - stop)
        ex = rest[-1]['c']; why = 'close'; mfe = 0
        for x in rest:
            mfe = max(mfe, side * ((x['h'] if side > 0 else x['l']) - entry) / R)
            if (side > 0 and x['l'] <= stop) or (side < 0 and x['h'] >= stop): ex = stop; why = 'stop at ' + x['t'][11:16] + 'Z'; break
        live = json.load(open(os.path.join(T.BOTS, f'day_{day}.json'))); lv = live.get('settle', {}).get(key, {}).get('pnl_usd'); lk = live.get(key, {})
        out.append(f"{sym} {'buy' if side > 0 else 'sell'} test {side * (ex - entry) / R:+.2f}R ({why}, best it reached {mfe:+.1f}R) | live {lk.get('side')} {lv}")
    print(day, ' || '.join(out))
PY
