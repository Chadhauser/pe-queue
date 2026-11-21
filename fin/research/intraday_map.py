# DATA-LED INTRADAY MAP (Peter 21 Nov: "add and test all you can"). Every share and fund we hold minute prices for, every day since
# 2020: at five moments of the day (09:35, 10:00, 10:30, 11:30, 15:00 New York) describe what is known (overnight gap, move so far
# today, yesterday, size of the first five minutes, weekday, fund or share), then score what the price did next (to the next moment
# and to the close). No rule chosen in advance. A cell survives only with 200+ days, both halves beating cost, day-clustered t 3.5+.
import sys, os, math, itertools, warnings; warnings.filterwarnings('ignore')
import numpy as np, pandas as pd
sys.path.insert(0, '/root/pe-fin'); sys.path.insert(0, '/root/pe-fin/team')
import mech2
COST = 4.0; STAKE = 10000.0; FX = 0.77; MAXN = 10; TS = [5, 30, 60, 120, 330]; NAMES = {5: '09:35', 30: '10:00', 60: '10:30', 120: '11:30', 330: '15:00'}
FUNDS = {'SPY', 'QQQ', 'IWM', 'DIA', 'TQQQ', 'SQQQ', 'ARKK', 'GLD', 'TLT', 'XLF', 'XLE', 'XLK', 'SMH', 'EEM', 'HYG', 'USO', 'SLV', 'VXX', 'UVXY', 'SOXL', 'SOXS'}
syms = sorted(s for s in os.listdir('/root/pe-data/alpaca') if 'USD' not in s); rows = []
for s in syms:
    try:
        b = mech2.bars(s)
        if b is None or len(b) < 50000: continue
        b = b[(b.mi >= 0) & (b.mi < 390)]; g = b.groupby('d')
        day = pd.DataFrame({'open': g.open.first(), 'close': g.close.last(), 'high': g.high.max(), 'low': g.low.min(), 'n': g.size()})
        day = day[day.n >= 300]
        px = b.pivot_table(index='d', columns='mi', values='close', aggfunc='last').reindex(day.index).ffill(axis=1)
        f5 = b[b.mi < 5].groupby('d').agg(h=('high', 'max'), l=('low', 'min')).reindex(day.index)
        prev = day.close.shift(1); adr = ((day.high - day.low) / day.open).rolling(20, min_periods=10).mean().shift(1)
        base = pd.DataFrame({'date': pd.to_datetime(day.index), 'sym': s, 'gapn': (day.open / prev - 1) / adr, 'prevn': (prev / day.close.shift(2) - 1) / adr.shift(1),
                             'f5n': ((f5.h - f5.l) / day.open) / adr, 'adr': adr.values}, index=day.index)
        for i, T in enumerate(TS):
            if T - 1 not in px.columns: continue
            pT = px[T - 1]; nxt = px[TS[i + 1] - 1] if i + 1 < len(TS) and TS[i + 1] - 1 in px.columns else day.close
            r = base.copy(); r['T'] = NAMES[T]; r['moven'] = (pT / day.open - 1) / adr; r['y_close'] = (day.close / pT - 1) * 1e4; r['y_next'] = (nxt / pT - 1) * 1e4
            rows.append(r.dropna(subset=['adr', 'moven', 'y_close']))
    except Exception as e: print('skip', s, str(e)[:80])
L = pd.concat(rows, ignore_index=True); print('symbols', L.sym.nunique(), 'rows', len(L), 'days', L.date.nunique(), str(L.date.min())[:10], 'to', str(L.date.max())[:10])
def band(s, edges, names): return pd.cut(s, [-np.inf] + edges + [np.inf], labels=names).astype(object)
M7 = ['down a full day range+', 'down half to one range', 'down a little', 'flat', 'up a little', 'up half to one range', 'up a full day range+']
X = pd.DataFrame({'date': L.date, 'time': L['T']})
X['move so far today'] = band(L.moven, [-1, -0.5, -0.15, 0.15, 0.5, 1], M7)
X['overnight gap'] = band(L.gapn, [-0.5, -0.15, 0.15, 0.5], ['big gap down', 'gap down', 'no gap', 'gap up', 'big gap up'])
X['yesterday'] = band(L.prevn, [-0.7, -0.2, 0.2, 0.7], ['big down day', 'down day', 'flat day', 'up day', 'big up day'])
X['first five minutes'] = band(L.f5n, [0.12, 0.25, 0.4], ['tiny', 'normal', 'wide', 'very wide'])
X['weekday'] = L.date.dt.day_name(); X['kind'] = np.where(L.sym.isin(FUNDS), 'fund', 'share'); X['which'] = np.where(L.sym.isin(['SPY', 'QQQ', 'IWM']), L.sym, 'other')
days = np.sort(L.date.unique()); mid = days[len(days) // 2]; OUT = []; tested = 0
feats = [c for c in X.columns if c not in ('date', 'time')]
for yname, y in (('to the close', L.y_close), ('to the next checkpoint', L.y_next)):
    base = X.assign(y=y.where(y.abs() < 3000)).dropna(subset=['y']); print(yname, 'all average %+.1f bps' % base.y.mean())
    for combo in [(f,) for f in feats] + list(itertools.combinations(feats, 2)):
        if set(combo) == {'kind', 'which'}: continue
        dm = base.dropna(subset=list(combo)).groupby(['date', 'time'] + list(combo)).y.agg(['mean', 'size']).reset_index()
        for key, cell in dm.groupby(['time'] + list(combo)):
            tested += 1; n = len(cell)
            if n < 200: continue
            m = cell['mean'].mean(); sd = cell['mean'].std(ddof=1)
            if not sd > 0: continue
            t = m / (sd / math.sqrt(n)); sgn = 1 if m > 0 else -1
            h1 = sgn * cell.loc[cell.date < mid, 'mean'].mean() - COST; h2 = sgn * cell.loc[cell.date >= mid, 'mean'].mean() - COST
            if abs(t) < 3.5 or not (h1 > 0 and h2 > 0): continue
            net = abs(m) - COST; per_day = min(MAXN, cell['size'].mean()); gbp = net / 1e4 * STAKE * per_day * n / len(days) * 21 * FX
            OUT.append(dict(at=key[0], what=' + '.join(f'{a}: {b_}' for a, b_ in zip(combo, key[1:])), do='BUY' if sgn > 0 else 'SELL SHORT', hold=yname, days=n, trades=int(cell['size'].sum()),
                            per_day=round(per_day, 1), net_bps=round(net, 1), half1=round(h1, 1), half2=round(h2, 1), t=round(abs(t), 1), gbp_month=round(gbp)))
T_ = pd.DataFrame(OUT); print('cells tested', tested, '| survivors', len(T_))
if len(T_):
    pd.set_option('display.width', 400); pd.set_option('display.max_colwidth', 95); pd.set_option('display.max_rows', 500)
    T_ = T_.sort_values('gbp_month', ascending=False); print(T_.groupby(['at', 'hold', 'do']).size().to_string())
    print('\nTOP 40 by pounds a month at $10,000 a trade, max 10 a day (after 4 bps cost)'); print(T_.head(40).to_string(index=False))
    print('\nTOP 15 by strength'); print(T_.sort_values('t', ascending=False).head(15).to_string(index=False))
    if len(sys.argv) > 1: T_.to_csv(sys.argv[1], index=False)
