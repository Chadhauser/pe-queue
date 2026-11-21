#!/bin/bash
# fin 009 (own runner): as 008 (which could not find the connection line). Read-only. Never prints the connection string.
cd /root/pe-fin || exit 1
grep -n -E "^\s*DB\b|DB\s*=" orb_slices.py | sed -E 's/(=).*/\1 <hidden>/' | head -5
python3 - <<'PY' 2>&1 | grep -v Warning
import re, os, sys, json, warnings; warnings.filterwarnings('ignore')
import pandas as pd, psycopg2
src = open('orb_slices.py').read().splitlines(); ns = {}
i = next(k for k, l in enumerate(src) if 'psycopg2.connect' in l)
pre = [l for l in src[:i] if not l.startswith((' ', '\t'))]
for l in pre:
    try: exec(l, ns)
    except Exception: pass
if 'DB' not in ns: print('still no DB; names:', [k for k in ns if not k.startswith('_')][:30]); sys.exit(0)
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
print('4-trade windows all losing: %.1f%%' % (100 * (w.astype(int).rolling(4).sum() == 0).mean()), '| worst 4-trade sum R %.2f' % r.rolling(4).sum().min())
m = r.groupby(pd.to_datetime(T.date).dt.to_period('M')).sum()
print('months', len(m), 'losing months %.0f%%' % (100 * (m < 0).mean()), 'worst month R %.1f best %.1f median %.1f' % (m.min(), m.max(), m.median()))
PY
