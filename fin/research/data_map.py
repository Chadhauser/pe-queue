# DATA-LED MAP (Peter 21 Nov: "are you testing the data not just your own rules?"). No rule is chosen in advance: every share-day in
# the small-company history is described by what was known at the moment of entry, cut into bands, and every band and every PAIR of
# bands is scored on what the price did next. Costs are OUR OWN measured fills (17-20 Nov: 26 bps in + 30 bps out = 60 bps round trip
# after rounding). A cell survives only if it clears costs in BOTH halves of the history with the same sign, on 200+ days, with a
# day-clustered t of 3.5+ (the bar for a sweep). Read-only: prints only.
import sys, math, itertools, warnings; warnings.filterwarnings('ignore')
import numpy as np, pandas as pd
COST = 60.0; STAKE = 500.0; FX = 0.77; MAXN = 30
D = pd.read_parquet('/root/pe-data/crumbs/daily_all.parquet'); print('columns', list(D.columns), 'rows', len(D))
D.columns = [c.lower() for c in D.columns]
if 'sym' not in D.columns: D = D.rename(columns={'symbol': 'sym', 'ticker': 'sym'})
small = set(pd.read_csv('/root/pe-data/crumbs/universe_small.csv', index_col=0).index)
D = D[D.sym.isin(small)].copy(); D['date'] = pd.to_datetime(D.date); D = D.sort_values(['sym', 'date']).reset_index(drop=True)
g = D.groupby('sym'); has = lambda c: c in D.columns
D['prev'] = g.close.shift(1); D['gap'] = D.open / D.prev - 1; D['cc'] = D.close / D.prev - 1; D['oc'] = D.close / D.open - 1
D['nopen'] = g.open.shift(-1); D['nclose'] = g.close.shift(-1); D['c5f'] = g.close.shift(-5)
D['co'] = D.nopen / D.close - 1; D['c1'] = D.nclose / D.close - 1; D['c5'] = D.c5f / D.close - 1; D['no_oc'] = D.nclose / D.nopen - 1
for k in (5, 20, 60): D[f'r{k}'] = D.close / g.close.shift(k) - 1
D['hi60'] = D.close / g.close.transform(lambda s: s.rolling(60, min_periods=20).max()) - 1
if has('volume'):
    D['dv'] = D.close * D.volume; D['dv20'] = g.dv.transform(lambda s: s.rolling(20, min_periods=10).mean()); D['rv'] = D.dv / D.dv20
