# FIN PAPER BOTS — one short "tick" per minute (cron), Alpaca PAPER endpoint only.
# Replaces the long-running bots (orb_alpaca_bot / k2 / k4) that waited for hours inside one process. Each tick looks at New York
# time and the Alpaca trading CALENDAR (handles DST and half days), runs whatever phase is due and not yet done today, saves state,
# and exits — normally within seconds, never more than ~60 s. Cron wraps it in nice/ionice/timeout.
# Strategies (symbols are kept disjoint so one account can hold them all without netting):
#   ORB  — QQQ  5-min opening range: candle direction 09:30-09:35, bracket stop at range edge, target 10R, $100 risk, flat 2 min before close
#   M7B  — signal on QQQ 09:30->15:00 move >= 1.5%  -> trade QQQM WITH it, $10,000 notional, 15:00 -> flat 1 min before close (16:00 days only)
#   K2   — small-cap overnight gap >= 5% (official open vs official prior close) faded at 09:31, $500/name, max 30, flat 5 min before close
#   K7   — heavily traded small-cap up >= 25% over 20 days, sold short 15:52, $500/name, max 10/day, bought back on the 5th trading day
#   K4   — small-cap down >= 15% over 5 trading days, bought 15:50, $500/name, max 10/day, sold on the 5th trading day
#   ORB_SPY / ORB_IWM — the same ORB rule on SPY and IWM (M23/M24: WORKS AT SMALL SIZE on the backtest)
#   E1S  — pre-FOMC drift (Lucca-Moench, E1s WORKS): long $10,000 VOO (S&P 500) from 2 min before the close on the trading day
#          before an FOMC decision day to 2 min before the close on the decision day. VOO so it never nets with SPY's ORB.
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

def assets():
    """sym -> (tradable, shortable) from Alpaca, cached per day. Unknown symbols count as not tradable."""
    p = os.path.join(BOTS, f'assets_{now():%Y-%m-%d}.json'); a = jload(p, None)
    if a is None:
        sc, rows = api('GET', '/assets', params={'status': 'active', 'asset_class': 'us_equity'})
        a = {r['symbol']: [bool(r.get('tradable')), bool(r.get('shortable') and r.get('easy_to_borrow'))] for r in (rows if sc == 200 and isinstance(rows, list) else [])}
        if a: jsave(p, a)
    return a or {}
def can(A, s): return A.get(s, [False, False]) if A else [True, True]     # asset list unreachable: don't block, let the broker decide

# ---------------------------------------------------------------- helpers
def jload(p, d):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return d
def jsave(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True); tmp = p + '.tmp'
    with open(tmp, 'w') as f: json.dump(obj, f, indent=1)
    os.replace(tmp, p)
