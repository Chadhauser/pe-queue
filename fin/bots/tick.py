# FIN PAPER BOTS — one short "tick" per minute (cron), Alpaca PAPER endpoint only.
# Replaces the long-running bots (orb_alpaca_bot / k2 / k4) that waited for hours inside one process. Each tick looks at New York
# time and the Alpaca trading CALENDAR (handles DST and half days), runs whatever phase is due and not yet done today, saves state,
# and exits — normally within seconds, never more than ~60 s. Cron wraps it in nice/ionice/timeout.
# Strategies (symbols are kept disjoint so one account can hold them all without netting):
#   ORB  — QQQ  5-min opening range: candle direction 09:30-09:35, bracket stop at range edge, target 10R, $100 risk, flat 2 min before close
#   M7B  — signal on QQQ 09:30->15:00 move >= 1.5%  -> trade QQQM WITH it, $10,000 notional, 15:00 -> flat 1 min before close (16:00 days only)
#   K2   — small-cap overnight gap >= 5% faded at 09:31, $500/name, max 10, flat 5 min before close
#   K4   — small-cap down >= 15% over 5 trading days, bought 15:50, $500/name, max 10/day, sold on the 5th trading day
# Safety: PAPER endpoint hard-wired; no new entries if free disk < 25 GB or state/KILL exists (exits/flattens still run).
import os, sys, json, time, fcntl, datetime as dt, traceback, zoneinfo, shutil
import requests

NY = zoneinfo.ZoneInfo('America/New_York')
ROOT = os.environ.get('FINQ_STATE', '/root/pe-finq/state')
BOTS = os.path.join(ROOT, 'bots')
PAPER = 'https://paper-api.alpaca.markets/v2'          # PAPER ONLY. Never api.alpaca.markets.
DATA = 'https://data.alpaca.markets/v2'
CFG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config.json')
MIN_FREE_GB = 25

# ---------------------------------------------------------------- plumbing (replaced by fakes in the offline test)
def _creds():
    sys.path.insert(0, '/root/pe-queue/runner'); import creds
    E = creds.all_vars(); return {'APCA-API-KEY-ID': E.get('ALPACA_KEY', ''), 'APCA-API-SECRET-KEY': E.get('ALPACA_SECRET', '')}
H = None
def now(): return dt.datetime.now(NY)
def sleep(s): time.sleep(max(0.0, s))
def free_gb(): return shutil.disk_usage('/').free / 1e9
def log(m):
    os.makedirs(BOTS, exist_ok=True)
    line = f"{now():%Y-%m-%d %H:%M:%S} {m}"; print(line, flush=True)
    with open(os.path.join(BOTS, 'bots.log'), 'a') as f: f.write(line + "\n")
def api(method, path, **kw):
    r = requests.request(method, PAPER + path, headers=H, timeout=30, **kw)
    try: j = r.json()
    except Exception: j = r.text
    if r.status_code >= 300: log(f"{method} {path} -> {r.status_code} {str(j)[:160]}")
    return r.status_code, j
def data_get(path, **params):
    r = requests.get(DATA + path, headers=H, timeout=60, params=params)
    return r.json() if r.status_code == 200 else {}
def bars_1m(sym, start, end):
    j = data_get('/stocks/bars', symbols=sym, timeframe='1Min', start=start.isoformat(), end=end.isoformat(), feed='iex', limit=1000)
    return (j.get('bars') or {}).get(sym) or []
def snapshots(syms):
    out = {}
    for i in range(0, len(syms), 200):
        out.update(data_get('/stocks/snapshots', symbols=','.join(syms[i:i + 200]), feed='iex') or {})
    return out
def daily_closes(syms, today):
    import yfinance as yf
    d = yf.download(syms, period='15d', interval='1d', auto_adjust=False, progress=False, threads=True)['Close']
    return d[d.index.date < today]
def universe():
    import pandas as pd
    uni = list(pd.read_csv('/root/pe-data/crumbs/universe_small.csv', index_col=0).index)
    ed = jload('/root/pe-data/crumbs/earnings_dates.json', {})
    return uni, ed

