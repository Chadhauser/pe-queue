# Offline test of the league paper executor with a fake broker (no network, no orders anywhere real).
import os, sys, json, shutil, tempfile, datetime as dt
TMP = tempfile.mkdtemp(); os.environ['FINQ_STATE'] = TMP
import league_bot as L
T = L.T; NY = T.NY; RES = []
def check(n, ok, d=''): RES.append(ok); print(('PASS ' if ok else 'FAIL ') + n + ('' if ok else f'  [{d}]'))
class Fake:
    def __init__(s): s.clock = [None]; s.orders = {}; s.pos = {}; s.n = 0; s.px = {}; s.close = '16:00'
    def api(s, m, path, **kw):
        if path == '/calendar':
            a = dt.date.fromisoformat(kw['params']['start']); b = dt.date.fromisoformat(kw['params']['end']); out = []; d = a
            while d <= b:
                if d.weekday() < 5: out.append({'date': str(d), 'open': '09:30', 'close': s.close})
                d += dt.timedelta(days=1)
            return 200, out
        if m == 'POST' and path == '/orders':
            j = kw['json']; s.n += 1; oid = f'o{s.n}'; q = int(j['qty']); p = s.px[j['symbol']]
            s.orders[oid] = dict(id=oid, status='filled', filled_avg_price=str(p), filled_qty=str(q), symbol=j['symbol'], side=j['side'], cid=j['client_order_id'])
            s.pos[j['symbol']] = s.pos.get(j['symbol'], 0) + (q if j['side'] == 'buy' else -q); return 200, s.orders[oid]
        if m == 'GET' and path.startswith('/orders/'): return 200, s.orders[path.split('/')[-1]]
        if m == 'GET' and path.startswith('/positions/'):
            q = s.pos.get(path.split('/')[-1], 0); return (200, {'qty': str(q)}) if q else (404, {})
        if m == 'GET' and path == '/assets': return 200, [{'symbol': x, 'tradable': True, 'shortable': True, 'easy_to_borrow': True} for x in s.px]
        return 200, {}
f = Fake(); T.api = f.api; T.now = lambda: f.clock[0]; T.free_gb = lambda: 100.0; T.log = lambda m: None
T.snapshots = lambda syms: {x: {'minuteBar': {'c': f.px[x]}} for x in syms}
def bar(day, mi, o, c, v=1000):
    t = dt.datetime.combine(day, dt.time(9, 30), tzinfo=NY) + dt.timedelta(minutes=mi); return dict(t=t.astimezone(dt.timezone.utc).isoformat().replace('+00:00', 'Z'), o=o, h=max(o, c), l=min(o, c), c=c, v=v)
day = dt.date(2026, 12, 1)
hist = {s: dict(adr=0.02, adr_prev=0.02, pc=100.0, pc2=100.0, last_day='2026-11-30', cum={str(t): 5000.0 for t in L.TS}) for s in ('AAA', 'BBB', 'CCC', 'SPY')}
L.prep = lambda d: hist
# AAA opens 3% up (a big gap up: 1.5 normal day ranges) and drifts a little; BBB opens flat; CCC gaps up too
today = {'AAA': [bar(day, i, 103, 103.1) for i in range(5)], 'BBB': [bar(day, i, 100, 100.05) for i in range(5)], 'CCC': [bar(day, i, 103, 103.0) for i in range(5)], 'SPY': [bar(day, i, 100, 100.0) for i in range(5)]}
L.bars_many = lambda syms, a, b: today
os.makedirs(L.LG, exist_ok=True)
rules = [dict(id='Lgap', sentence='test: buy big gap up, stop a quarter', at='09:35', facts={'overnight gap': 'big gap up'}, do='BUY', hold="to the close, stop at a quarter of a normal day's range", stake=2500.0, maxn=10),
         dict(id='Lnight', sentence='test: sell flat openers overnight', at='09:35', facts={'overnight gap': 'no gap', 'kind': 'share'}, do='SELL SHORT', hold='overnight to the next open', stake=2500.0, maxn=10)]