else: D['dv20'] = np.nan; D['rv'] = np.nan
D['rng'] = (D.high - D.low) / D.close if has('high') else np.nan
D['clv'] = (D.close - D.low) / (D.high - D.low).replace(0, np.nan) if has('high') else np.nan
P = lambda c: g[c].shift(1)                                              # yesterday's value: known before today's open
def band(s, edges, names): return pd.cut(s, [-np.inf] + edges + [np.inf], labels=names).astype(object)
R = ['down 10%+', 'down 3-10%', 'flat', 'up 3-10%', 'up 10%+']; RE = [-0.10, -0.03, 0.03, 0.10]
R5 = ['down 15%+', 'down 5-15%', 'flat', 'up 5-15%', 'up 15%+']; R5E = [-0.15, -0.05, 0.05, 0.15]
R20 = ['down 25%+', 'down 8-25%', 'flat', 'up 8-25%', 'up 25%+']; R20E = [-0.25, -0.08, 0.08, 0.25]
GAPN = ['gap down 5%+', 'gap down 2-5%', 'no gap', 'gap up 2-5%', 'gap up 5%+']; GAPE = [-0.05, -0.02, 0.02, 0.05]
# ---- what is known AT THE OPEN (entry at the open)
O = pd.DataFrame({'date': D.date, 'sym': D.sym})
O['opening gap'] = band(D.gap, GAPE, GAPN); O['yesterday'] = band(P('cc'), RE, R); O['last 5 days'] = band(P('r5'), R5E, R5); O['last 20 days'] = band(P('r20'), R20E, R20)
O['yesterday volume'] = band(P('rv'), [0.5, 1.5, 3.0], ['quiet', 'normal', 'busy 1.5-3x', 'very busy 3x+'])
O['yesterday range'] = band(P('rng'), [0.03, 0.06, 0.12], ['tight', 'normal', 'wide', 'very wide 12%+'])
O['yesterday finish'] = band(P('clv'), [0.2, 0.8], ['closed at low', 'mid', 'closed at high'])
O['vs 60-day high'] = band(P('hi60'), [-0.40, -0.15, -0.03], ['40%+ below', '15-40% below', '3-15% below', 'at high'])
O['share price'] = band(D.open, [5, 10, 20], ['$3-5', '$5-10', '$10-20', '$20+']); O['weekday'] = D.date.dt.day_name()
O['traded value'] = band(P('dv20'), [3e6, 10e6, 30e6], ['$1-3m', '$3-10m', '$10-30m', '$30m+'])
okO = (D.open >= 3) & (P('dv20') >= 1e6) & D.oc.notna() & D.gap.notna()
# ---- what is known AT THE CLOSE (entry at the close)
Cc = pd.DataFrame({'date': D.date, 'sym': D.sym})
Cc['today'] = band(D.cc, RE, R); Cc['today open to close'] = band(D.oc, RE, R); Cc['today gap'] = band(D.gap, GAPE, GAPN)
Cc['last 5 days'] = band(D.r5, R5E, R5); Cc['last 20 days'] = band(D.r20, R20E, R20)
Cc['today volume'] = band(D.rv, [0.5, 1.5, 3.0], ['quiet', 'normal', 'busy 1.5-3x', 'very busy 3x+'])
Cc['today finish'] = band(D.clv, [0.2, 0.8], ['closed at low', 'mid', 'closed at high'])
Cc['vs 60-day high'] = band(D.hi60, [-0.40, -0.15, -0.03], ['40%+ below', '15-40% below', '3-15% below', 'at high'])
Cc['share price'] = band(D.close, [5, 10, 20], ['$3-5', '$5-10', '$10-20', '$20+']); Cc['weekday'] = D.date.dt.day_name()
Cc['traded value'] = band(D.dv20, [3e6, 10e6, 30e6], ['$1-3m', '$3-10m', '$10-30m', '$30m+'])
okC = (D.close >= 3) & (D.dv20 >= 1e6) & D.cc.notna()
days = np.sort(D.date.unique()); mid = days[len(days) // 2]; print('days', len(days), str(days[0])[:10], 'to', str(days[-1])[:10], '| half split', str(mid)[:10], '| shares', D.sym.nunique())
OUT = []; tested = 0
def score(X, ok, y, yname, when, hold_days=1):
    global tested
    feats = [c for c in X.columns if c not in ('date', 'sym')]; Y = (D[y] * 1e4).where(ok & D[y].notna() & (D[y].abs() < 1.0))
    base = X.assign(y=Y).dropna(subset=['y'])
    for combo in [(f,) for f in feats] + list(itertools.combinations(feats, 2)):
        b = base.dropna(subset=list(combo)); 
        if not len(b): continue
        dm = b.groupby(['date'] + list(combo)).y.agg(['mean', 'size']).reset_index()
        for key, cell in dm.groupby(list(combo)):
            tested += 1; n = len(cell)
            if n < 200: continue
            m = cell['mean'].mean(); sd = cell['mean'].std(ddof=1)
            if not sd > 0: continue
            t = m / (sd / math.sqrt(n)) / math.sqrt(hold_days); sgn = 1 if m > 0 else -1
            h1 = sgn * cell.loc[cell.date < mid, 'mean'].mean() - COST; h2 = sgn * cell.loc[cell.date >= mid, 'mean'].mean() - COST
            if abs(t) < 3.5 or not (h1 > 0 and h2 > 0): continue
            net = abs(m) - COST; per_day = min(MAXN, cell['size'].mean()); freq = n / len(days)
            gbp = net / 1e4 * STAKE * per_day * freq * 21 / hold_days * FX
            key = key if isinstance(key, tuple) else (key,)
            OUT.append(dict(when=when, what=' + '.join(f'{a}: {b_}' for a, b_ in zip(combo, key)), do=('BUY' if sgn > 0 else 'SELL SHORT'), hold=yname, days=n,
                            trades=int(cell['size'].sum()), per_day=round(per_day, 1), net_bps=round(net), half1=round(h1), half2=round(h2), t=round(abs(t), 1), gbp_month=round(gbp)))
score(O, okO, 'oc', 'open to close', 'at the open')
score(Cc, okC, 'co', 'close to next open', 'at the close')
score(Cc, okC, 'c1', 'close to next close', 'at the close')
score(Cc, okC, 'no_oc', 'next open to next close', 'next open')
score(Cc, okC, 'c5', 'five days', 'at the close', hold_days=5)
T = pd.DataFrame(OUT); print('cells tested', tested, '| survivors', len(T))
if len(T):
    pd.set_option('display.width', 400); pd.set_option('display.max_colwidth', 90); pd.set_option('display.max_rows', 500)
    T = T.sort_values('gbp_month', ascending=False); print(T.groupby(['when', 'hold', 'do']).size().to_string())
    print('\nTOP 40 by pounds a month at $500 a share (after 60 bps measured cost)'); print(T.head(40).to_string(index=False))
    print('\nTOP 15 by strength (t)'); print(T.sort_values('t', ascending=False).head(15).to_string(index=False))
    T.to_csv(sys.argv[1], index=False) if len(sys.argv) > 1 else None
