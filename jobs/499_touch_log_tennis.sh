#!/bin/bash
# Finder item 129 (2026-11-07). Tennis, fade a big pre-off shock by resting, at the REAL 30 s touch, finder_tlog (copy of Railway bf_tennis_log), 7 Sep to 6 Nov 2026. Closed before the off.
# RULE, in the queue since 5 Nov, no new cuts: X10 only, trigger as item 126 (a print 10%+ from the latest print 30 s to 5 min earlier, T-90 to T-5, price 1.10 to 20, first per market).
#   Rest one tick inside the touch on the fade side for 120 s. Fill only on a print through the level. Exit 10 minutes later crossing the real touch, one tick adverse, or the last pre-off touch if the off comes first. Unfilled = no trade, counted.
#   Fade side: price shortened, so lay; price drifted, so back. Inside the touch: lay at max(best back, one tick under best lay); back at min(best lay, one tick over best back).
#   Through: a lay at X fills on a print strictly below X; a back at X fills on a print strictly above X (job 492's reading, mirrored).
# Also printed, not scored: the same trigger crossing the touch on the fade side and on the follow side, both ways at the real touch.
# PRINTS: a row whose last_traded differs from the row before. Prints between 30 s rows are unseen, so fills are undercounted and a 10% move inside one row counts at the row's time.
# GRADING: standard bar with t by market. Per-market, so no within-game inflation.
set -o pipefail
python3 - <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys, time
import numpy as np, pandas as pd, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs'); import creds
from lib_cand import step, back_hedge, lay_hedge, tstat, passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200); pd.set_option('display.max_columns', 40)
T0 = time.time(); M = 60.0; PLO, PHI = 1.10, 20.0
def prints(ts, ltp):
    keep = []; last = None
    for i in range(len(ts)):
        v = ltp[i]
        if np.isnan(v): continue
        if last is None or v != last: keep.append(i); last = v
    return np.array(keep, dtype=int)
def scan(tp, pp, st):
    """First print 10%+ from the latest print 30 s to 300 s earlier, T-90 to T-5. Returns (index, +1 shortened / -1 drifted) or None."""
    for i in range(1, len(tp)):
        m = (tp[i] - st) / M
        if m < -90: continue
        if m > -5: return None
        if not (PLO <= pp[i] <= PHI): continue
        j = i - 1
        while j >= 0 and tp[i] - tp[j] < 30: j -= 1
        if j < 0 or tp[i] - tp[j] > 300: continue
        if abs(pp[i] / pp[j] - 1) >= 0.10 - 1e-12: return i, (1 if pp[i] < pp[j] else -1)
    return None
def offer(side, b, l):
    return max(b, step(l, -1)) if side == 'L' else min(l, step(b, 1))
def filled(tp, pp, t0, x, side, wait=120):
    for k in range(len(tp)):
        if tp[k] <= t0: continue
        if tp[k] > t0 + wait: return None
        if (side == 'L' and pp[k] < x - 1e-9) or (side == 'B' and pp[k] > x + 1e-9): return tp[k]
    return None
def exit_row(ts, ref, b, l, side):
    """Row index at the first row 600 s after ref with a touch on the exit side, else the last pre-off row with one. side is the entry side."""
    col = b if side == 'L' else l
    ok = np.where(~np.isnan(col) & (ts > ref))[0]
    if len(ok) == 0: return None
    late = ok[ts[ok] >= ref + 600]
    return int(late[0]) if len(late) else int(ok[-1])
def pl(side, a, x):
    return lay_hedge(a, x) if side == 'L' else back_hedge(a, x)
# known answers, worked by hand
t_ = np.array([0., 30., 60., 90.]) - 40 * M
assert scan(t_, np.array([2.0, 2.0, 2.0, 1.8]), 0.0) == (3, 1) and scan(t_, np.array([2.0, 2.0, 2.0, 1.85]), 0.0) is None and scan(t_, np.array([2.0, 2.0, 2.0, 2.2]), 0.0) == (3, -1)
assert scan(np.array([0., 10.]) - 40 * M, np.array([2.0, 1.5]), 0.0) is None                                # nothing 30 s back
assert scan(np.array([0., 400.]) - 40 * M, np.array([2.0, 1.5]), 0.0) is None                               # gap over 5 min
assert scan(np.array([0., 60.]) - 4 * M, np.array([2.0, 1.5]), 0.0) is None                                 # after T-5
assert offer('L', 2.0, 2.04) == 2.02 and offer('L', 2.0, 2.02) == 2.0 and offer('B', 2.0, 2.04) == 2.02 and offer('B', 2.0, 2.02) == 2.02
tt = np.array([10., 40., 200.])
assert filled(tt, np.array([2.0, 1.98, 1.9]), 0., 2.0, 'L') == 40. and filled(tt, np.array([2.0, 2.0, 1.9]), 0., 2.0, 'L') is None and filled(tt, np.array([2.0, 2.02, 2.1]), 0., 2.0, 'B') == 40.
ts_ = np.array([0., 300., 600., 900.]); b_ = np.array([2., 2., np.nan, 2.]); l_ = np.array([2.1, 2.1, 2.1, np.nan])
assert exit_row(ts_, 0., b_, l_, 'L') == 3 and exit_row(ts_, 0., b_, l_, 'B') == 2 and exit_row(ts_[:2], 0., b_[:2], l_[:2], 'L') == 1
# lay 2.0 no tick, out at touch 1.8 -> back at 1.79: stake 10*(1-2/1.79) = -1.173184. back 2.0, out at touch 2.2 -> lay at 2.22: 10*(2/2.22-1) = -0.990991. back 2.0, out at 1.8 -> lay at 1.81: 10*(2/1.81-1)*.98 = 1.028729
assert abs(lay_hedge(2.0, 1.8) + 1.173184) < 1e-5 and abs(back_hedge(2.0, 2.2) + 0.990991) < 1e-5 and abs(back_hedge(2.0, 1.8) - 1.028729) < 1e-5
print('known answers OK', flush=True)
con = psycopg2.connect(creds.pg_local()); cur = con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D = pd.read_sql("""SELECT market_id, selection_id, competition, extract(epoch from captured_at)::float8 ts, extract(epoch from market_start)::float8 st,
     back_price::float8 b, lay_price::float8 l, last_traded::float8 ltp FROM finder_tlog
     WHERE NOT inplay AND captured_at>=market_start - interval '100 minutes' AND captured_at<market_start""", con)