json.dump(rules, open(os.path.join(L.LG, 'live_rules.json'), 'w'))
f.px = {'AAA': 103.1, 'BBB': 100.05, 'CCC': 103.0, 'SPY': 100.0}
def tick(h, m, d=day): f.clock[0] = dt.datetime.combine(d, dt.time(h, m, 5), tzinfo=NY); L.run()
F = L.facts_now(hist, today, 5, 'Tuesday')
check('facts: AAA big gap up, BBB no gap, market flat', F['AAA']['overnight gap'] == 'big gap up' and F['BBB']['overnight gap'] == 'no gap' and F['AAA']['market so far (S&P 500 fund)'] == 'market flat', F.get('AAA'))
tick(9, 35); b = L.book()
check('09:35 buys AAA and CCC (24 shares each at about 103), sells BBB short (24), each share used by one rule only', sorted((p['sym'], p['side'], p['qty']) for p in b['open']) == [('AAA', 'buy', 24), ('BBB', 'sell', 24), ('CCC', 'buy', 24)], b['open'])
tick(9, 36); check('no second entry a minute later', len(L.book()['open']) == 3, len(L.book()['open']))
f.px['AAA'] = 102.5; tick(10, 0); b = L.book()                              # stop distance = 0.25 x 0.02 x 103 = 0.515
a = [p for p in b['closed'] if p['sym'] == 'AAA']
check('AAA falls 0.60 (more than a quarter of a normal range): stopped, loss 24 x 0.60 = -14.40', a and a[0]['exit_why'] == 'stop' and f.pos.get('AAA', 0) == 0, a)
tick(10, 1); a = [p for p in L.book()['closed'] if p['sym'] == 'AAA']; check('AAA priced from the fills: -14.40', a and a[0].get('pnl_usd') == -14.4, a)
f.px['CCC'] = 104.0; tick(15, 57); tick(15, 58); c = [p for p in L.book()['closed'] if p['sym'] == 'CCC']
check('CCC held to three minutes before the close: +24.00, nothing left', c and c[0]['exit_why'] == 'time' and c[0].get('pnl_usd') == 24.0 and f.pos.get('CCC', 0) == 0, c)
check('BBB short still held overnight', [p['sym'] for p in L.book()['open']] == ['BBB'] and f.pos.get('BBB') == -24, (L.book()['open'], f.pos))
d2 = dt.date(2026, 12, 2); f.px['BBB'] = 99.0; today = {}; tick(9, 31, d2); tick(9, 32, d2); bb = [p for p in L.book()['closed'] if p['sym'] == 'BBB']
check('next morning 09:31: BBB bought back, +25.20 (24 x 1.05), flat', bb and bb[0].get('pnl_usd') == 25.2 and f.pos.get('BBB', 0) == 0 and not L.book()['open'], (bb, f.pos))
L.report(); md = open(os.path.join(L.LG, 'league_paper.md')).read()
check('scoreboard: Lgap 2 settled +9.60, Lnight 1 settled +25.20', '| Lgap | test: buy big gap up, stop a quarter | 2 | 2% | +9.60 |' in md and '| 1 | 1% | +25.20 |' in md, md)
f.close = '13:00'; os.remove(os.path.join(T.BOTS, 'calendar.json')) if os.path.exists(os.path.join(T.BOTS, 'calendar.json')) else None
d3 = dt.date(2026, 12, 3); today = {'AAA': [bar(d3, i, 103, 103.1) for i in range(5)], 'SPY': [bar(d3, i, 100, 100.0) for i in range(5)]}; tick(9, 35, d3)
check('half day: no entries', not L.book()['open'], L.book()['open'])
print(f"\n{sum(RES)}/{len(RES)} PASS"); shutil.rmtree(TMP); sys.exit(0 if all(RES) else 1)
