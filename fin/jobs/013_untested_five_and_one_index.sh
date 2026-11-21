#!/bin/bash
# fin 013 (own runner): read-only. (a) the five untested ideas, with their own pre-written tests (they only print);
# (b) is running the opening break on three funds three bets or one bet three times? No orders, no writes.
cd /root/pe-fin/team || exit 1
for pair in "mech_events.py E1t" "mech_events.py E1g" "mech_m7door3.py M7S" "mech_m7door3.py M7I" "mech_m7door3.py M7P"; do
  set -- $pair; echo "=== $2"; timeout 400 python3 -I $1 $2 2>&1 | grep -v -i warning | tail -5 | cut -c1-700
done
echo "=== orb5 source"; grep -n "def orb5" -A 22 mech2.py | cut -c1-260
echo "=== three funds"
timeout 600 python3 -I - <<'PY' 2>&1 | grep -v -i warning
import sys, math, numpy as np, pandas as pd
sys.path.insert(0, '/root/pe-fin'); sys.path.insert(0, '/root/pe-fin/team')
import mech2
S = {k: mech2.orb5(k) for k in ('QQQ', 'SPY', 'IWM')}
for k, s in S.items(): print(k, type(s).__name__, len(s), 'meanR %.3f' % s.mean(), 'index sample', list(s.index[:2]))
D = pd.DataFrame(S); print('days', len(D), 'all three traded', int(D.notna().all(axis=1).sum())); print('correlation of daily results\n', D.corr().round(2))
B = D.dropna(); w = B > 0
print('days all three lose %.0f%% | all three win %.0f%% | mixed %.0f%%' % (100 * (~w).all(axis=1).mean(), 100 * w.all(axis=1).mean(), 100 * (1 - (~w).all(axis=1).mean() - w.all(axis=1).mean())))
def rep(name, s):
    s = s.dropna(); t = s.mean() / (s.std(ddof=1) / math.sqrt(len(s))); eq = s.cumsum(); dd = (eq - eq.cummax()).min(); h = len(s) // 2
    m = s.groupby(pd.to_datetime(s.index).to_period('M')).sum()
    print('%-34s n %d | mean %+.3f R/day | t %.2f | 1st half %+.3f 2nd half %+.3f | worst day %.1f | deepest drawdown %.1f R | total %.0f R | return/drawdown %.1f | losing months %.0f%%' % (name, len(s), s.mean(), t, s[:h].mean(), s[h:].mean(), s.min(), dd, s.sum(), s.sum() / abs(dd), 100 * (m < 0).mean()))
F = D.fillna(0)
rep('Nasdaq fund only, $100 risk', F.QQQ); rep('all three, $100 risk each', F.sum(axis=1)); rep('all three, $33 risk each', F.sum(axis=1) / 3)
best = F.QQQ.where(D.QQQ.notna(), F.SPY.where(D.SPY.notna(), F.IWM)); rep('one a day (Nasdaq, else S&P, else small)', best)
rep('Nasdaq + small-company, $50 each', (F.QQQ + F.IWM) / 2)
PY
