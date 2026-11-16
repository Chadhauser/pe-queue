# Offline test of tick.py against a fake Alpaca paper broker (no network). Worked examples with known answers.
import os, sys, json, tempfile, datetime as dt, importlib, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.mkdtemp(); os.environ['FINQ_STATE'] = TMP
import tick as T
import pandas as pd
NY = T.NY
RES = []
def check(name, ok, got=''): RES.append((name, ok, got)); print(('PASS ' if ok else 'FAIL ') + name + (f'  [{got}]' if got != '' else ''))

class Fake:
    def __init__(s, clock, prices, half=False, disk=100.0):
        s.clock = clock; s.px = prices; s.orders = []; s.pos = {}; s.half = half; s.disk = disk; s.n = 0
    def fill(s, sym, side, qty, coid=''):
        p = s.px(sym, s.clock[0]); s.n += 1
        o = dict(id=f'o{s.n}', t=s.clock[0], symbol=sym, side=side, filled_qty=str(qty), filled_avg_price=str(p), client_order_id=coid, status='filled', legs=[])
        s.orders.append(o); s.pos[sym] = s.pos.get(sym, 0) + (qty if side == 'buy' else -qty)
        if s.pos[sym] == 0: del s.pos[sym]
        return o
    def api(s, method, path, **kw):
        if path == '/calendar':
            a = dt.date.fromisoformat(kw['params']['start']); b = dt.date.fromisoformat(kw['params']['end']); rows = []
            d = a
            while d <= b:
                if d.weekday() < 5: rows.append({'date': str(d), 'open': '09:30', 'close': '13:00' if s.half else '16:00'})
                d += dt.timedelta(days=1)
            return 200, rows
        if method == 'POST' and path == '/orders':
            j = kw['json']; o = s.fill(j['symbol'], j['side'], int(j['qty']), j.get('client_order_id', ''))
            if j.get('order_class') == 'bracket': o['legs'] = []          # legs stay open (not hit) in these tests
            return 200, o
        if method == 'GET' and path == '/orders':
            if kw['params']['status'] == 'open': return 200, []
            after = dt.datetime.fromisoformat(kw['params']['after'])
            return 200, [o for o in s.orders if o['t'] >= after]
        if method == 'GET' and path.startswith('/orders/'):
            oid = path.split('/')[-1]; return 200, next(o for o in s.orders if o['id'] == oid)
        if method == 'GET' and path.startswith('/positions/'):
            sym = path.split('/')[-1]
            return (200, {'qty': str(s.pos[sym])}) if sym in s.pos else (404, {})
        if method == 'DELETE' and path.startswith('/positions/'):
            sym = path.split('/')[-1]; q = s.pos.get(sym, 0)
            if q: s.fill(sym, 'sell' if q > 0 else 'buy', abs(q))
            return 200, {}
        if method == 'DELETE': return 204, {}
        raise Exception(f'unexpected {method} {path}')

def install(f, uni_rows, earnings, closes):
    T.api = f.api
    T.now = lambda: f.clock[0]
    T.sleep = lambda x: f.clock.__setitem__(0, f.clock[0] + dt.timedelta(seconds=max(0, x)))
    T.free_gb = lambda: f.disk
    T.bars_1m = lambda sym, a, b: [dict(o=500, h=501.5, l=499.5, c=501, t='x')] * 5 if sym == 'QQQ' else []
    def snaps(syms):
        out = {}
        for sym in syms:
            p = f.px(sym, f.clock[0]); prev = uni_rows.get(sym)
            out[sym] = {'latestTrade': {'p': p, 't': f.clock[0].astimezone(dt.timezone.utc).isoformat()}, 'prevDailyBar': {'c': prev}}
        return out
    T.snapshots = snaps
    T.universe = lambda: (list(uni_rows), earnings)
    T.daily_closes = lambda syms, today: closes

def run_day(f, day, start=(9, 29), end=(16, 20)):
    t = dt.datetime.combine(day, dt.time(*start), tzinfo=NY); stop = dt.datetime.combine(day, dt.time(*end), tzinfo=NY)
    while t <= stop:
        f.clock[0] = t; T.tick(); t += dt.timedelta(minutes=1)

def prices(sym, t):
    h = t.hour * 60 + t.minute
    base = {'QQQ': 501 if h < 15 * 60 else (508 if h < 15 * 60 + 58 else 503), 'QQQM': 210 if h < 15 * 60 + 59 else 211,
            'AAA': 11 if h < 15 * 60 + 55 else 10.5, 'BBB': 20.5, 'CCC': 4.5, 'DDD': 7 if h < 15 * 60 + 55 else 7.2, 'EEE': 8, 'FFF': 9}
    return base[sym]
uni = {'AAA': 10, 'BBB': 20, 'CCC': 5, 'DDD': 8, 'EEE': 8.1, 'FFF': 9}
day = dt.date(2026, 11, 17)
earn = {'CCC': [str(day + dt.timedelta(days=1))]}
closes = pd.DataFrame({'AAA': [14] * 6, 'BBB': [20] * 6, 'CCC': [5] * 6, 'DDD': [8] * 6, 'EEE': [10] * 6, 'FFF': [9] * 6},
                      index=pd.to_datetime([day - dt.timedelta(days=i) for i in range(8, 2, -1)]))

