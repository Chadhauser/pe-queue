import sys, datetime as dt
import numpy as np, pandas as pd, psycopg2, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/root/pe-queue/runner'); import creds
con = psycopg2.connect(creds.pg_local())
R = pd.read_sql("SELECT market_id, selection_id, won FROM finder_rresults", con)
W = {(m, int(s)): bool(x) for m, s, x in zip(R.market_id, R.selection_id, R.won)}
D = pd.read_sql("""SELECT market_id, selection_id, extract(epoch from captured_at)::float8 ts, extract(epoch from market_start)::float8 st, back_price::float8 b, lay_price::float8 l, mins_to_off::float8 m
    FROM finder_rlog WHERE inplay""", con).sort_values(['market_id', 'selection_id', 'ts'])
q = 1.1; rows = []
for (mid, sid), g in D.groupby(['market_id', 'selection_id'], sort=False):
    if (mid, int(sid)) not in W: continue
    b, l, ts = g.b.values, g.l.values, g.ts.values
    ok = np.where(~np.isnan(b))[0]
    if len(ok) < 2 or b[ok[0]] <= q: continue
    for i in ok[1:]:
        if b[i] <= q + 1e-9 and not np.isnan(l[i]) and l[i] <= b[i] * 1.05 + 1e-9:
            if i + 1 < len(ts) and ts[i + 1] - ts[i] <= 120 and not np.isnan(b[i + 1]):
                rows.append(dict(mid=mid, won=W[(mid, int(sid))], sb=b[i], sl=l[i], nb=b[i + 1], nl=l[i + 1], gap=ts[i + 1] - ts[i], secs=ts[i] - g.st.iloc[0]))
            break
X = pd.DataFrame(rows)
print('n', len(X), 'won', X.won.mean())
print('next back quantiles, winners', X[X.won].nb.quantile([.1, .5, .75, .9, 1]).round(2).to_dict())
print('next back quantiles, losers', X[~X.won].nb.quantile([.1, .5, .9, 1]).round(2).to_dict())
big = X[X.nb > 2]
print('next back above 2.0:', len(big), 'won', big.won.mean(), 'with next lay missing', big.nl.isna().mean(), 'median next lay', big.nl.median())
print(big.sort_values('nb', ascending=False).head(8).round(2).to_string(index=False))
print('next back <=2.0 only: n', int((X.nb <= 2).sum()), 'won', X[X.nb <= 2].won.mean(), 'implied', (1 / X[X.nb <= 2].nb).mean())
print('seconds after scheduled off at signal, median', X.secs.median())
A = pd.read_sql("""SELECT (captured_at at time zone 'UTC')::date d, count(*) rows_ip, count(distinct market_id) mk FROM finder_rlog WHERE inplay AND captured_at>='2026-10-28' GROUP BY 1 ORDER BY 1""", con)
print(A.to_string(index=False))
