# LEAGUE PAPER EXECUTOR (CEO order 27 Nov 2026): every way of earning that passes the league test goes onto the Alpaca PRACTICE
# account automatically. Paper only: it uses the same paper endpoint and keys as the other robots (bots/tick.py) and nothing else.
# One run a minute from cron. Shares and funds only for now (the only universe with passers a practice account can place).
#   prep (before the open): 30 days of minute bars -> per-share history (normal day range, prior closes, usual volume by time of day)
#   at each rule's time: today's bars -> the same facts and bands the test used (bands.py) -> orders for the shares that match
#   every minute: exits that are due (time, close, next open, next close) and stop / bank-profit exits on the last minute's close
# Each trade is its own pair of orders tagged with the rule, so profit is counted from the broker's fills, rule by rule.
import os, sys, json, random, datetime as dt, traceback, fcntl
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'bots'))
import tick as T
from bands import band1, FUNDS
LG = os.path.join(T.ROOT, 'league'); NY = T.NY
EXCLUDE = {'QQQ', 'SPY', 'IWM', 'QQQM', 'VOO'}                              # traded by the other robots: keep their books clean
FACT_BAND = {'move so far today': 'move', 'overnight gap': 'gap', 'yesterday': 'prev', 'first five minutes': 'f5', "place in today's range": 'pos',
             'volume so far': 'rv', 'market so far (S&P 500 fund)': 'mkt', 'against the market': 'rel', 'last 30 minutes': 'l30'}
TS = [5, 15, 30, 60, 90, 120, 180, 240, 300, 330, 360]
def log(m):
    os.makedirs(LG, exist_ok=True)
    with open(os.path.join(LG, 'league.log'), 'a') as f: f.write(f"{T.now():%Y-%m-%d %H:%M:%S} {m}\n")
def rules(): return T.jload(os.path.join(LG, 'live_rules.json'), [])
def book(): return T.jload(os.path.join(LG, 'book.json'), {'open': [], 'closed': []})
def save_book(b): T.jsave(os.path.join(LG, 'book.json'), b)
def universe_syms():
    small = set()
    try: small = set(T.universe()[0])
    except Exception: pass
    liquid = T.jload(os.path.join(LG, 'liquid_symbols.json'), [])
    return [s for s in liquid if s not in EXCLUDE and s not in small]
# ---------------------------------------------------------------- prices
def bars_many(syms, start, end):
    """{sym: [bars]} one-minute bars, all pages."""
    out = {s: [] for s in syms}
    for i in range(0, len(syms), 12):
        chunk = syms[i:i + 12]; tok = None
        for _ in range(400):
            p = dict(symbols=','.join(chunk), timeframe='1Min', start=start.isoformat(), end=end.isoformat(), feed='iex', limit=10000)
            if tok: p['page_token'] = tok
            j = T.data_get('/stocks/bars', **p)
            for s, bs in (j.get('bars') or {}).items(): out.setdefault(s, []).extend(bs)
            tok = j.get('next_page_token')
            if not tok: break
    return out
def mi_of(t):
    x = dt.datetime.fromisoformat(t.replace('Z', '+00:00')).astimezone(NY); return x.date(), x.hour * 60 + x.minute - 570
def day_summary(bs):
    """bars of ONE regular session -> the numbers the test used (minute closes, carried forward over gaps)"""
    bs = [(mi_of(b['t'])[1], b) for b in bs]; bs = sorted((m, b) for m, b in bs if 0 <= m < 390)
    if len(bs) < 200: return None
    closes = [b['c'] for _, b in bs]; f5 = [b['c'] for m, b in bs if m < 5] or [bs[0][1]['c']]
    cum = {}; v = 0; k = 0
    for t_ in TS:
        while k < len(bs) and bs[k][0] < t_: v += bs[k][1]['v']; k += 1
        cum[str(t_)] = v
    return dict(o=bs[0][1]['o'], h=max(b['h'] for _, b in bs), l=min(b['l'] for _, b in bs), c=closes[-1], f5=max(f5) - min(f5), cum=cum, n=len(bs))