# ---- A: normal day, all four strategies
f = Fake([None], prices); install(f, uni, earn, closes); run_day(f, day)
st = json.load(open(os.path.join(TMP, 'bots', f'day_{day}.json')))
check('A1 ORB long 66 QQQ (R 1.5 -> $100//1.5=66), stop 499.5, target 516', st['ORB'].get('qty') == 66 and st['ORB']['side'] == 'buy' and st['ORB']['stop'] == 499.5 and st['ORB']['target'] == 516.0, st['ORB'])
check('A2 M7B buy 47 QQQM ($10k//210) on QQQ +1.6%', st['M7B'].get('qty') == 47 and st['M7B']['side'] == 'buy', st['M7B'])
legs = {l['sym']: (l['side'], l['qty']) for l in st['K2']['legs']}
check('A3 K2 fades AAA (sell 45) and DDD (buy 71); skips BBB (2.5% gap) and CCC (earnings tomorrow)', legs == {'AAA': ('sell', 45), 'DDD': ('buy', 71)}, legs)
check('A4 K4 buys EEE only (-20%); AAA excluded because K2 traded it today; FFF -0% skipped', st['K4']['new'] == ['EEE'], st['K4'])
s = st['settle']
check('A5 settle ORB +132.00 (66 x (503-501))', s['ORB']['pnl_usd'] == 132.0, s['ORB'])
check('A6 settle M7B +47.00 (47 x (211-210))', s['M7B']['pnl_usd'] == 47.0, s['M7B'])
check('A7 settle K2 +36.70 (45 x 0.5 + 71 x 0.2)', s['K2']['pnl_usd'] == 36.7, s['K2'])
check('A8 only EEE left open (K4 hold), QQQ/QQQM/K2 names flat', f.pos == {'EEE': 62}, f.pos)
n_orders = len(f.orders)
# ---- B: idempotent — run the whole day again, no new orders
run_day(f, day); check('B1 re-running every tick adds no orders', len(f.orders) == n_orders, len(f.orders) - n_orders)
# ---- C: disk under 25 GB on the next day -> no entries, K4 not entered, flats still run
day2 = day + dt.timedelta(days=1); f.disk = 20.0; f.pos['QQQ'] = 10   # pretend a stray QQQ position exists
run_day(f, day2); st2 = json.load(open(os.path.join(TMP, 'bots', f'day_{day2}.json')))
check('C1 disk 20 GB: ORB/K2/M7B blocked', all(st2[k].get('note') == 'entries blocked' for k in ('ORB', 'K2', 'M7B')), {k: st2[k] for k in ('ORB', 'K2', 'M7B')})
check('C2 disk 20 GB: K4 makes no new buys', st2['K4']['new'] == [], st2['K4'])
check('C3 disk 20 GB: ORB flatten still closes the stray QQQ', 'QQQ' not in f.pos, f.pos)
# ---- D: Saturday -> nothing
sat = dt.date(2026, 11, 21); before = len(f.orders); f.disk = 100.0; run_day(f, sat)
check('D1 Saturday: no state file, no orders', not os.path.exists(os.path.join(TMP, 'bots', f'day_{sat}.json')) and len(f.orders) == before)
# ---- E: half day (13:00 close) -> M7B and K4 skipped; flats move to 12:55/12:58/12:59
half = dt.date(2026, 11, 27); f.half = True; os.remove(os.path.join(TMP, 'bots', 'calendar.json'))
run_day(f, half, end=(13, 20)); st3 = json.load(open(os.path.join(TMP, 'bots', f'day_{half}.json')))
check('E1 half day: M7B and K4 not run', 'M7B_entry' not in st3['done'] and 'K4_run' not in st3['done'], st3['done'])
check('E2 half day: ORB entered and flattened before 13:00, settle ran', 'ORB_entry' in st3['done'] and 'ORB_flat' in st3['done'] and 'settle' in st3['done'] and 'QQQ' not in f.pos, st3['done'])
# ---- F: K4 exit on the 5th trading day after entry (17 Nov entry -> exit 24 Nov: 17,18,19,20,23,24 = 6 days incl. both -> n-1 = 5)
f.half = False; os.remove(os.path.join(TMP, 'bots', 'calendar.json'))
for d in (dt.date(2026, 11, 23),):
    run_day(f, d, start=(15, 49), end=(16, 20))
book = json.load(open(os.path.join(TMP, 'bots', 'k4_book.json')))
check('F1 23 Nov (4th trading day after): EEE still held', any(p['sym'] == 'EEE' for p in book['open']), [p['sym'] for p in book['open']])
run_day(f, dt.date(2026, 11, 24), start=(15, 49), end=(16, 20)); book = json.load(open(os.path.join(TMP, 'bots', 'k4_book.json')))
eee = next((p for p in book['closed'] if p['sym'] == 'EEE'), None)
check('F2 24 Nov (5th trading day): EEE sold and priced, pnl 0.00 (62 x (8-8))', eee is not None and eee.get('pnl_usd') == 0.0 and 'EEE' not in f.pos, eee)
# ---- G: KILL file blocks entries
open(os.path.join(TMP, 'KILL'), 'w').close(); d = dt.date(2026, 11, 25); run_day(f, d, end=(10, 0))
st4 = json.load(open(os.path.join(TMP, 'bots', f'day_{d}.json'))); check('G1 KILL file: ORB entry blocked', st4['ORB'].get('note') == 'entries blocked', st4['ORB'])
os.remove(os.path.join(TMP, 'KILL'))
# ---- H: endpoint is paper only
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tick.py')).read()
check('H1 only the paper trading endpoint appears in the code', 'paper-api.alpaca.markets' in src and 'https://api.alpaca.markets' not in src)
T.summary(); print(open(os.path.join(TMP, 'bots', 'bots.md')).read())
print(f"\n{sum(1 for r in RES if r[1])}/{len(RES)} PASS"); shutil.rmtree(TMP); sys.exit(0 if all(r[1] for r in RES) else 1)
