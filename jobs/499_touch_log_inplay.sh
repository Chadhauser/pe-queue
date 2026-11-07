#!/bin/bash
# Finder item 392 (2026-11-07). Cross-check of item 380: first in-play touch of a low price, 30 s rows of finder_rlog, about 2,000 races item 380 never saw. Rule in the queue before this run. Does not replace item 382.
# Signal: first in-play row with back > Q, then the first later in-play row with back <= Q and lay <= back*1.05 (a real book, item 385's guard).
# NEXT, scored: back at the next row's back within 120 s, one tick adverse, to result. No next row, or next back too low to fill above 1.01, is no trade, counted. About 30 s late against item 380's 1 s, so a miss does not refute it.
# SAME, not graded: back at the signal row's back, one tick adverse: win rate against price, an upper read.
# Result finder_rresults, one winner only; other races not scored, counted. UNSEEN = off before 2 Nov 00:00 UTC, scored. 2 to 6 Nov (item 380's own days) printed apart.
set -o pipefail
python3 - <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys, time, datetime as dt
import numpy as np, pandas as pd, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs'); import creds
from lib_cand import step, back_settle, tstat, passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 100); pd.set_option('display.max_columns', 40)
T0 = time.time()
CUT = dt.datetime(2026, 11, 2, tzinfo=dt.timezone.utc).timestamp()
def signal(b, l, q):
    """Index of the first row with back <= q and a real book, after an earlier row with back > q. None if none. The first valid back must be above q."""
    ok = np.where(~np.isnan(b))[0]
    if len(ok) == 0 or b[ok[0]] <= q + 1e-9: return None
    for i in ok[1:]:
        if b[i] <= q + 1e-9 and not np.isnan(l[i]) and l[i] <= b[i] * 1.05 + 1e-9:
            return int(i)
    return None
def bk(p, w):
    a = step(p, -1); return np.nan if a <= 1.01 else back_settle(a, w)
n_ = np.nan
assert signal(np.array([1.5, 1.3, 1.09]), np.array([1.6, 1.4, 1.10]), 1.1) == 2
assert signal(np.array([1.09, 1.08]), np.array([1.10, 1.09]), 1.1) is None                # never seen above Q
assert signal(np.array([1.5, 1.09]), np.array([1.6, 3.0]), 1.1) is None                   # a touch on an empty lay side is junk
assert signal(np.array([1.5, 1.09, 1.08]), np.array([1.6, 3.0, 1.09]), 1.1) == 2          # skip the junk row, take the first real book, as the queue rule says
assert signal(np.array([n_, 1.5, n_, 1.1]), np.array([n_, 1.6, n_, 1.15]), 1.1) == 3      # 1.15 <= 1.1*1.05 = 1.155
assert abs(bk(1.10, True) - 0.882) < 1e-9 and bk(1.10, False) == -10.0 and np.isnan(bk(1.02, True))   # 1.10 fills 1.09: 0.9*0.98
print('known answers OK', flush=True)
con = psycopg2.connect(creds.pg_local()); cur = con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R = pd.read_sql("SELECT market_id, selection_id, won FROM finder_rresults", con)
w = R[R.won == True].groupby('market_id').size(); one = set(w[w == 1].index)
WON = {(m, int(s)): bool(x) for m, s, x in zip(R.market_id, R.selection_id, R.won) if m in one}
print(f'results markets {R.market_id.nunique():,}, one winner {len(one):,}', flush=True)
D = pd.read_sql("""SELECT market_id, selection_id, extract(epoch from captured_at)::float8 ts, extract(epoch from market_start)::float8 st, back_price::float8 b, lay_price::float8 l
    FROM finder_rlog WHERE inplay AND market_name !~* 'place|tbp'""", con)
D = D.sort_values(['market_id', 'selection_id', 'ts'])
print(f'in-play rows {len(D):,}, markets {D.market_id.nunique():,}, {time.time()-T0:.0f}s', flush=True)
gaps = D.groupby(['market_id', 'selection_id']).ts.diff().dropna(); print(f'median row gap {gaps.median():.1f} s, p90 {gaps.quantile(.9):.1f} s; median rows per runner {D.groupby(["market_id","selection_id"]).size().median():.0f}', flush=True)
rows = []; c = dict(noresult=0)
for (mid, sid), g in D.groupby(['market_id', 'selection_id'], sort=False):
    k = (mid, int(sid))
    if k not in WON: c['noresult'] += 1; continue
    ts, b, l = g.ts.values, g.b.values, g.l.values; st = float(g.st.iloc[0]); won = WON[k]
    for q in (1.1, 1.2, 1.5, 2.0):
        i = signal(b, l, q)
        if i is None: continue
        rec = dict(mid=mid, sid=int(sid), st=st, q=q, won=won, same=bk(b[i], won), px=b[i], nxt=np.nan, nxpx=np.nan, why='ok')
        if i + 1 >= len(ts) or ts[i + 1] - ts[i] > 120: rec['why'] = 'no next row'
        elif np.isnan(b[i + 1]): rec['why'] = 'next back empty'
        else:
            rec['nxt'] = bk(b[i + 1], won); rec['nxpx'] = b[i + 1]
            if rec['nxt'] != rec['nxt']: rec['why'] = 'next at the floor'
        rows.append(rec)
X = pd.DataFrame(rows); X['unseen'] = X.st < CUT
print(c, f'signals {len(X):,}', flush=True)
print(X.groupby(['q', 'why'])['won'].agg(['size', 'mean']).round(3).to_string(), flush=True)
T = []
for (u, q), g in X.groupby(['unseen', 'q']):
    for col in ('nxt', 'same'):
        h = g[g[col].notna()]
        if len(h) == 0: continue
        v = h[col].values; med = np.median(h.st.values); a = h[h.st <= med][col]; b2 = h[h.st > med][col]
        tr = tstat(h.groupby('mid')[col].mean().values); t = min(tr, tstat(v)); px = h.nxpx if col == 'nxt' else h.px
        T.append(dict(window='UNSEEN' if u else '2-6Nov', q=q, how=col.upper(), n=len(v), races=h.mid.nunique(), per10=v.mean(), t_race=tr, n1=len(a), h1=a.mean(), n2=len(b2), h2=b2.mean(), won=h.won.mean(), implied=(1 / px).mean(), losers=int((~h.won).sum()),
                      PASS=bool(u and col == 'nxt' and q in (1.1, 1.2) and passes(len(v), len(a), len(b2), t, a.mean(), b2.mean(), v.mean()))))
T = pd.DataFrame(T); print(T.sort_values(['window', 'how', 'q']).round(3).to_string(index=False))
print('\n== SURVIVORS'); S = T[T.PASS]
print(S.round(3).to_string(index=False) if len(S) else 'none'); print(f'time {time.time()-T0:.0f}s')
PY