D = D.sort_values(['market_id', 'selection_id', 'ts'])
print(f'pre-off rows {len(D):,}, markets {D.market_id.nunique():,}, {time.time()-T0:.0f}s', flush=True)
rows = []; nomk = 0
for mid, gm in D.groupby('market_id', sort=False):
    st = float(gm.st.iloc[0]); best = None
    for sid, g in gm.groupby('selection_id', sort=False):
        ts, b, l, ltp = g.ts.values, g.b.values, g.l.values, g.ltp.values
        pi = prints(ts, ltp)
        if len(pi) < 2: continue
        tp, pp = ts[pi], ltp[pi]
        s = scan(tp, pp, st)
        if s and (best is None or tp[s[0]] < best['t']):
            best = dict(t=tp[s[0]], d=s[1], px=pp[s[0]], ts=ts, b=b, l=l, tp=tp, pp=pp, sid=sid, comp=g.competition.iloc[0])
    if best is None: nomk += 1; continue
    ts, b, l, tp, pp = best['ts'], best['b'], best['l'], best['tp'], best['pp']; t = best['t']; d = best['d']
    side = 'L' if d == 1 else 'B'
    i = int(np.searchsorted(ts, t, side='left'))
    if i >= len(ts) or np.isnan(b[i]) or np.isnan(l[i]):
        rows.append(dict(mid=mid, st=st, side=side, px=best['px'], book=False, fill=False)); continue
    x = float(offer(side, b[i], l[i])); ft = filled(tp, pp, t, x, side)
    rec = dict(mid=mid, st=st, side=side, px=best['px'], book=True, fill=ft is not None, spread=float(l[i] / b[i] - 1), comp=best['comp'])
    if ft is not None and x > 1.01:
        e = exit_row(ts, ft, b, l, side)
        if e is not None: rec['fade'] = pl(side, x, b[e] if side == 'L' else l[e]); rec['mins'] = (ts[e] - ft) / M
    # crossing reads, not scored: next row's touch, one tick adverse, out 600 s later
    n = i + 1
    if n < len(ts) and ts[n] - ts[i] <= 120:
        for nm, sd in (('cross_fade', side), ('cross_follow', 'B' if side == 'L' else 'L')):
            pxn = l[n] if sd == 'L' else b[n]
            if np.isnan(pxn): continue
            a = step(float(pxn), 1 if sd == 'L' else -1)
            if a <= 1.01: continue
            e = exit_row(ts, ts[n], b, l, sd)
            if e is not None: rec[nm] = pl(sd, a, b[e] if sd == 'L' else l[e])
    rows.append(rec)
X = pd.DataFrame(rows)
print(f'triggers {len(X):,} of {len(X)+nomk:,} markets; book at trigger {X.book.mean():.3f}; fill rate where book {X[X.book].fill.mean():.3f}; median spread {X.spread.median():.4f}', flush=True)
def line(x, col, name):
    x = x[x[col].notna()]
    if len(x) == 0: return dict(line=name, n=0)
    v = x[col].values; med = np.median(x.st.values); a = x[x.st <= med][col]; c = x[x.st > med][col]; t = tstat(v)
    return dict(line=name, n=len(v), per10=v.mean(), t=t, n1=len(a), h1=a.mean(), n2=len(c), h2=c.mean(), PASS=passes(len(v), len(a), len(c), t, a.mean(), c.mean(), v.mean()))
def band(p): return 'P<1.5' if p < 1.5 else 'P1.5-2.5' if p < 2.5 else 'P2.5-20'
X['band'] = X.px.map(band)
print('\n== ITEM 129: fade by resting, X10, per filled trade; only the ALL and side lines are scored')
T = [line(X, 'fade', 'FADE rest ALL'), line(X[X.side == 'L'], 'fade', 'FADE rest lay after shortening'), line(X[X.side == 'B'], 'fade', 'FADE rest back after drift')]
for bd, g in X.groupby('band'): T.append(dict(line(g, 'fade', 'FADE rest ' + bd), PASS=False))
for c, nm in (('cross_fade', 'cross fade'), ('cross_follow', 'cross follow')):
    if c in X:
        T.append(dict(line(X, c, nm + ' ALL'), PASS=False))
        for s in ('L', 'B'): T.append(dict(line(X[X.side == s], c, nm + (' after shortening' if s == 'L' else ' after drift')), PASS=False))
print(pd.DataFrame(T).round(3).to_string(index=False))
print('per signal, unfilled at zero:', round(X.fade.fillna(0).mean(), 3) if 'fade' in X else 'no fills', '; median minutes held', X.mins.median() if 'mins' in X else None)
print('\n== SURVIVORS')
S = [r for r in T if r.get('PASS')]
print('\n'.join(f"{r['line']} n {r['n']} {r['per10']:+.3f} t {r['t']:.2f} h1 {r['h1']:+.3f} h2 {r['h2']:+.3f}" for r in S) if S else 'none')
print(f'time {time.time()-T0:.0f}s')
PY
