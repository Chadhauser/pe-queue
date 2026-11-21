#!/bin/bash
# fin 010 (own runner): read-only. (a) every live gap-fade fill 17-20 Nov against what the daily-bar history test would have booked
# for the same share that day; (b) the whole rule on those four days in history terms (all names vs the ten biggest gaps);
# (c) the five untested ideas and what tables/files exist to test with. No orders, no writes outside this log.
cd /root/pe-finq/repo/fin/bots || exit 1
echo "=== how the history test defined the rule"; grep -n -i -E "K2|gap" /root/pe-fin/team/mech_crumbs.py | cut -c1-260 | head -30
python3 - <<'PY' 2>&1 | grep -v -i warning
import json, os, datetime as dt, warnings; warnings.filterwarnings('ignore')
import pandas as pd, numpy as np, yfinance as yf, tick as T
T.H = T._creds(); uni, ed = T.universe()
d = yf.download(uni, period='15d', interval='1d', auto_adjust=False, progress=False, threads=True)
O, C = d['Open'], d['Close']; PC = C.shift(1); gap = O / PC - 1; fade = -np.sign(gap) * (C / O - 1)
rows = []
for day in ('2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20'):
    ts = pd.Timestamp(day); D = dt.date.fromisoformat(day)
    if ts not in O.index: print(day, 'no daily bar'); continue
    g = gap.loc[ts]; f = fade.loc[ts]; ok = (g.abs() >= 0.05) & (O.loc[ts] >= 3) & f.notna()
    noearn = [s for s in g[ok].index if not any(abs((pd.Timestamp(x).date() - D).days) <= 1 for x in ed.get(s, []))]
    top = g[noearn].abs().sort_values(ascending=False).index[:10]
    print(f"{day} HISTORY TERMS: names gapping 5%+ {len(noearn)} | all mean {1e4*f[noearn].mean():+.0f} bps, win {100*(f[noearn]>0).mean():.0f}% | ten biggest gaps mean {1e4*f[top].mean():+.0f} bps")
    st = json.load(open(os.path.join(T.BOTS, f'day_{day}.json'))); legs = [l for l in st.get('K2', {}).get('legs', []) if l.get('status', 999) < 300]
    sc, od = T.api('GET', '/orders', params={'status': 'closed', 'after': f'{day}T13:00:00Z', 'until': f'{day}T22:00:00Z', 'limit': 500, 'direction': 'asc'})
    for l in legs:
        s = l['sym']; fl = [(o['side'], float(o['filled_qty']), float(o['filled_avg_price'])) for o in od if o['symbol'] == s and o.get('filled_avg_price') and float(o['filled_qty']) > 0]
        if len(fl) < 2 or s not in O.columns or pd.isna(O.loc[ts, s]): print('  skip', s, fl); continue
        ent, ex = fl[0], fl[-1]; sgn = 1 if ent[0] == 'buy' else -1
        live = sgn * (ex[2] / ent[2] - 1); hist = sgn * (C.loc[ts, s] / O.loc[ts, s] - 1)
        rows.append(dict(day=day, sym=s, side=ent[0], gap_live=l['gap'], gap_official=round(g[s], 4), open=O.loc[ts, s], entry=ent[2], close=C.loc[ts, s], exit=ex[2],
                         live_bps=1e4 * live, hist_bps=1e4 * hist, entry_cost_bps=1e4 * sgn * (ent[2] / O.loc[ts, s] - 1), exit_cost_bps=-1e4 * sgn * (ex[2] / C.loc[ts, s] - 1),
                         in_hist=bool(abs(g[s]) >= 0.05), same_side=bool(np.sign(g[s]) == np.sign(l['gap'])), usd=sgn * (ex[2] - ent[2]) * ent[1]))
R = pd.DataFrame(rows); pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200)
print(R.round(2).to_string(index=False))
print('\nTOTAL legs', len(R), '| live mean %+.0f bps ($%.2f) | history-test booking for the same legs mean %+.0f bps' % (R.live_bps.mean(), R.usd.sum(), R.hist_bps.mean()))
print('entry cost mean %+.0f bps (fill at 09:31 vs the official open) | exit cost mean %+.0f bps (fill at 15:55 vs the official close)' % (R.entry_cost_bps.mean(), R.exit_cost_bps.mean()))
print('legs the history test would also have picked (official gap 5%%+, same side): %d of %d | their live mean %+.0f, hist mean %+.0f' % ((R.in_hist & R.same_side).sum(), len(R), R[R.in_hist & R.same_side].live_bps.mean(), R[R.in_hist & R.same_side].hist_bps.mean()))
print('legs NOT in the history set: %d | live mean %+.0f bps' % ((~(R.in_hist & R.same_side)).sum(), R[~(R.in_hist & R.same_side)].live_bps.mean()))
print('by side:', R.groupby('side').live_bps.agg(['count', 'mean']).round(0).to_dict())
print('\n=== untested ideas'); H = json.load(open('/root/pe-fin/team/hypotheses.json')); H = H if isinstance(H, list) else H.get('hypotheses', H)
for h in (H if isinstance(H, list) else list(H.values())):
    if isinstance(h, dict) and h.get('status') in ('proposed', 'failed'): print(h.get('status'), '|', h.get('id'), '|', str(h.get('title') or h.get('name') or h.get('claim') or h)[:330])
PY
echo "=== data on disk"; ls -la /root/pe-data/crumbs 2>/dev/null | head -20; du -sh /root/pe-data/* 2>/dev/null | head -20
