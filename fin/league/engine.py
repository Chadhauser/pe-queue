# FINANCIAL LEAGUE ENGINE (CEO order 27 Nov 2026). One test for every way of earning, on every price series held:
#   real prices; entry two minutes AFTER the signal (the fill delay measured on the practice account); real costs per market;
#   a way passes only if it beats its costs in BOTH halves of history, on 200+ separate days, with a day-clustered t of 3.5+
#   (the bar for a sweep of thousands). No rule is chosen in advance: every time of day x every fact x every pair of facts x
#   every way out. Usage: python3 engine.py A|C|D <out_dir>.   A = shares and funds (minute), C = crypto, D = currencies and gold.
import sys, os, json, math, itertools, warnings; warnings.filterwarnings('ignore')
import numpy as np, pandas as pd
sys.path.insert(0, '/root/pe-fin'); sys.path.insert(0, '/root/pe-fin/team'); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bands import BANDS, band, FUNDS
MIN_DAYS, T_BAR = 200, 3.5
def score(X, ycols, feats, total_days, mid, stake, maxn, days_month, universe, tkey='time'):
    """X: one row per possible trade with date, time, feature bands, cost (bps) and outcome columns (bps).
    ycols: [(hold name, column, mode, overlap)] mode 'both' = direction read from the data, 'long'/'short' = column is already that side.
    Every cell is reduced to one number per day first (so a busy day counts once), then judged across days."""
    out = []; tested = 0; yraw = list(dict.fromkeys(c for _, c, _, _ in ycols)); X = X.copy(); has_x = all(c + '_x' in X.columns for c in yraw)
    for c in yraw:
        bad = X[c].abs() >= 5000; X.loc[bad, c] = np.nan
        if has_x: X.loc[bad, c + '_x'] = np.nan
    yn = yraw + ([c + '_x' for c in yraw] if has_x else [])
    combos = [(f,) for f in feats] + list(itertools.combinations(feats, 2))
    for combo in combos:
        if set(combo) == {'kind', 'which'} or (len(combo) == 2 and 'always' in combo): continue
        keys = [tkey] + list(combo); b = X.dropna(subset=list(combo))
        if not len(b): continue
        g0 = b.groupby(['date'] + keys, observed=True); dm = g0[yn + ['cost']].mean().reset_index(); cn = g0[yn].count().reset_index()
        first = dm.date < mid; G = dm.groupby(keys, observed=True)
        nd = G[yn].count(); m = G[yn].mean(); sd = G[yn].std(ddof=1); c_all = G['cost'].mean()
        m1 = dm[first].groupby(keys, observed=True)[yn].mean().reindex(m.index); m2 = dm[~first].groupby(keys, observed=True)[yn].mean().reindex(m.index)
        c1 = dm[first].groupby(keys, observed=True)['cost'].mean().reindex(m.index); c2 = dm[~first].groupby(keys, observed=True)['cost'].mean().reindex(m.index)
        cg = cn.groupby(keys, observed=True)[yn]; tot = cg.sum().reindex(m.index); cn_pos = cn.copy(); cn_pos[yn] = cn_pos[yn].replace(0, np.nan); per = cn_pos.groupby(keys, observed=True)[yn].mean().reindex(m.index)
        for hname, rawcol, mode, overlap in ycols:
            col = rawcol + '_x' if has_x else rawcol
            tested += len(m) * (2 if mode == 'both' else 1)
            sgn = np.sign(m[col]) if mode == 'both' else pd.Series(1.0, index=m.index)
            t = m[col].abs() / (sd[col] / np.sqrt(nd[col])) / math.sqrt(overlap); h1 = sgn * m1[col] - c1; h2 = sgn * m2[col] - c2
            ok = (nd[col] >= MIN_DAYS) & (t >= T_BAR) & (h1 > 0) & (h2 > 0) & ((m[col] > 0) if mode != 'both' else True)
            if has_x: ok = ok & ((sgn * m1[rawcol] - c1) > 0) & ((sgn * m2[rawcol] - c2) > 0)
            for key in m.index[ok.fillna(False).values]:
                k = key if isinstance(key, tuple) else (key,); n_ = int(nd[col][key]); net = abs(m[col][key]) - c_all[key]; pdx = min(maxn, per[col][key])
                side = ('BUY' if sgn[key] > 0 else 'SELL SHORT') if mode == 'both' else ('BUY' if mode == 'long' else 'SELL SHORT')
                out.append(dict(universe=universe, at=k[0], facts=json.dumps(dict(zip(combo, k[1:]))), do=side, hold=hname, days=n_, trades=int(tot[col][key]), per_day=round(float(pdx), 2),
                                trades_month=round(float(pdx) * n_ / total_days * days_month, 1), net_bps=round(float(net), 1), half1=round(float(h1[key]), 1), half2=round(float(h2[key]), 1), t=round(float(t[key]), 2),
                                usd_month=round(float(net) / 1e4 * stake * float(pdx) * n_ / total_days * days_month), stake=stake))
    return out, tested