# ---------------------------------------------------------------- helpers
def jload(p, d):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return d
def jsave(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True); tmp = p + '.tmp'
    with open(tmp, 'w') as f: json.dump(obj, f, indent=1)
    os.replace(tmp, p)
def cfg(): return jload(CFG_PATH, {'ORB': True, 'M7B': True, 'K2': True, 'K4': True})
def at(day, hh, mm, ss=0): return dt.datetime.combine(day, dt.time(hh, mm, ss), tzinfo=NY)
def calendar_day(day):
    """Alpaca calendar row for `day` (cached), or None if not a trading day."""
    cache = os.path.join(BOTS, 'calendar.json'); c = jload(cache, {})
    if str(day) not in c:
        sc, cal = api('GET', '/calendar', params={'start': str(day), 'end': str(day)})
        if sc != 200: return 'ERR'
        row = next((r for r in (cal or []) if r.get('date') == str(day)), None)
        c[str(day)] = row; jsave(cache, c)
    return c[str(day)]
def trading_days(a, b):
    """number of trading days in [a, b] inclusive"""
    sc, cal = api('GET', '/calendar', params={'start': str(a), 'end': str(b)})
    return len(cal) if sc == 200 else None
def due(t_now, target, until):
    """phase is due if target <= now < until; if target is within the next 55 s, wait for it (tick fires on the minute)."""
    if target - dt.timedelta(seconds=55) <= t_now < target: sleep((target - t_now).total_seconds()); return True
    return target <= t_now < until
def entries_allowed():
    if os.path.exists(os.path.join(ROOT, 'KILL')): log('KILL file present: no new entries'); return False
    g = free_gb()
    if g < MIN_FREE_GB: log(f'disk {g:.1f} GB free < {MIN_FREE_GB}: no new entries'); return False
    return True
def position_qty(sym):
    sc, p = api('GET', f'/positions/{sym}')
    return float(p.get('qty', 0)) if sc == 200 and isinstance(p, dict) else 0.0
def cancel_open(sym):
    sc, orders = api('GET', '/orders', params={'status': 'open', 'symbols': sym, 'nested': 'true', 'limit': 100})
    for o in (orders if sc == 200 and isinstance(orders, list) else []):
        api('DELETE', f"/orders/{o['id']}")
def flatten(sym):
    cancel_open(sym)
    if position_qty(sym) != 0: api('DELETE', f'/positions/{sym}'); return True
    return False

