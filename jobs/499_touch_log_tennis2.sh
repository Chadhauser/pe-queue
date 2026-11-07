#!/bin/bash
# Finder item 391 (2026-11-07). A tennis pre-off shock on a tight book, follow or fade, crossing, at the real 30 s touch, finder_tlog, 7 Sep to 6 Nov 2026. Closed before the off. Rule in the queue before this run.
# Trigger as item 129 at X5 and X10, first per market, book at the trigger row lay/back-1 <= 3%. Enter at the next row within 120 s at the real touch, one tick adverse. Out at the first touch 600 s on, else the last pre-off touch, one tick adverse.
set -o pipefail
python3 - <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys, time
import numpy as np, pandas as pd, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs'); import creds
from lib_cand import step, back_hedge, lay_hedge, tstat, passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 40)
T0 = time.time(); M = 60.0; PLO, PHI = 1.10, 20.0
def prints(ts, ltp):
    keep = []; last = None
    for i in range(len(ts)):
        v = ltp[i]
        if np.isnan(v): continue
        if last is None or v != last: keep.append(i); last = v
    return np.array(keep, dtype=int)
def triggers(tp, pp, st, x):
    """All prints x+ from the latest print 30 s to 300 s earlier, T-90 to T-5, as (index, +1 shortened / -1 drifted)."""
    out = []
    for i in range(1, len(tp)):
        m = (tp[i] - st) / M
        if m < -90: continue
        if m > -5: break
        if not (PLO <= pp[i] <= PHI): continue
        j = i - 1
        while j >= 0 and tp[i] - tp[j] < 30: j -= 1
        if j < 0 or tp[i] - tp[j] > 300: continue
        if abs(pp[i] / pp[j] - 1) >= x - 1e-12: out.append((i, 1 if pp[i] < pp[j] else -1))
    return out
def exit_row(ts, ref, b, l, side):
    col = b if side == 'L' else l
    ok = np.where(~np.isnan(col) & (ts > ref))[0]
    if len(ok) == 0: return None
    late = ok[ts[ok] >= ref + 600]
    return int(late[0]) if len(late) else int(ok[-1])
def pl(side, a, x): return lay_hedge(a, x) if side == 'L' else back_hedge(a, x)
t_ = np.array([0., 30., 60., 90.]) - 40 * M
assert triggers(t_, np.array([2.0, 2.0, 2.0, 1.8]), 0.0, 0.10) == [(3, 1)] and triggers(t_, np.array([2.0, 2.0, 2.0, 1.85]), 0.0, 0.10) == [] and triggers(t_, np.array([2.0, 2.0, 2.0, 1.9]), 0.0, 0.05) == [(3, 1)]
assert triggers(np.array([0., 400.]) - 40 * M, np.array([2.0, 1.5]), 0.0, 0.05) == []
assert abs(lay_hedge(step(2.0, 1), 2.0) - (10 / 1.02 * (1 - 2.02 / 1.99))) < 1e-9       # lay 2.0 fills 2.02, out at 2.0 backs 1.99: a loss, no commission
assert abs(back_hedge(step(2.0, -1), 2.0) - (10 * (1.99 / 2.02 - 1))) < 1e-9            # back 2.0 fills 1.99, out at 2.0 lays 2.02: a loss, no commission
print('known answers OK', flush=True)
con = psycopg2.connect(creds.pg_local()); cur = con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D = pd.read_sql("""SELECT market_id, selection_id, extract(epoch from captured_at)::float8 ts, extract(epoch from market_start)::float8 st,
     back_price::float8 b, lay_price::float8 l, last_traded::float8 ltp FROM finder_tlog
     WHERE NOT inplay AND captured_at>=market_start - interval '100 minutes' AND captured_at<market_start""", con)
D = D.sort_values(['market_id', 'selection_id', 'ts'])
print(f'pre-off rows {len(D):,}, markets {D.market_id.nunique():,}', flush=True)
rows = []; cnt = {}
for mid, gm in D.groupby('market_id', sort=False):
    st = float(gm.st.iloc[0])
    R = [(sid, g.ts.values, g.b.values, g.l.values, g.ltp.values) for sid, g in gm.groupby('selection_id', sort=False)]
    for X in (0.05, 0.10):
        best = None; anyt = 0
        for sid, ts, b, l, ltp in R:
            pi = prints(ts, ltp)
            if len(pi) < 2: continue
            tp, pp = ts[pi], ltp[pi]
            for i, d in triggers(tp, pp, st, X):
                anyt = 1; k = int(np.searchsorted(ts, tp[i], side='left'))
                if k < len(ts) and not np.isnan(b[k]) and not np.isnan(l[k]) and l[k] / b[k] - 1 <= 0.03 + 1e-12:
                    if best is None or tp[i] < best[0]: best = (tp[i], d, k, ts, b, l, pp[i])
                    break
        cnt[X] = cnt.get(X, [0, 0]); cnt[X][0] += anyt
        if best is None: continue
        cnt[X][1] += 1
        t, d, k, ts, b, l, px = best
        n = k + 1
        if n >= len(ts) or ts[n] - ts[k] > 120: continue
        fade = 'L' if d == 1 else 'B'
        for nm, sd in (('FADE', fade), ('FOLLOW', 'B' if fade == 'L' else 'L')):
            pn = l[n] if sd == 'L' else b[n]
            if np.isnan(pn): continue
            a = step(float(pn), 1 if sd == 'L' else -1)
            if a <= 1.01: continue
            e = exit_row(ts, ts[n], b, l, sd)
            if e is None: continue
            rows.append(dict(mid=mid, st=st, X=X, how=nm, d=d, px=px, pnl=pl(sd, a, b[e] if sd == 'L' else l[e])))
print({f'X{int(k*100)}': dict(markets_with_trigger=v[0], on_tight_book=v[1]) for k, v in cnt.items()}, flush=True)
Y = pd.DataFrame(rows); T = []
for (x, h), g in Y.groupby(['X', 'how']):
    v = g.pnl.values; med = np.median(g.st.values); a = g[g.st <= med].pnl; c = g[g.st > med].pnl; t = tstat(v)
    T.append(dict(X=x, how=h, n=len(v), per10=v.mean(), t=t, n1=len(a), h1=a.mean(), n2=len(c), h2=c.mean(), PASS=passes(len(v), len(a), len(c), t, a.mean(), c.mean(), v.mean())))
    for dd, gg in g.groupby('d'):
        T.append(dict(X=x, how=h + (' after short' if dd == 1 else ' after drift'), n=len(gg), per10=gg.pnl.mean(), t=tstat(gg.pnl.values), PASS=False))
T = pd.DataFrame(T); print(T.round(3).to_string(index=False))
print('\n== SURVIVORS'); S = T[T.PASS == True]
print(S.round(3).to_string(index=False) if len(S) else 'none'); print(f'time {time.time()-T0:.0f}s')
PY