def finish(name, out, tested, outdir, extra=''):
    os.makedirs(outdir, exist_ok=True); T = pd.DataFrame(out)
    T.to_csv(f'{outdir}/league_{name}.csv', index=False); json.dump(dict(tested=tested, passing=len(T), note=extra), open(f'{outdir}/league_{name}.json', 'w'))
    print(f'universe {name}: ways tested {tested} | passing {len(T)} | {extra}')
    if len(T):
        pd.set_option('display.width', 330); pd.set_option('display.max_colwidth', 110); pd.set_option('display.max_rows', 100)
        print(T.groupby(['do', 'hold']).size().to_string()); print(T.sort_values('usd_month', ascending=False).head(30).drop(columns=['universe', 'stake', 'trades']).to_string(index=False))
# ---------------------------------------------------------------- A: shares and funds, minute bars, regular session
def run_A(outdir):
    os.makedirs(outdir, exist_ok=True)
    import mech2
    TS = [5, 15, 30, 60, 90, 120, 180, 240, 300, 330, 360]; NM = {t: f'{(570 + t) // 60:02d}:{(570 + t) % 60:02d}' for t in TS}
    syms = sorted(s for s in os.listdir('/root/pe-data/alpaca') if 'USD' not in s); D = {}; rows = []
    def prep(s):
        b = mech2.bars(s)
        if b is None or len(b) < 50000: return None
        g = b.groupby('d'); n = g.size(); ok = n[n >= 300].index
        P = b.pivot_table(index='d', columns='mi', values='close', aggfunc='last').reindex(index=ok, columns=range(390)).ffill(axis=1).bfill(axis=1)
        V = b.pivot_table(index='d', columns='mi', values='volume', aggfunc='sum').reindex(index=ok, columns=range(390)).fillna(0).cumsum(axis=1)
        O = g.open.first().reindex(ok); Hh = g.high.max().reindex(ok); Ll = g.low.min().reindex(ok)
        return P, V, O, Hh, Ll
    spy = prep('SPY'); spy_mv = {t: (spy[0][t - 1] / spy[2] - 1) for t in TS}
    for s in syms:
        try:
            r = prep(s)
            if r is None: continue
            P, V, O, Hh, Ll = r; C = P[389]; adr = ((Hh - Ll) / O).rolling(20, min_periods=10).mean().shift(1); pc = C.shift(1)
            gapn = (O / pc - 1) / adr; prevn = (pc / C.shift(2) - 1) / adr.shift(1); f5n = ((P.iloc[:, :5].max(axis=1) - P.iloc[:, :5].min(axis=1)) / O) / adr
            nxtO = O.shift(-1); nxtC = P[387].shift(-1); Pv = P.values; cost = 3.0 if s in FUNDS else 6.0
            for T in TS:
                pT = P[T - 1]; e = P[T + 1]; mv = pT / O - 1; moven = mv / adr
                lo = P.iloc[:, :T].min(axis=1); hi = P.iloc[:, :T].max(axis=1); pos = (pT - lo) / (hi - lo).replace(0, np.nan)
                rv = V[T - 1] / V[T - 1].rolling(20, min_periods=10).mean().shift(1)
                sm = spy_mv[T].reindex(P.index); rel = (mv - sm) / adr
                d = pd.DataFrame({'date': pd.to_datetime(P.index), 'sym': s, 'time': NM[T], 'cost': cost,
                                  'move so far today': band('move', moven), 'overnight gap': band('gap', gapn), 'yesterday': band('prev', prevn), 'first five minutes': band('f5', f5n),
                                  'place in today\'s range': band('pos', pos), 'volume so far': band('rv', rv), 'market so far (S&P 500 fund)': band('mkt', sm / adr.clip(lower=1e-6) * 0 + sm * 100),
                                  'against the market': band('rel', rel), 'weekday': pd.to_datetime(P.index).day_name(), 'kind': 'fund' if s in FUNDS else 'share', 'always': 'any'}, index=P.index)
                if T >= 60: d['last 30 minutes'] = band('l30', (pT / P[T - 31] - 1) / adr)
                else: d['last 30 minutes'] = np.nan
                for h in (30, 60, 120):
                    if T + 1 + h <= 387: d[f'y{h}'] = (P[T + 1 + h] / e - 1) * 1e4
                d['yclose'] = (P[387] / e - 1) * 1e4; d['yon'] = (nxtO / e - 1) * 1e4; d['ync'] = (nxtC / e - 1) * 1e4
                W = Pv[:, T + 2:388]; ev = e.values[:, None]; sdist = (0.25 * adr * O).values[:, None]; gdist = (0.5 * adr * O).values[:, None]; last = P[387].values
                for sgn, tag in ((1, 'L'), (-1, 'S')):
                    sh = sgn * (W - ev) <= -sdist; th = sgn * (W - ev) >= gdist
                    i_s = np.where(sh.any(axis=1), sh.argmax(axis=1), 10 ** 6); i_t = np.where(th.any(axis=1), th.argmax(axis=1), 10 ** 6)
                    plain = sgn * (last / e.values - 1); nW = W.shape[1]; rws = np.arange(len(W))
                    # exits are market orders sent after the breaching minute closes and filled about two minutes later: use that price, not the stop level
                    stopv = sgn * (W[rws, np.minimum(np.where(i_s < 10 ** 6, i_s, 0) + 2, nW - 1)] / e.values - 1); tgtv = sgn * (W[rws, np.minimum(np.where(i_t < 10 ** 6, i_t, 0) + 2, nW - 1)] / e.values - 1)
                    d[f'y{tag}_stop'] = np.where(i_s < 10 ** 6, stopv, plain) * 1e4
                    d[f'y{tag}_st'] = np.where((i_s < i_t), stopv, np.where(i_t < 10 ** 6, tgtv, plain)) * 1e4
                    d[f'y{tag}_tgt'] = np.where(i_t < 10 ** 6, tgtv, plain) * 1e4
                rows.append(d.dropna(subset=['move so far today', 'yclose']))
        except Exception as ex: print('skip', s, str(ex)[:90])
    X = pd.concat(rows, ignore_index=True); days = np.sort(X.date.unique()); mid = days[len(days) // 2]
    # The share list is today's well-known names, so history flatters every BUY (they are the ones that went up). Each share is
    # therefore also scored against the average of ALL shares at the same moment; a way must pass on both measures. Funds are not adjusted.
    ycs = [c for c in X.columns if c.startswith('y') and c != 'yesterday']; sh = X.kind == 'share'
    mu = X[sh].groupby(['date', 'time'])[ycs].transform('mean')
    for c in ycs: X[c + '_x'] = X[c]; X.loc[sh, c + '_x'] = X.loc[sh, c] - mu[c]
    print('A rows', len(X), 'symbols', X.sym.nunique(), 'days', len(days), str(days[0])[:10], 'to', str(days[-1])[:10])
    feats = ['always', 'move so far today', 'overnight gap', 'yesterday', 'first five minutes', "place in today's range", 'volume so far', 'market so far (S&P 500 fund)', 'against the market', 'last 30 minutes', 'weekday', 'kind']
    ycols = [('30 minutes', 'y30', 'both', 1), ('60 minutes', 'y60', 'both', 1), ('two hours', 'y120', 'both', 1), ('to the close', 'yclose', 'both', 1), ('overnight to the next open', 'yon', 'both', 1), ('to the next day\'s close', 'ync', 'both', 2)]
    for tag, mode in (('L', 'long'), ('S', 'short')):
        ycols += [('to the close, stop at a quarter of a normal day\'s range', f'y{tag}_stop', mode, 1), ('to the close, stop at a quarter and bank at half a normal day\'s range', f'y{tag}_st', mode, 1), ('to the close, bank at half a normal day\'s range', f'y{tag}_tgt', mode, 1)]
    X[X.date == days[-1]][['date', 'sym', 'time'] + [f for f in feats if f not in ('always',)]].to_csv(os.path.join(outdir, 'parity_A.csv'), index=False)   # for the live-executor parity check
    out, tested = score(X, ycols, feats, len(days), mid, 10000.0, 10, 21, 'shares and funds')
    finish('A', out, tested, outdir, f'{X.sym.nunique()} shares and funds, {len(days)} days, entry 2 minutes after the signal, cost 3 (funds) / 6 (shares) hundredths of a percent a round trip')
# ---------------------------------------------------------------- C and D: round-the-clock markets, hourly decisions
def run_24(outdir, name):
    if name == 'C': from alpaca_load import load; syms = ['BTCUSD', 'ETHUSD', 'SOLUSD']; stake, dm, uni = 5000.0, 30, 'crypto'
    else: from oanda_load import load; syms = ['EUR_USD', 'GBP_USD', 'USD_JPY', 'AUD_USD', 'USD_CAD', 'XAU_USD']; stake, dm, uni = 20000.0, 22, 'currencies and gold'
    rows = []; ctx = None
    for s in syms:
        b = load(s)
        if not len(b): print('no data', s); continue
        c = b.close; idx = pd.date_range(c.index[0].ceil('h'), c.index[-1].floor('h'), freq='h')
        def at(off_min):
            t = idx + pd.Timedelta(minutes=off_min); v = c.reindex(t, method='ffill', tolerance=pd.Timedelta(minutes=5)); v.index = idx; return v
        sig = at(-1); e = at(2); dly = b.resample('1D').agg({'open': 'first', 'high': 'max', 'low': 'min'}).dropna()
        adr = ((dly.high - dly.low) / dly.open).rolling(20, min_periods=10).mean().shift(1); adr_h = adr.reindex(idx.floor('D')).values
        hi24 = sig.rolling(24, min_periods=12).max(); lo24 = sig.rolling(24, min_periods=12).min()
        d = pd.DataFrame({'date': idx.floor('D').tz_localize(None), 'sym': s, 'time': [f'{h:02d}:00 UTC' for h in idx.hour], 'which': s.replace('_', '/').replace('USD', '/USD') if name == 'C' else s.replace('_', '/'),
                          'last hour': band('h1', (sig / sig.shift(1) - 1).values / adr_h), 'last 4 hours': band('h4', (sig / sig.shift(4) - 1).values / adr_h), 'last 24 hours': band('h24', (sig / sig.shift(24) - 1).values / adr_h),
                          'place in the last 24 hours\' range': band('pos', ((sig - lo24) / (hi24 - lo24).replace(0, np.nan)).values), 'weekday': idx.day_name(), 'always': 'any'}, index=idx)
        if name == 'C': d['cost'] = 55.0
        else:
            sp = b.spread.reindex(idx + pd.Timedelta(minutes=2), method='ffill', tolerance=pd.Timedelta(minutes=5)); sp.index = idx; d['cost'] = (sp / e * 1e4).values + 0.5
        for h in (1, 4, 12, 24, 48, 72, 168): d[f'y{h}'] = ((at(h * 60 + 2) / e - 1) * 1e4).values
        d['last 3 days'] = band('h24', (sig / sig.shift(72) - 1).values / adr_h / 1.7); d['last 7 days'] = band('h24', (sig / sig.shift(168) - 1).values / adr_h / 2.6)
        if s in ('BTCUSD', 'EUR_USD'): ctx = d[['last 24 hours']].rename(columns={'last 24 hours': 'bitcoin last 24 hours' if name == 'C' else 'euro last 24 hours'})
        rows.append(d.dropna(subset=['last 24 hours', 'y1', 'cost']))
    X = pd.concat(rows); cn = ctx.columns[0]; X[cn] = ctx[cn].reindex(X.index).values; X = X.reset_index(drop=True)
    days = np.sort(X.date.unique()); mid = days[len(days) // 2]; print(name, 'rows', len(X), 'days', len(days), str(days[0])[:10], 'to', str(days[-1])[:10], 'average cost', round(X.cost.mean(), 1))
    feats = ['always', 'last hour', 'last 4 hours', 'last 24 hours', "place in the last 24 hours' range", 'weekday', 'which', cn]
    ycols = [('one hour', 'y1', 'both', 1), ('4 hours', 'y4', 'both', 1), ('12 hours', 'y12', 'both', 1.5), ('24 hours', 'y24', 'both', 2)]
    feats += ['last 3 days', 'last 7 days']; ycols += [('2 days', 'y48', 'both', 3), ('3 days', 'y72', 'both', 4), ('7 days', 'y168', 'both', 8)]
    out, tested = score(X, ycols, feats, len(days), mid, stake, 3 if name == 'C' else 6, dm, uni)
    finish(name, out, tested, outdir, f'{len(syms)} instruments, {len(days)} days, hourly decisions, entry 2 minutes after the hour, average cost {X.cost.mean():.1f} hundredths of a percent a round trip')
if __name__ == '__main__':
    m = sys.argv[1]; od = sys.argv[2] if len(sys.argv) > 2 else '/root/pe-finq/state/league'
    run_A(od) if m == 'A' else run_24(od, m)