def cfg(): return jload(CFG_PATH, {'ORB': True, 'ORB_SPY': True, 'ORB_IWM': True, 'M7B': True, 'K2': True, 'K4': True, 'E1S': True})
def fomc_dates():
    import pandas as pd
    out = set()
    # past decision days come from the minutes archive; upcoming ones (no minutes yet) from fomc_upcoming.csv next to this file
    for f in ('/root/pe-data/events/fomc.csv', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fomc_upcoming.csv')):
        try: out |= set(str(d.date()) for d in pd.to_datetime(pd.read_csv(f).date))
        except Exception: pass
    return out
def next_trading_day(day):
    sc, cal = api('GET', '/calendar', params={'start': str(day + dt.timedelta(days=1)), 'end': str(day + dt.timedelta(days=10))})
    return cal[0]['date'] if sc == 200 and cal else None
ETF_SYMS = {'QQQ', 'SPY', 'IWM', 'QQQM', 'VOO'}
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
def cancel_open(sym, keep=()):
    sc, orders = api('GET', '/orders', params={'status': 'open', 'symbols': sym, 'nested': 'true', 'limit': 100})
    for o in (orders if sc == 200 and isinstance(orders, list) else []):
        if o['id'] not in keep: api('DELETE', f"/orders/{o['id']}")
def flatten(sym):
    """Close a position. Bracket legs HOLD the shares and a cancel is asynchronous (18 Nov: IWM close refused 403, held overnight),
    so cancel, wait for the release, close, and confirm flat; retry. Our own closing order is never cancelled and is given time to
    fill (19 Nov: the retry cancelled the closing order before it filled at the open). Returns the closing order ids (for settle)."""
    ids = []
    for i in range(8):
        cancel_open(sym, keep=ids)
        if position_qty(sym) == 0: return ids
        sleep(2)
        sc, r = api('DELETE', f'/positions/{sym}')
        if sc < 300 and isinstance(r, dict) and r.get('id'): ids.append(r['id'])
        if ids:
            for _ in range(15):                                            # up to 30s for the closing order to fill
                sleep(2)
                if position_qty(sym) == 0: return ids
    log(f'FLATTEN FAILED {sym}: still open after 8 tries'); return ids
def flatten_many(syms):
    """Close many plain positions quickly (up to 30 gap-fade names must be flat before the opening-break closes run at 15:58):
    send every closing order first, then wait for them together; anything still open gets the careful one-by-one routine."""
    for sym in syms:
        if position_qty(sym) != 0: api('DELETE', f'/positions/{sym}')
    left = list(syms)
    for _ in range(10):
        sleep(2); left = [x for x in left if position_qty(x) != 0]
        if not left: return
    for sym in left: flatten(sym)
def stray_flat(st):
    """At the open, close anything left in the intraday symbols from a previous day; those fills never count (settle skips them)."""
    for sym in ('QQQ', 'SPY', 'IWM', 'QQQM'):
        if position_qty(sym) != 0:
            log(f'STRAY {sym} left from a previous day: closing at the open')
            st.setdefault('stray_ids', []).extend(flatten(sym)); st.setdefault('stray', []).append(sym)

# ---------------------------------------------------------------- strategies
def orb_entry(st, day, op, sym='QQQ', key='ORB'):
    s = op; e = op + dt.timedelta(minutes=4, seconds=59); b = []
    for _ in range(4):
        b = bars_1m(sym, s, e)
        if len(b) >= 4: break
        sleep(5)
    if len(b) < 3: st[key] = dict(note=f'only {len(b)} bars'); return
    o, c = b[0]['o'], b[-1]['c']; hi = max(x['h'] for x in b); lo = min(x['l'] for x in b); rng = hi - lo
    if rng <= 0 or abs(c - o) < 0.05 * rng: st[key] = dict(note='no signal (doji open)'); return
    side = 1 if c > o else -1; stop = lo if side > 0 else hi; R = abs(c - stop)
    if R <= 0: st[key] = dict(note='zero range'); return
    qty = max(1, int(100.0 // R)); tgt = round(c + side * 10 * R, 2)
    order = {'symbol': sym, 'qty': str(qty), 'side': 'buy' if side > 0 else 'sell', 'type': 'market', 'time_in_force': 'day',
             'order_class': 'bracket', 'take_profit': {'limit_price': str(tgt)}, 'stop_loss': {'stop_price': str(round(stop, 2))},
             'client_order_id': f'orb-{sym}-{day:%Y%m%d}'}
    sc, res = api('POST', '/orders', json=order)
    st[key] = dict(side=order['side'], qty=qty, ref=c, range=[lo, hi], R=round(R, 4), stop=round(stop, 2), target=tgt, status=sc,
                     order_id=res.get('id') if isinstance(res, dict) else None)
    log(f"{key} {order['side']} {qty} {sym} ~{c} stop {stop:.2f} target {tgt} -> {sc}")

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

def official_gaps(syms, day):
    """{sym: (today's official open, yesterday's official close)} from daily bars — exactly what the history test used.
    21 Nov: the old gap (last IEX print vs IEX close) picked 22 of 35 shares that had not gapped at all (they lost 218 bps each)."""
    import yfinance as yf, pandas as pd
    d = yf.download(syms, period='5d', interval='1d', auto_adjust=False, progress=False, threads=True)
    if d is None or len(d) < 2 or d.index[-1].date() != day: return {}
    o = d['Open'].iloc[-1]; pc = d['Close'].iloc[-2]
    return {s: (float(o[s]), float(pc[s])) for s in syms if s in o.index and pd.notna(o[s]) and pd.notna(pc[s]) and pc[s] > 0}
def k2_entry(st, day, op):
    uni, ed = universe(); held = {p['sym'] for p in k4_book()['open']} | {p['sym'] for p in k7_book()['open']}; cands = []; A = assets(); G = {}
    for _ in range(3):                                                     # the day's opens can lag a little after 09:30
        G = official_gaps(uni, day)
        if len(G) >= 0.5 * len(uni): break
        sleep(30)
    if len(G) < 0.5 * len(uni): st['K2'] = dict(note=f'official opens for only {len(G)} of {len(uni)} names: no trade today', legs=[]); log(f"K2 {st['K2']['note']}"); return
    import pandas as pd
    for s, (px, prev) in G.items():
        try:
            gap = px / prev - 1
            if abs(gap) < 0.05 or px < 3 or s in held or s in ETF_SYMS: continue
            tr, sh = can(A, s)
            if not tr or (gap > 0 and not sh): continue                                       # can't buy / can't short it
            if any(abs((pd.Timestamp(x).date() - day).days) <= 1 for x in ed.get(s, [])): continue
            cands.append(dict(sym=s, px=px, gap=gap))
        except Exception: continue
    cands = sorted(cands, key=lambda c: -abs(c['gap']))[:30]; legs = []   # the history test took every name (20-28 a day), not the ten biggest
    for c in cands:
        qty = max(1, int(500.0 // c['px'])); side = 'sell' if c['gap'] > 0 else 'buy'
        sc, res = api('POST', '/orders', json={'symbol': c['sym'], 'qty': str(qty), 'side': side, 'type': 'market', 'time_in_force': 'day',
                                                'client_order_id': f"k2-{day:%Y%m%d}-{c['sym']}"})
        legs.append(dict(sym=c['sym'], side=side, qty=qty, gap=round(c['gap'], 4), ref=c['px'], status=sc))
    st['K2'] = dict(scanned=len(G), legs=legs); log(f"K2 scanned {len(G)} legs {[(l['sym'], l['side']) for l in legs]}")

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
        held = {p['sym'] for p in keep} | {p['sym'] for p in book['closed'] if p.get('exit_date') == str(day)} | {p['sym'] for p in k7_book()['open']}   # no same-day re-buy
        d = daily_closes(uni, day)
        if len(d) >= 5:
            ref = d.iloc[-5]; snap = snapshots(uni); cands = []; A = assets()
            import pandas as pd
            for s, v in snap.items():
                try:
                    px = v['latestTrade']['p']; r5 = px / ref[s] - 1
                    if (now() - pd.Timestamp(v['latestTrade']['t']).to_pydatetime()).total_seconds() > 1800: continue   # stale print on the thin feed (21 Nov gap-fade lesson)
                    if pd.isna(r5) or r5 > -0.15 or px < 3 or s in held or s in k2 or s in ETF_SYMS or not can(A, s)[0]: continue
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

def k7_book(): return jload(os.path.join(BOTS, 'k7_book.json'), {'open': [], 'closed': []})
def k7_candidates(uni, day):
    """[(sym, 20-day return, average traded value, price)] from official daily bars; today's row is the price near the close."""
    import yfinance as yf, pandas as pd
    d = yf.download(uni, period='3mo', interval='1d', auto_adjust=False, progress=False, threads=True)
    if d is None or len(d) < 22 or d.index[-1].date() != day: return []
    C_, V_ = d['Close'], d['Volume']; r20 = C_.iloc[-1] / C_.iloc[-21] - 1; dv = (C_ * V_).iloc[-21:-1].mean()
    return [(s, float(r20[s]), float(dv[s]), float(C_[s].iloc[-1])) for s in uni if s in r20.index and pd.notna(r20[s]) and pd.notna(dv[s])]
def k7_run(st, day, entries):
    """K7 (from the data map, 21 Nov): heavily traded small company ($30m+ a day) up 25%+ in 20 days -> SELL SHORT near the close,
    buy back on the 5th trading day. $500 a name, max 10 a day. History: +2.2% a trade after 0.6% measured cost, both halves."""
    book = k7_book(); keep = []
    for p in book['open']:
        n = trading_days(dt.date.fromisoformat(p['date']), day)
        if n is not None and n - 1 >= 5:
            qty = min(p['qty'], abs(position_qty(p['sym'])))
            if qty > 0:
                sc, res = api('POST', '/orders', json={'symbol': p['sym'], 'qty': str(int(qty)), 'side': 'buy', 'type': 'market',
                                                        'time_in_force': 'day', 'client_order_id': f"k7x-{day:%Y%m%d}-{p['sym']}"})
                p['exit_order'] = res.get('id') if isinstance(res, dict) else None
            p['exit_date'] = str(day); book['closed'].append(p); log(f"K7 exit {p['sym']}")
        else: keep.append(p)
    book['open'] = keep; new = []
    if entries:
        uni, ed = universe(); A = assets(); k2 = {l['sym'] for l in st.get('K2', {}).get('legs', [])}
        held = {p['sym'] for p in keep} | {p['sym'] for p in book['closed'] if p.get('exit_date') == str(day)} | {p['sym'] for p in k4_book()['open']}
        cands = [c for c in k7_candidates(uni, day) if c[1] >= 0.25 and c[2] >= 30e6 and c[3] >= 3 and c[0] not in held and c[0] not in k2
                 and c[0] not in ETF_SYMS and all(can(A, c[0]))]
        for s_, r20, dv, px in sorted(cands, key=lambda c: -c[1])[:10]:
            qty = max(1, int(500.0 // px))
            sc, res = api('POST', '/orders', json={'symbol': s_, 'qty': str(qty), 'side': 'sell', 'type': 'market', 'time_in_force': 'day',
                                                    'client_order_id': f"k7-{day:%Y%m%d}-{s_}"})
            if sc < 300: book['open'].append(dict(sym=s_, side='sell', date=str(day), qty=qty, ref=px, r20=round(r20, 4), order=res.get('id'))); new.append(s_)
    jsave(os.path.join(BOTS, 'k7_book.json'), book); st['K7'] = dict(new=new, open=len(book['open'])); log(f'K7 new {new}')

def e1_book(): return jload(os.path.join(BOTS, 'e1_book.json'), {'open': [], 'closed': []})
def e1_run(st, day):
    D = fomc_dates(); book = e1_book(); note = []
    for p in list(book['open']):                                   # exit on the decision day
        if str(day) in D or str(day) > p.get('fomc', '9999'):
            qty = min(p['qty'], abs(position_qty('VOO')))
            if qty > 0:
                sc, res = api('POST', '/orders', json={'symbol': 'VOO', 'qty': str(int(qty)), 'side': 'sell', 'type': 'market', 'time_in_force': 'day',
                                                        'client_order_id': f'e1x-{day:%Y%m%d}'})
                p['exit_order'] = res.get('id') if isinstance(res, dict) else None
            p['exit_date'] = str(day); book['open'].remove(p); book['closed'].append(p); note.append('exit')
    nxt = next_trading_day(day)
    if nxt and nxt in D and not book['open'] and entries_allowed():  # enter the trading day before
        snap = snapshots(['VOO'])
        try: px = snap['VOO']['latestTrade']['p']
        except Exception: px = None
        if px:
            qty = max(1, int(10000.0 // px))
            sc, res = api('POST', '/orders', json={'symbol': 'VOO', 'qty': str(qty), 'side': 'buy', 'type': 'market', 'time_in_force': 'day',
                                                    'client_order_id': f'e1-{day:%Y%m%d}'})
            if sc < 300: book['open'].append(dict(date=str(day), fomc=nxt, qty=qty, ref=px, order=res.get('id'))); note.append(f'entry {qty} VOO for FOMC {nxt}')
    jsave(os.path.join(BOTS, 'e1_book.json'), book); st['E1S'] = dict(note=', '.join(note) or f'no FOMC next ({nxt})'); log(f"E1S {st['E1S']}")

def price_book(path):
    book = jload(path, {'open': [], 'closed': []}); done = 0
    for p in book['closed']:
        if p.get('pnl_usd') is not None or not p.get('order') or not p.get('exit_order'): continue
        s1, o1 = api('GET', f"/orders/{p['order']}"); s2, o2 = api('GET', f"/orders/{p['exit_order']}")
        if s1 == 200 and s2 == 200 and o1.get('filled_avg_price') and o2.get('filled_avg_price'):
            p['pnl_usd'] = round((float(o2['filled_avg_price']) - float(o1['filled_avg_price'])) * float(o2['filled_qty']) * (-1 if p.get('side') == 'sell' else 1), 2); done += 1
    jsave(path, book); return done

def settle(st, day, op):
    """P&L per strategy for the day from filled orders (symbols are disjoint by design). UNVERIFIED-PAPER."""
    sc, orders = api('GET', '/orders', params={'status': 'closed', 'after': (op - dt.timedelta(hours=1)).isoformat(),
                                               'limit': 500, 'nested': 'true', 'direction': 'asc'})
    fills = []; stray = set(st.get('stray_ids', []))
    def walk(os_):
        for o in os_:
            if o.get('filled_qty') and float(o['filled_qty']) > 0 and o.get('filled_avg_price'):
                if o.get('id') in stray: continue                          # closing a previous day's leftover is not today's trade
                fills.append((o['symbol'], o['side'], float(o['filled_qty']), float(o['filled_avg_price']), o.get('client_order_id') or ''))
            walk(o.get('legs') or [])
    walk(orders if sc == 200 and isinstance(orders, list) else [])
    k2 = {l['sym'] for l in st.get('K2', {}).get('legs', [])}
    def pnl(pred):
        f = [x for x in fills if pred(x)]; net = {}
        for sy, s, q, _, _ in f: net[sy] = net.get(sy, 0) + (q if s == 'buy' else -q)
        bad = sorted(sy for sy, n in net.items() if abs(n) > 1e-6)         # bought and sold must match, or the "P&L" is just the cost of the shares
        if bad: log(f'SETTLE UNFLAT {bad}: not closed, not counted'); f = [x for x in f if x[0] not in bad]
        return (round(sum(q * p * (1 if s == 'sell' else -1) for _, s, q, p, _ in f), 2) if f else None), len(f)
    mine = lambda k: bool(st.get(k, {}).get('order_id'))                   # count a symbol only if this tick entered it today
    res = {k: (pnl(lambda x, s_=sym: x[0] == s_) if mine(k) else (None, 0))
           for k, sym in (('ORB', 'QQQ'), ('ORB_SPY', 'SPY'), ('ORB_IWM', 'IWM'), ('M7B', 'QQQM'))}
    res['K2'] = pnl(lambda x: x[0] in k2)
    for sd in ('sell', 'buy'):                                             # the two sides of the gap fade judged separately (data map 21 Nov)
        ks = {l['sym'] for l in st.get('K2', {}).get('legs', []) if l.get('side') == sd and l.get('status', 999) < 300}; res[f'K2_{sd}'] = pnl(lambda x, ks=ks: x[0] in ks) + (len(ks),)
    done = price_book(os.path.join(BOTS, 'k4_book.json')); price_book(os.path.join(BOTS, 'k7_book.json')); e1done = price_book(os.path.join(BOTS, 'e1_book.json'))
    st['settle'] = {k: ({'pnl_usd': v[0], 'fills': v[1], 'n': v[2]} if len(v) > 2 else {'pnl_usd': v[0], 'fills': v[1]}) for k, v in res.items()}; st['settle']['K4_closed_priced_today'] = done; st['settle']['E1_closed_priced_today'] = e1done
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
        if needs_entry and not entries_allowed(): st['done'].append(name); st[name.rsplit('_', 1)[0]] = dict(note='entries blocked'); jsave(sp, st); return
        st['done'].append(name); jsave(sp, st)                             # mark first: never double-enter on a crash
        try: fn()
        except Exception: log(f'{name} ERROR ' + traceback.format_exc()[-400:])
        jsave(sp, st)
    run('stray_flat', op + dt.timedelta(seconds=5), op + dt.timedelta(minutes=3), lambda: stray_flat(st), needs_entry=False)
    if C.get('K2'):  run('K2_entry', op + dt.timedelta(minutes=1), op + dt.timedelta(minutes=15), lambda: k2_entry(st, day, op))
    for sym, key in (('QQQ', 'ORB'), ('SPY', 'ORB_SPY'), ('IWM', 'ORB_IWM')):
        if C.get(key): run(f'{key}_entry', op + dt.timedelta(minutes=5, seconds=5), op + dt.timedelta(minutes=30), lambda s_=sym, k_=key: orb_entry(st, day, op, s_, k_))
    if C.get('M7B') and cl.time() == dt.time(16, 0):
        run('M7B_entry', at(day, 15, 0, 5), at(day, 15, 20), lambda: m7b_entry(st, day, op))
    if C.get('K4') and cl.time() == dt.time(16, 0):
        run('K4_run', at(day, 15, 50), at(day, 15, 57), lambda: k4_run(st, day, entries_allowed()), needs_entry=False)
    if C.get('K7', True) and cl.time() == dt.time(16, 0):
        run('K7_run', at(day, 15, 52), at(day, 15, 57), lambda: k7_run(st, day, entries_allowed()), needs_entry=False)
    if C.get('K2'):  run('K2_flat', cl - dt.timedelta(minutes=5), cl, lambda: flatten_many([l['sym'] for l in st.get('K2', {}).get('legs', []) if l.get('status', 999) < 300]), needs_entry=False)
    for sym, key in (('QQQ', 'ORB'), ('SPY', 'ORB_SPY'), ('IWM', 'ORB_IWM')):
        if C.get(key): run(f'{key}_flat', cl - dt.timedelta(minutes=2), cl, lambda s_=sym: flatten(s_), needs_entry=False)
    if C.get('E1S'): run('E1S_run', cl - dt.timedelta(minutes=2), cl, lambda: e1_run(st, day), needs_entry=False)
    if C.get('M7B'): run('M7B_flat', cl - dt.timedelta(minutes=1), cl, lambda: flatten('QQQM'), needs_entry=False)
    run('settle', cl + dt.timedelta(minutes=10), cl + dt.timedelta(hours=6), lambda: settle(st, day, op), needs_entry=False)
    jsave(sp, st)

K2_COUNT_FROM = '2026-11-23'   # Peter 21 Nov: "Restart" - 22 of the first 35 gap-fade trades were not the rule (wrong gap measure); they stay in the record, not in the count
def summary():
    """bots.md: per strategy, settled paper trades (the 100-trade gate counts these) and P&L. UNVERIFIED-PAPER. Line 1 holds the
    timestamp and disk so the runner only commits when the numbers change."""
    rows = []; K = ('ORB', 'ORB_SPY', 'ORB_IWM', 'M7B', 'K2')
    for f in sorted(x for x in os.listdir(BOTS) if x.startswith('day_')):
        d = jload(os.path.join(BOTS, f), {}); s_ = d.get('settle', {})
        for k in K:
            if k in s_ and s_[k]['fills'] and s_[k]['pnl_usd'] is not None and (k == 'K2' or d.get(k, {}).get('order_id')):   # stray fills (old bot, manual) never count
                n = sum(1 for l in d.get('K2', {}).get('legs', []) if l.get('status', 0) < 300) if k == 'K2' else 1   # rejected legs are not trades
                rows.append((d['date'], k, s_[k]['pnl_usd'], n))
    cnt = lambda r: r[1] != 'K2' or r[0] >= K2_COUNT_FROM
    tot = {k: (round(sum(r[2] for r in rows if r[1] == k and cnt(r)), 2), sum(r[3] for r in rows if r[1] == k and cnt(r))) for k in K}
    old = [r for r in rows if not cnt(r)]
    for k, path in (('K4', 'k4_book.json'), ('E1S', 'e1_book.json'), ('K7', 'k7_book.json')):
        b = jload(os.path.join(BOTS, path), {'open': [], 'closed': []}); c = [p for p in b['closed'] if p.get('pnl_usd') is not None]
        tot[k] = (round(sum(p['pnl_usd'] for p in c), 2), len(c))
    L = [f"# Fin paper bots — UNVERIFIED-PAPER (Alpaca paper, $) — updated {now():%Y-%m-%d %H:%M} NY — disk free {free_gb():.0f} GB (entries stop under {MIN_FREE_GB})", '',
         'Gate for real money: 100 settled paper trades per strategy, profitable overall and in each half, in line with the backtest, and Peter\'s yes.', '',
         '| strategy | settled trades | of 100 | pnl $ |', '|---|---|---|---|']
    L += [f'| {k} | {n} | {min(n, 100)}% | {p:+.2f} |' for k, (p, n) in tot.items()]
    side = {}
    for f in sorted(x for x in os.listdir(BOTS) if x.startswith('day_')):
        dd = jload(os.path.join(BOTS, f), {}); s_ = dd.get('settle', {})
        if dd.get('date', '') < K2_COUNT_FROM: continue
        for sd in ('sell', 'buy'):
            v = s_.get(f'K2_{sd}')
            if v and v.get('pnl_usd') is not None: a = side.setdefault(sd, [0.0, 0]); a[0] += v['pnl_usd']; a[1] += v.get('n', 0)
    if side: L += ['', 'K2 gap fade by side (parts of the K2 row above):', '', '| side | trades | pnl $ |', '|---|---|---|'] + [f"| {'sells (gap up)' if sd == 'sell' else 'buys (gap down)'} | {n} | {p:+.2f} |" for sd, (p, n) in side.items()]
    if old: L += ['', f"K2 gap fade count restarted {K2_COUNT_FROM} on Peter's instruction (21 Nov): the {sum(r[3] for r in old)} earlier trades, {sum(r[2] for r in old):+.2f}, were placed with a faulty gap measure. They stay in the daily record below and in the account, not in the count."]
    L += ['', '| date | strategy | pnl $ | trades |', '|---|---|---|---|'] + [f'| {d} | {k} | {p:+.2f} | {n} |' for d, k, p, n in rows[-40:]]
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