def prep(day):
    """per-share history for today's decisions, cached for the day"""
    p = os.path.join(LG, f'hist_{day}.json'); h = T.jload(p, None)
    if h: return h
    syms = universe_syms() + ['SPY']; end = dt.datetime.combine(day, dt.time(0, 0), tzinfo=NY); start = end - dt.timedelta(days=36)
    raw = bars_many(syms, start, end); h = {}
    for s, bs in raw.items():
        byday = {}
        for b in bs: byday.setdefault(str(mi_of(b['t'])[0]), []).append(b)
        days = [(d, day_summary(x)) for d, x in sorted(byday.items())]; days = [(d, x) for d, x in days if x]
        if len(days) < 12: continue
        last = [x for _, x in days][-21:]; rng = [(x['h'] - x['l']) / x['o'] for x in last]
        h[s] = dict(adr=sum(rng[-20:]) / len(rng[-20:]), adr_prev=sum(rng[:-1][-20:]) / len(rng[:-1][-20:]), pc=last[-1]['c'], pc2=last[-2]['c'], last_day=days[-1][0],
                    cum={k: sum(x['cum'][k] for x in last[-20:]) / len(last[-20:]) for k in last[-1]['cum']})
    if len(h) >= 0.5 * len(syms): T.jsave(p, h)
    log(f'prep: history for {len(h)} of {len(syms)} shares and funds'); return h
def facts_now(hist, today_bars, Tm, weekday):
    """{sym: {fact name: band}} at minute Tm of the session, exactly as engine.py builds them"""
    def one(s):
        h = hist.get(s); bs = sorted((mi_of(b['t'])[1], b) for b in today_bars.get(s, [])); bs = [(m, b) for m, b in bs if 0 <= m < Tm]
        if not h or not bs or bs[0][0] > 3 or bs[-1][0] < Tm - 4: return None           # no open print, or the last print is stale
        o = bs[0][1]['o']; cl = [b['c'] for _, b in bs]; pT = cl[-1]; adr = h['adr']
        if not adr or adr <= 0: return None
        f5 = [b['c'] for m, b in bs if m < 5]; lo, hi = min(cl), max(cl); vol = sum(b['v'] for _, b in bs)
        l30 = [b['c'] for m, b in bs if m <= Tm - 31]
        return dict(o=o, pT=pT, adr=adr, mv=pT / o - 1, gap=(o / h['pc'] - 1) / adr, prev=(h['pc'] / h['pc2'] - 1) / h['adr_prev'], f5=((max(f5) - min(f5)) / o) / adr if f5 else None,
                    pos=(pT - lo) / (hi - lo) if hi > lo else None, rv=vol / h['cum'][str(Tm)] if h['cum'].get(str(Tm)) else None, l30=(pT / l30[-1] - 1) / adr if (Tm >= 60 and l30) else None)
    spy = one('SPY'); out = {}
    if not spy: return out
    for s in hist:
        if s == 'SPY' or s in EXCLUDE: continue
        x = one(s)
        if not x: continue
        out[s] = {'move so far today': band1('move', x['mv'] / x['adr']), 'overnight gap': band1('gap', x['gap']), 'yesterday': band1('prev', x['prev']), 'first five minutes': band1('f5', x['f5']),
                  "place in today's range": band1('pos', x['pos']), 'volume so far': band1('rv', x['rv']), 'market so far (S&P 500 fund)': band1('mkt', spy['mv'] * 100),
                  'against the market': band1('rel', (x['mv'] - spy['mv']) / x['adr']), 'last 30 minutes': band1('l30', x['l30']), 'weekday': weekday, 'kind': 'fund' if s in FUNDS else 'share', 'always': 'any',
                  '_px': x['pT'], '_o': x['o'], '_adr': x['adr']}
    return out
# ---------------------------------------------------------------- trading
def exit_plan(r, day, cl):
    h = r['hold']; nxt = T.next_trading_day(day); t0 = T.at(day, *map(int, r['at'].split(':')))
    if h in ('30 minutes', '60 minutes', 'two hours'): return dict(at=(t0 + dt.timedelta(minutes={'30 minutes': 30, '60 minutes': 60, 'two hours': 120}[h])).isoformat())
    if h.startswith('overnight'): return dict(at=dt.datetime.combine(dt.date.fromisoformat(nxt), dt.time(9, 31), tzinfo=NY).isoformat()) if nxt else None
    if h.startswith("to the next day"): return dict(next_close=nxt) if nxt else None
    p = dict(at=(cl - dt.timedelta(minutes=3)).isoformat())
    if 'stop at a quarter' in h: p['stop'] = 0.25
    if 'bank at half' in h: p['target'] = 0.5
    return p
