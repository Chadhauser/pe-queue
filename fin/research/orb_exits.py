# Opening break: same entry, different EXITS (Peter: a trade should bank a profit once it is green). 1,400 days per fund from minute
# bars, same cost as the history test ($0.03 a share). Read-only: prints only.
import sys, math, numpy as np, pandas as pd
sys.path.insert(0, '/root/pe-fin'); sys.path.insert(0, '/root/pe-fin/team')
import mech2
def run(sym, target=10.0, be_at=None, trail=None, tstop=None):
    b = mech2.bars(sym); COST = 0.03; out = {}
    for d, sess in b.groupby('d'):
        if len(sess) < 300: continue
        fb = sess[sess.mi < 5]; rest = sess[sess.mi >= 5]
        if len(fb) < 3 or not len(rest): continue
        o, c, hi, lo = fb.open.iloc[0], fb.close.iloc[-1], fb.high.max(), fb.low.min(); rng = hi - lo
        if rng <= 0 or abs(c - o) < 0.05 * rng: continue
        side = 1 if c > o else -1; entry = rest.open.iloc[0]; stop = lo if side > 0 else hi; R = abs(entry - stop)
        if R <= 0 or (side > 0 and stop >= entry) or (side < 0 and stop <= entry): continue
        tgt = entry + side * target * R; ex = rest.close.iloc[-1]; best = 0.0; cur = stop
        H = rest.high.values; L = rest.low.values; M = rest.mi.values; Cl = rest.close.values
        for i in range(len(H)):
            if tstop is not None and M[i] >= tstop: ex = Cl[i]; break
            lo_hit = (L[i] <= cur) if side > 0 else (H[i] >= cur)
            if lo_hit: ex = cur; break                                     # stop first (conservative when both in one bar)
            if (H[i] >= tgt) if side > 0 else (L[i] <= tgt): ex = tgt; break
            best = max(best, side * ((H[i] if side > 0 else L[i]) - entry) / R)
            if be_at is not None and best >= be_at: cur = max(cur, entry) if side > 0 else min(cur, entry)
            if trail is not None and best >= trail: nc = entry + side * (best - trail) * R; cur = max(cur, nc) if side > 0 else min(cur, nc)
        out[d] = (side * (ex - entry) - COST) / R
    return pd.Series(out).sort_index()
def rep(name, S):
    D = pd.DataFrame(S).fillna(0); s = D.sum(axis=1); allr = pd.concat(S.values()); h = len(s) // 2; eq = s.cumsum(); dd = (eq - eq.cummax()).min()
    w = s.rolling(5).sum(); t = s.mean() / (s.std(ddof=1) / math.sqrt(len(s)))
    runs = []; n = 0
    for x in (s > 0):
        if not x: n += 1
        else: runs.append(n); n = 0
    print('%-44s win %4.1f%% | avg %+.3f a trade | t %.2f | 1st half %+.3f 2nd half %+.3f per day | total %5.0f | deepest run down %6.1f | total/drawdown %4.1f | longest losing run %2d days | QQQ %+.3f SPY %+.3f IWM %+.3f' % (
        name, 100 * (allr > 0).mean(), allr.mean(), t, s[:h].mean(), s[h:].mean(), s.sum(), dd, s.sum() / abs(dd), max(runs + [n]), S['QQQ'].mean(), S['SPY'].mean(), S['IWM'].mean()))
V = [('as now: stop or hold to close (10x target)', {}), ('bank at 1x risk', dict(target=1)), ('bank at 2x risk', dict(target=2)), ('bank at 3x risk', dict(target=3)), ('bank at 5x risk', dict(target=5)),
     ('stop to entry price once 1x up', dict(be_at=1)), ('stop to entry once 2x up', dict(be_at=2)), ('trail 1x behind the best', dict(trail=1)), ('trail 2x behind the best', dict(trail=2)),
     ('stop to entry at 1x + bank at 3x', dict(be_at=1, target=3)), ('out by 11:30 if neither hit', dict(tstop=120)), ('out by 13:00 if neither hit', dict(tstop=210)),
     ('trail 2x + stop to entry at 1x', dict(be_at=1, trail=2))]
print('units = multiples of the amount risked per trade ($100 on practice); three funds together')
for name, kw in V: rep(name, {s: run(s, **kw) for s in ('QQQ', 'SPY', 'IWM')})
