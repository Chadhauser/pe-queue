#!/bin/bash
# Finder item 393 (2026-11-07). A horse at 1.1 whose back price then collapses past 2.0: real, or a dead book? stream_ticks racing WIN, in play, OPEN only. Rule in the queue before this run. Read only; temp tables only.
# First tick back <= 1.1 after a first in-play back above 1.1; then the first OPEN tick within 120 s with back >= 2.0. P&L at that back, one tick adverse, 2%, stake the lesser of £10 and the size shown, to result, one winner only.
set -o pipefail
python3 - <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys, time
import numpy as np, pandas as pd, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs'); import creds
from lib_cand import step, net
pd.set_option('display.width', 220); pd.set_option('display.max_rows', 80); pd.set_option('display.max_columns', 30)
T0 = time.time()
def pl(px, sz, won):
    a = step(px, -1); s = min(10.0, sz) if sz == sz else 0.0
    return net(s * (a - 1)) if won else -s
assert abs(pl(10.0, 100.0, True) - 10 * 8.8 * .98) < 1e-9 and pl(10.0, 100.0, False) == -10.0     # 10.0 fills 9.8
assert abs(pl(10.0, 2.0, True) - 2 * 8.8 * .98) < 1e-9 and pl(10.0, 2.0, False) == -2.0           # capped at the size shown
print('known answers OK', flush=True)
con = psycopg2.connect(creds.pg_local()); con.autocommit = True; cur = con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='1500s'")
cur.execute("""CREATE TEMP TABLE tmp_t AS SELECT market_id, sel_id, extract(epoch from pt)::float8 t, back_px::float8 back_px, lay_px::float8 lay_px, back_sz::float8 back_sz
    FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND status='OPEN' AND pt IS NOT NULL AND back_px IS NOT NULL""")
cur.execute("CREATE INDEX ON tmp_t (market_id, sel_id, t)"); cur.execute("ANALYZE tmp_t")
cur.execute("select count(*),count(distinct market_id),to_timestamp(min(t)),to_timestamp(max(t)) from tmp_t"); print('ticks, markets, from, to', cur.fetchone(), flush=True)
X = pd.read_sql("""WITH f AS (SELECT DISTINCT ON (market_id, sel_id) market_id, sel_id, back_px st FROM tmp_t ORDER BY market_id, sel_id, t),
    h AS (SELECT market_id, sel_id, min(t) tt FROM tmp_t WHERE back_px<=1.1 GROUP BY 1,2)
  SELECT h.market_id, h.sel_id, h.tt, j.t tj, j.back_px, j.lay_px, j.back_sz FROM h JOIN f USING (market_id, sel_id)
    LEFT JOIN LATERAL (SELECT x.t, x.back_px, x.lay_px, x.back_sz FROM tmp_t x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>h.tt AND x.t<=h.tt+120 AND x.back_px>=2.0 ORDER BY x.t LIMIT 1) j ON true
  WHERE f.st>1.1""", con)
R = pd.read_sql("SELECT market_id, selection_id sel_id, won FROM finder_rresults", con)
w = R[R.won == True].groupby('market_id').size(); R = R[R.market_id.isin(w[w == 1].index)]
X = X.merge(R, how='left', on=['market_id', 'sel_id'])
print(f'touches {len(X)}; with a result {X.won.notna().sum()}; result rows end at 6 Nov, so later races are not scored', flush=True)
print('all touches with a result, won', round(X[X.won.notna()].won.astype(bool).mean(), 3), flush=True)
J = X[X.tj.notna()].copy(); J['secs'] = J.tj - J.tt
print(f'collapsed past 2.0 within 120 s: {len(J)}, with a result {J.won.notna().sum()}', flush=True)
print(J.drop(columns=['tt', 'tj']).sort_values('secs').round(2).to_string(index=False))
S = J[J.won.notna()].copy()
if len(S):
    S['won'] = S.won.astype(bool); S['pnl'] = [pl(p, z, q) for p, z, q in zip(S.back_px, S.back_sz, S.won)]
    print(f'SCORED n {len(S)} won {S.won.mean():.3f} implied {(1/S.back_px).mean():.3f} sum £{S.pnl.sum():.2f} median size on show £{S.back_sz.median():.2f}; without the largest win £{S.pnl.sum()-S.pnl.max():.2f}')
print('\n== SURVIVORS: under n 300 by design, none')
print(f'time {time.time()-T0:.0f}s')
PY