def enter(day, op, cl, st):
    rs = [r for r in rules() if r['id'] not in st['done']]; due = [r for r in rs if 0 <= (T.now() - T.at(day, *map(int, r['at'].split(':')))).total_seconds() < 150]
    if not due: return
    for r in due: st['done'].append(r['id'])
    T.jsave(os.path.join(LG, f'day_{day}.json'), st)                       # mark first: never double-enter
    if cl.time() != dt.time(16, 0) or not T.entries_allowed(): log(f"entries skipped ({'half day' if cl.time() != dt.time(16, 0) else 'entries blocked'}): {[r['id'] for r in due]}"); return
    hist = prep(day); syms = [s for s in hist if s != 'SPY'] + ['SPY']; today = bars_many(syms, op, T.now()); A = T.assets(); b = book(); busy = {p['sym'] for p in b['open']}
    for r in due:
        hh, mm = map(int, r['at'].split(':')); Tm = hh * 60 + mm - 570; F = facts_now(hist, today, Tm, day.strftime('%A'))
        hits = sorted(s for s, f in F.items() if all(f.get(k) == v for k, v in r['facts'].items()) and s not in busy)
        hits = [s for s in hits if T.can(A, s)[0] and (r['do'] == 'BUY' or T.can(A, s)[1])]
        random.Random(f"{day}{r['id']}").shuffle(hits); plan = exit_plan(r, day, cl); n = 0
        if not plan: log(f"{r['id']}: no exit date available, skipped"); continue
        for s in hits[:r.get('maxn', 10)]:
            px = F[s]['_px']; qty = max(1, int(r['stake'] // px)); side = 'buy' if r['do'] == 'BUY' else 'sell'
            sc, res = T.api('POST', '/orders', json={'symbol': s, 'qty': str(qty), 'side': side, 'type': 'market', 'time_in_force': 'day', 'client_order_id': f"lg-{r['id']}-{day:%Y%m%d}-{s}"})
            if sc < 300:
                b['open'].append(dict(rule=r['id'], sym=s, side=side, qty=qty, date=str(day), ref=px, order=res.get('id'), plan=plan, dist=F[s]['_adr'] * F[s]['_o'])); busy.add(s); n += 1
        save_book(b); log(f"{r['id']} at {r['at']}: {len(F)} shares read, {len(hits)} match, {n} orders sent")
def manage(day, cl):
    b = book(); keep = []; changed = False; now = T.now()
    watch = [p for p in b['open'] if p['plan'].get('stop') or p['plan'].get('target')]; last = {}
    if watch:
        snap = T.snapshots(sorted({p['sym'] for p in watch}))
        for s, v in snap.items():
            try: last[s] = v['minuteBar']['c']
            except Exception: pass
    for p in b['open']:
        if 'fill' not in p:
            sc, o = T.api('GET', f"/orders/{p['order']}")
            if sc == 200 and o.get('status') == 'filled' and o.get('filled_avg_price'): p['fill'] = float(o['filled_avg_price']); changed = True
            elif sc == 200 and o.get('status') in ('canceled', 'expired', 'rejected'): changed = True; log(f"{p['rule']} {p['sym']} entry {o['status']}: not a trade"); continue
        pl = p['plan']; why = None; sgn = 1 if p['side'] == 'buy' else -1
        due_at = pl['at'] if pl.get('at') else ((cl - dt.timedelta(minutes=3)).isoformat() if str(day) >= pl.get('next_close', '9999') else None)
        if due_at and now >= dt.datetime.fromisoformat(due_at): why = 'time'
        elif 'fill' in p and p['sym'] in last and p['date'] == str(day):
            mv = sgn * (last[p['sym']] - p['fill'])
            if pl.get('stop') and mv <= -pl['stop'] * p['dist']: why = 'stop'
            elif pl.get('target') and mv >= pl['target'] * p['dist']: why = 'banked'
        if why and 'fill' not in p:                                        # exit is due but the entry never filled: cancel it, not a trade
            T.api('DELETE', f"/orders/{p['order']}"); changed = True; log(f"{p['rule']} {p['sym']} entry never filled: cancelled, not a trade"); continue
        if why and int(abs(T.position_qty(p['sym']))) == 0:
            p['exit_why'] = 'no position left'; p['exit_date'] = str(day); b['closed'].append(p); changed = True; log(f"{p['rule']} {p['sym']} nothing held at exit time"); continue
        if why and 'fill' in p:
            qty = min(p['qty'], int(abs(T.position_qty(p['sym']))))
            sc, res = T.api('POST', '/orders', json={'symbol': p['sym'], 'qty': str(qty), 'side': 'sell' if sgn > 0 else 'buy', 'type': 'market', 'time_in_force': 'day',
                                                      'client_order_id': f"lgx-{p['rule']}-{now:%Y%m%d%H%M}-{p['sym']}"})
            if sc < 300: p['exit_order'] = res.get('id'); p['exit_why'] = why; p['exit_date'] = str(day); b['closed'].append(p); changed = True; continue
            log(f"{p['rule']} {p['sym']} exit refused {sc}")
        keep.append(p)
    for p in b['closed']:
        if p.get('pnl_usd') is None and p.get('exit_order'):
            s1, o1 = T.api('GET', f"/orders/{p['exit_order']}")
            if s1 == 200 and o1.get('status') == 'filled' and o1.get('filled_avg_price') and 'fill' in p:
                p['exit_fill'] = float(o1['filled_avg_price']); p['pnl_usd'] = round((p['exit_fill'] - p['fill']) * float(o1['filled_qty']) * (1 if p['side'] == 'buy' else -1), 2); changed = True
    if changed or len(keep) != len(b['open']): b['open'] = keep; save_book(b)
def report():
    b = book(); rs = rules(); day = str(T.now().date()); L = ['# League rules on the practice account (paper only)', '', f'updated {T.now():%Y-%m-%d %H:%M} New York', '',
        '| rule | in one sentence | settled trades | of 100 | profit $ | open now |', '|---|---|---|---|---|---|']
    tot = 0.0
    for r in rs:
        c = [p for p in b['closed'] if p['rule'] == r['id'] and p.get('pnl_usd') is not None]; s = sum(p['pnl_usd'] for p in c); tot += s
        L.append(f"| {r['id']} | {r['sentence']} | {len(c)} | {min(len(c), 100)}% | {s:+.2f} | {sum(1 for p in b['open'] if p['rule'] == r['id'])} |")
    L += ['', f'League rules total: {tot:+.2f}']
    with open(os.path.join(LG, 'league_paper.md'), 'w') as f: f.write('\n'.join(L) + '\n')
    names = {r['id']: r['sentence'] for r in rs}; Tn = ['# Paper trades today (league rules)', '', f'{day}', '', '| time | share | side | shares | in | out | why | result $ | rule |', '|---|---|---|---|---|---|---|---|---|']
    for p in [x for x in b['closed'] if x.get('exit_date') == day or x.get('date') == day] + [x for x in b['open'] if x.get('date') == day]:
        Tn.append(f"| {p['date']} | {p['sym']} | {p['side']} | {p['qty']} | {p.get('fill', '')} | {p.get('exit_fill', 'open')} | {p.get('exit_why', '')} | {p.get('pnl_usd', '')} | {names.get(p['rule'], p['rule'])[:90]} |")
    with open(os.path.join(LG, 'league_trades_today.md'), 'w') as f: f.write('\n'.join(Tn) + '\n')
def run():
    t = T.now(); day = t.date(); cal = T.calendar_day(day)
    if cal in ('ERR', None) or not cal: return
    op = T.at(day, *map(int, cal['open'].split(':'))); cl = T.at(day, *map(int, cal['close'].split(':')))
    st = T.jload(os.path.join(LG, f'day_{day}.json'), {'date': str(day), 'done': []})
    if not rules(): return
    if op - dt.timedelta(minutes=25) <= t < op and 'prep' not in st['done']:
        st['done'].append('prep'); T.jsave(os.path.join(LG, f'day_{day}.json'), st); prep(day)
    if op <= t <= cl:
        enter(day, op, cl, st); manage(day, cl)
        if t.minute % 5 == 0 or t >= cl - dt.timedelta(minutes=4): report()
    elif cl < t <= cl + dt.timedelta(minutes=20): manage(day, cl); report()
def parity():
    """Proof that the live executor reads the same facts as the test: recompute the last tested day from the broker's own bars
    and compare every band with what the test engine wrote for that day."""
    import csv
    rows = list(csv.DictReader(open(os.path.join(LG, 'parity_A.csv'))))
    if not rows: print('no parity file'); return
    day = dt.date.fromisoformat(rows[0]['date'][:10]); hist = prep(day); op = T.at(day, 9, 30); syms = [s for s in hist]
    today = bars_many(syms, op, op + dt.timedelta(minutes=390)); agree = {}; total = {}; shown = 0
    for tm in sorted({r['time'] for r in rows}):
        hh, mm = map(int, tm.split(':')); F = facts_now(hist, today, hh * 60 + mm - 570, day.strftime('%A'))
        for r in rows:
            if r['time'] != tm or r['sym'] not in F: continue
            for k in FACT_BAND:
                if k not in r: continue
                want = r[k] or None; got = F[r['sym']].get(k); total[k] = total.get(k, 0) + 1; agree[k] = agree.get(k, 0) + (want == got)
                if want != got and shown < 6: shown += 1; print('  differs:', tm, r['sym'], k, '| test:', want, '| live:', got)
    print('parity day', day, '| shares compared', len({r['sym'] for r in rows} & set(hist)))
    for k in total: print(f"  {k}: {100 * agree[k] / total[k]:.1f}% the same ({total[k]} checks)")
if __name__ == '__main__':
    os.makedirs(LG, exist_ok=True); lk = open(os.path.join(LG, 'bot.lock'), 'w')
    try: fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError: sys.exit(0)
    T.H = T._creds()
    if '--parity' in sys.argv: parity(); sys.exit(0)
    try: run()
    except Exception: log('LEAGUE BOT ERROR ' + traceback.format_exc()[-700:])
