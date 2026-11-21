#!/bin/bash
# fin 008 (own runner): read-only — in the 1,397-trade opening-break history (Nasdaq 100 fund), how often do losing runs happen?
# Live paper has opened with 4 losing days in a row. No orders, no writes. Never prints the connection string.
cd /root/pe-fin || exit 1
python3 - <<'PY' 2>&1 | grep -v Warning
import re, os, warnings; warnings.filterwarnings('ignore')
import pandas as pd, psycopg2
src = open('orb_slices.py').read(); ns = {'os': os}
for ln in src.splitlines():
    if re.match(r'^(import |from )', ln):
        try: exec(ln, ns)
        except Exception: pass
    if re.match(r'^DB\s*=', ln): exec(ln, ns); break
con = psycopg2.connect(ns['DB'], sslmode='prefer')
T = pd.read_sql("SELECT date, r_mult, reason FROM orb_qqq_trades ORDER BY date", con); con.close()
r = T.r_mult.astype(float); w = r > 0
print('trades', len(T), 'win rate %.1f%%' % (100 * w.mean()), 'mean R %.3f' % r.mean(), 'median R %.2f' % r.median())
print('avg win R %.2f avg loss R %.2f' % (r[w].mean(), r[~w].mean())); print(T.reason.value_counts().to_dict())
runs = []; n = 0
for x in w:
    if not x: n += 1
    else:
        if n: runs.append(n)
        n = 0
if n: runs.append(n)
s = pd.Series(runs); print('losing runs: longest', s.max(), '| runs of 4+:', int((s >= 4).sum()), '| 6+:', int((s >= 6).sum()), '| 8+:', int((s >= 8).sum()))
c4 = r.rolling(4).sum(); print('4-trade windows all losing: %.1f%%' % (100 * (w.rolling(4).sum() == 0).mean()), '| worst 4-trade sum R %.2f' % c4.min())
print('first 4 trades of history R:', r.head(4).round(2).tolist()); m = r.groupby(pd.to_datetime(T.date).dt.to_period('M')).sum()
print('months', len(m), 'losing months %.0f%%' % (100 * (m < 0).mean()), 'worst month R %.1f best %.1f median %.1f' % (m.min(), m.max(), m.median()))
PY