# ---------------------------------------------------------------- strategies
def orb_entry(st, day, op):
    s = op; e = op + dt.timedelta(minutes=4, seconds=59); b = []
    for _ in range(4):
        b = bars_1m('QQQ', s, e)
        if len(b) >= 4: break
        sleep(5)
    if len(b) < 3: st['ORB'] = dict(note=f'only {len(b)} bars'); return
    o, c = b[0]['o'], b[-1]['c']; hi = max(x['h'] for x in b); lo = min(x['l'] for x in b); rng = hi - lo
    if rng <= 0 or abs(c - o) < 0.05 * rng: st['ORB'] = dict(note='no signal (doji open)'); return
    side = 1 if c > o else -1; stop = lo if side > 0 else hi; R = abs(c - stop)
    if R <= 0: st['ORB'] = dict(note='zero range'); return
    qty = max(1, int(100.0 // R)); tgt = round(c + side * 10 * R, 2)
    order = {'symbol': 'QQQ', 'qty': str(qty), 'side': 'buy' if side > 0 else 'sell', 'type': 'market', 'time_in_force': 'day',
             'order_class': 'bracket', 'take_profit': {'limit_price': str(tgt)}, 'stop_loss': {'stop_price': str(round(stop, 2))},
             'client_order_id': f'orb-{day:%Y%m%d}'}
    sc, res = api('POST', '/orders', json=order)
    st['ORB'] = dict(side=order['side'], qty=qty, ref=c, range=[lo, hi], R=round(R, 4), stop=round(stop, 2), target=tgt, status=sc,
                     order_id=res.get('id') if isinstance(res, dict) else None)
    log(f"ORB {order['side']} {qty} QQQ ~{c} stop {stop:.2f} target {tgt} -> {sc}")

def m7b_entry(st, day, op):
    b = bars_1m('QQQ', op, op + dt.timedelta(minutes=1))
    snap = snapshots(['QQQ', 'QQQM'])
    try: o = b[0]['o']; px = snap['QQQ']['latestTrade']['p']; pm = snap['QQQM']['latestTrade']['p']
    except Exception: st['M7B'] = dict(note='no data'); log('M7B no data'); return
    mv = px / o - 1
    if abs(mv) < 0.015: st['M7B'] = dict(note=f'no signal, move {mv:+.2%}'); log(f'M7B no signal {mv:+.2%}'); return
    qty = max(1, int(10000.0 // pm)); side = 'buy' if mv > 0 else 'sell'
    sc, res = api('POST', '/orders', json={'symbol': 'QQQM', 'qty': str(qty), 'side': side, 'type': 'market', 'time_in_force': 'day',
                                            'client_order_id': f'm7b-{day:%Y%m%d}'})
    st['M7B'] = dict(side=side, qty=qty, move=round(mv, 4), ref=pm, status=sc, order_id=res.get('id') if isinstance(res, dict) else None)
    log(f'M7B {side} {qty} QQQM (QQQ move {mv:+.2%}) -> {sc}')

def k4_book(): return jload(os.path.join(BOTS, 'k4_book.json'), {'open': [], 'closed': []})

def k2_entry(st, day, op):
    uni, ed = universe(); held = {p['sym'] for p in k4_book()['open']}
    snap = snapshots(uni); cands = []
    for s, v in snap.items():
        try:
            prev = v['prevDailyBar']['c']; lt = v['latestTrade']; px = lt['p']
            import pandas as pd
            if pd.Timestamp(lt['t']) < pd.Timestamp(op): continue                                # no print yet today
            gap = px / prev - 1
            if abs(gap) < 0.05 or px < 3 or s in held: continue
            if any(abs((pd.Timestamp(x).date() - day).days) <= 1 for x in ed.get(s, [])): continue
            cands.append(dict(sym=s, px=px, gap=gap))
        except Exception: continue
    cands = sorted(cands, key=lambda c: -abs(c['gap']))[:10]; legs = []
    for c in cands:
        qty = max(1, int(500.0 // c['px'])); side = 'sell' if c['gap'] > 0 else 'buy'
        sc, res = api('POST', '/orders', json={'symbol': c['sym'], 'qty': str(qty), 'side': side, 'type': 'market', 'time_in_force': 'day',
                                                'client_order_id': f"k2-{day:%Y%m%d}-{c['sym']}"})
        legs.append(dict(sym=c['sym'], side=side, qty=qty, gap=round(c['gap'], 4), ref=c['px'], status=sc))
    st['K2'] = dict(scanned=len(snap), legs=legs); log(f"K2 scanned {len(snap)} legs {[(l['sym'], l['side']) for l in legs]}")

def k4_run(st, day, entries):
    book = k4_book(); keep = []
    for p in book['open']:
        n = trading_days(dt.date.fromisoformat(p['date']), day)
        if n is not None and n - 1 >= 5:
            qty = min(p['qty'], abs(position_qty(p['sym'])))
            if qty > 0:
                sc, res = api('POST', '/orders', json={'symbol': p['sym'], 'qty': str(int(qty)), 'side': 'sell', 'type': 'market',
                                                        'time_in_force': 'day', 'client_order_id': f"k4x-{day:%Y%m%d}-{p['sym']}"})
                p['exit_order'] = res.get('id') if isinstance(res, dict) else None
            p['exit_date'] = str(day); book['closed'].append(p); log(f"K4 exit {p['sym']}")
        else: keep.append(p)
    book['open'] = keep; new = []
    if entries:
        uni, ed = universe(); k2 = {l['sym'] for l in st.get('K2', {}).get('legs', [])}
        held = {p['sym'] for p in keep} | {p['sym'] for p in book['closed'] if p.get('exit_date') == str(day)}   # no same-day re-buy
        d = daily_closes(uni, day)
        if len(d) >= 5:
            ref = d.iloc[-5]; snap = snapshots(uni); cands = []
            import pandas as pd
            for s, v in snap.items():
                try:
                    px = v['latestTrade']['p']; r5 = px / ref[s] - 1
                    if pd.isna(r5) or r5 > -0.15 or px < 3 or s in held or s in k2: continue
                    if any(abs((pd.Timestamp(x).date() - day).days) <= 1 for x in ed.get(s, [])): continue
                    cands.append(dict(sym=s, px=px, r5=r5))
                except Exception: continue
            for c in sorted(cands, key=lambda c: c['r5'])[:10]:
                qty = max(1, int(500.0 // c['px']))
                sc, res = api('POST', '/orders', json={'symbol': c['sym'], 'qty': str(qty), 'side': 'buy', 'type': 'market',
                                                        'time_in_force': 'day', 'client_order_id': f"k4-{day:%Y%m%d}-{c['sym']}"})
                if sc < 300:
                    p = dict(sym=c['sym'], date=str(day), qty=qty, ref=c['px'], r5=round(c['r5'], 4), order=res.get('id'))
                    book['open'].append(p); new.append(c['sym'])
    jsave(os.path.join(BOTS, 'k4_book.json'), book); st['K4'] = dict(new=new, open=len(book['open'])); log(f'K4 new {new}')

def settle(st, day, op):
    """P&L per strategy for the day from filled orders (symbols are disjoint by design). UNVERIFIED-PAPER."""
    sc, orders = api('GET', '/orders', params={'status': 'closed', 'after': (op - dt.timedelta(hours=1)).isoformat(),
                                               'limit': 500, 'nested': 'true', 'direction': 'asc'})
    fills = []
    def walk(os_):
        for o in os_:
            if o.get('filled_qty') and float(o['filled_qty']) > 0 and o.get('filled_avg_price'):
                fills.append((o['symbol'], o['side'], float(o['filled_qty']), float(o['filled_avg_price']), o.get('client_order_id') or ''))
            walk(o.get('legs') or [])
    walk(orders if sc == 200 and isinstance(orders, list) else [])
    k2 = {l['sym'] for l in st.get('K2', {}).get('legs', [])}
    def pnl(pred):
        f = [x for x in fills if pred(x)]
        return (round(sum(q * p * (1 if s == 'sell' else -1) for _, s, q, p, _ in f), 2) if f else None), len(f)
    res = {'ORB': pnl(lambda x: x[0] == 'QQQ'), 'M7B': pnl(lambda x: x[0] == 'QQQM'), 'K2': pnl(lambda x: x[0] in k2)}
    # K4: closed trades priced from their own entry/exit orders
    book = k4_book(); done = 0
    for p in book['closed']:
        if p.get('pnl_usd') is not None or not p.get('order') or not p.get('exit_order'): continue
        s1, o1 = api('GET', f"/orders/{p['order']}"); s2, o2 = api('GET', f"/orders/{p['exit_order']}")
        if s1 == 200 and s2 == 200 and o1.get('filled_avg_price') and o2.get('filled_avg_price'):
            p['pnl_usd'] = round((float(o2['filled_avg_price']) - float(o1['filled_avg_price'])) * float(o2['filled_qty']), 2); done += 1
    jsave(os.path.join(BOTS, 'k4_book.json'), book)
    st['settle'] = {k: {'pnl_usd': v[0], 'fills': v[1]} for k, v in res.items()}; st['settle']['K4_closed_priced_today'] = done
    log(f"SETTLE {st['settle']}")

# ---------------------------------------------------------------- the tick
def tick():
    t = now(); day = t.date(); cal = calendar_day(day)
    if cal == 'ERR': log('calendar unreachable'); return
    if not cal: return                                                    # weekend/holiday: nothing to do
    op = at(day, *map(int, cal['open'].split(':'))); cl = at(day, *map(int, cal['close'].split(':')))
    sp = os.path.join(BOTS, f'day_{day}.json'); st = jload(sp, {'date': str(day), 'done': []}); C = cfg()
    def run(name, target, until, fn, needs_entry=True):
        if name in st['done'] or not due(now(), target, until): return
        if needs_entry and not entries_allowed(): st['done'].append(name); st[name.split('_')[0]] = dict(note='entries blocked'); jsave(sp, st); return
        st['done'].append(name); jsave(sp, st)                             # mark first: never double-enter on a crash
        try: fn()
        except Exception: log(f'{name} ERROR ' + traceback.format_exc()[-400:])
        jsave(sp, st)
    if C.get('K2'):  run('K2_entry', op + dt.timedelta(minutes=1), op + dt.timedelta(minutes=15), lambda: k2_entry(st, day, op))
    if C.get('ORB'): run('ORB_entry', op + dt.timedelta(minutes=5, seconds=5), op + dt.timedelta(minutes=30), lambda: orb_entry(st, day, op))
    if C.get('M7B') and cl.time() == dt.time(16, 0):
        run('M7B_entry', at(day, 15, 0, 5), at(day, 15, 20), lambda: m7b_entry(st, day, op))
    if C.get('K4') and cl.time() == dt.time(16, 0):
        run('K4_run', at(day, 15, 50), at(day, 15, 57), lambda: k4_run(st, day, entries_allowed()), needs_entry=False)
    if C.get('K2'):  run('K2_flat', cl - dt.timedelta(minutes=5), cl, lambda: [flatten(l['sym']) for l in st.get('K2', {}).get('legs', [])], needs_entry=False)
    if C.get('ORB'): run('ORB_flat', cl - dt.timedelta(minutes=2), cl, lambda: flatten('QQQ'), needs_entry=False)
    if C.get('M7B'): run('M7B_flat', cl - dt.timedelta(minutes=1), cl, lambda: flatten('QQQM'), needs_entry=False)
    run('settle', cl + dt.timedelta(minutes=10), cl + dt.timedelta(hours=6), lambda: settle(st, day, op), needs_entry=False)
    jsave(sp, st)

def summary():
    """bots.md for the reports folder: one line per strategy per day, labelled UNVERIFIED-PAPER."""
    rows = []
    for f in sorted(x for x in os.listdir(BOTS) if x.startswith('day_')):
        d = jload(os.path.join(BOTS, f), {}); s = d.get('settle', {})
        for k in ('ORB', 'M7B', 'K2'):
            if k in s and s[k]['fills']: rows.append((d['date'], k, s[k]['pnl_usd'], s[k]['fills']))
    book = k4_book(); k4 = [p for p in book['closed'] if p.get('pnl_usd') is not None]
    tot = {k: round(sum(r[2] for r in rows if r[1] == k), 2) for k in ('ORB', 'M7B', 'K2')}; tot['K4'] = round(sum(p['pnl_usd'] for p in k4), 2)
    L = [f"# Fin paper bots — UNVERIFIED-PAPER (Alpaca paper, $) — {now():%Y-%m-%d %H:%M} NY", '',
         f"Totals: ORB {tot['ORB']:+.2f} | M7B {tot['M7B']:+.2f} | K2 {tot['K2']:+.2f} | K4 {tot['K4']:+.2f} (closed {len(k4)}, open {len(book['open'])})",
         f"Disk free {free_gb():.0f} GB (entries stop under {MIN_FREE_GB})", '', '| date | strategy | pnl $ | fills |', '|---|---|---|---|']
    L += [f'| {d} | {k} | {p:+.2f} | {n} |' for d, k, p, n in rows[-40:]]
    with open(os.path.join(BOTS, 'bots.md'), 'w') as f: f.write('\n'.join(L) + '\n')

if __name__ == '__main__':
    os.makedirs(BOTS, exist_ok=True)
    lk = open(os.path.join(BOTS, 'tick.lock'), 'w')
    try: fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError: sys.exit(0)                                           # previous tick still running
    H = _creds()
    if '--check' in sys.argv:
        sc, acc = api('GET', '/account'); print('CHECK', sc, acc.get('account_number') if isinstance(acc, dict) else acc); sys.exit(0 if sc == 200 else 1)
    try: tick(); summary()
    except Exception: log('TICK ERROR ' + traceback.format_exc()[-600:])
