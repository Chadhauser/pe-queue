#!/bin/bash
# Finder items 17, 172 and the spread atlas (2026-11-07). Racing at the REAL 30 s touch, finder_rlog (copy of Railway bf_racing_log), 7 Sep to 6 Nov 2026. Closed before the off.
# ITEM 17, rule in the queue since 3 Nov: lay when morning-money R < 0.5, R as job 463 from racing_bsp, at the real lay price; green at the last pre-off touch and at BSP; by price band.
#   Entry at 11:30 and 13:00 UK, the worse of that row's lay and the next row's within 120 s, one tick adverse. 10:00 is printed, not scored: morning volume is not finished by then (look-ahead).
#   R 0.8-1.25 is the control, not scored. RESTED, fixed in the queue as item 390 before this run: offer at that row's back, filled only on a later print strictly below it by T-5, no entry tick, out at the last pre-off touch.
# ITEM 172, rule in the queue since 5 Nov: signal as item 169 EARLY, last print T-45..T-20 against last print T-15..T-10, up 10%+, band 3-6, one per race; offer the lay at the signal print,
#   filled only on a later print through it (strictly below, as job 492) by T-5; out at the last pre-off touch crossing, one tick adverse. FLAT is the control.
# PRINTS: a row whose last_traded differs from the row before. A repeat at the same price is unseen, and prints between 30 s rows are unseen, so fills are undercounted.
# GRADING: standard bar with t by race, the lower of it and t by trade. NOTICK = at the bare touch, no extra tick, an upper read, not graded.
set -o pipefail
python3 - <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys, time, datetime as dt
from zoneinfo import ZoneInfo
import numpy as np, pandas as pd, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs'); import creds
from lib_cand import step, net, lay_hedge, tstat, passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200); pd.set_option('display.max_columns', 40)
T0 = time.time(); UK = ZoneInfo('Europe/London'); UTC = dt.timezone.utc; M = 60.0
def clock_utc(day, hh, mm):
    return dt.datetime(day.year, day.month, day.day, hh, mm, tzinfo=UK).astimezone(UTC).timestamp()
def nticks(b, l, cap=400):
    n = 0; x = float(b)
    while x < l - 1e-9 and n < cap:
        x = step(x, 1); n += 1
    return n
def rband(p): return '<3' if p < 3 else '3-6' if p < 6 else '6-12' if p < 12 else '12-30' if p < 30 else '30+'
def b169(p): return '<3' if p < 3 else '3-6' if p < 6 else '6-12' if p < 12 else '12-20' if p <= 20 else None
def rgroup(r): return '<0.5' if r < 0.5 else 'CTRL' if 0.8 <= r <= 1.25 else None
def prints(ts, ltp):
    """Rows where last_traded changed, first known value included. Returns index array."""
    keep = []; last = None
    for i in range(len(ts)):
        v = ltp[i]
        if np.isnan(v): continue
        if last is None or v != last: keep.append(i); last = v
    return np.array(keep, dtype=int)
def last_in(ts, lo, hi):
    i = int(np.searchsorted(ts, hi, side='right')) - 1
    return i if i >= 0 and ts[i] >= lo else None
def through(ts, px, start, level, limit):
    """First print after index start strictly below level, by limit. None if none."""
    for k in range(start + 1, len(ts)):
        if ts[k] > limit: return None
        if px[k] < level - 1e-9: return k
    return None
# known answers, worked by hand
assert dt.datetime.fromtimestamp(clock_utc(dt.date(2026, 10, 20), 11, 30), UTC).hour == 10          # BST
assert dt.datetime.fromtimestamp(clock_utc(dt.date(2026, 10, 30), 11, 30), UTC).hour == 11          # GMT after 25 Oct
assert nticks(5.0, 5.2) == 2 and nticks(1.98, 2.02) == 3 and nticks(5.0, 5.0) == 0
# lay 5.0 -> fill 5.1, stake 10/4.1, out at touch 5.0 -> back at 4.9: 2.439024*(1-5.1/4.9) = -0.099552, a loss so no commission
assert abs(lay_hedge(step(5.0, 1), 5.0) + 0.0995520) < 1e-5
# rested lay at 5.0, no tick, out at touch 4.0 -> back at 3.95: stake 2.5*(1-5/3.95) = -0.664557
assert abs(lay_hedge(5.0, 4.0) + 0.664557) < 1e-5
assert rgroup(0.49) == '<0.5' and rgroup(0.5) is None and rgroup(0.8) == 'CTRL' and rgroup(1.25) == 'CTRL' and rgroup(1.3) is None
t_ = np.array([0., 30., 60., 90.]); assert through(t_, np.array([5., 5.1, 5., 4.9]), 0, 5.0, 100) == 3 and through(t_, np.array([5., 5.1, 5., 4.9]), 0, 5.0, 80) is None
assert list(prints(t_, np.array([5., 5., np.nan, 5.1]))) == [0, 3]
_d = pd.DataFrame(dict(e=[1, 1, 1], mv=[10., 30., 60.], pm=[2., 4., 4.]))                            # s .1,.3,.6; q0 .5,.25,.25, q .5,.25,.25; R .2,1.2,2.4
_d['s'] = _d.mv / _d.groupby('e').mv.transform('sum'); _d['q0'] = 1 / _d.pm; _d['q'] = _d.q0 / _d.groupby('e').q0.transform('sum'); _d['R'] = _d.s / _d.q
assert abs(_d.R[0] - 0.2) < 1e-9 and abs(_d.R[1] - 1.2) < 1e-9 and abs(_d.R[2] - 2.4) < 1e-9
print('known answers OK', flush=True)

con = psycopg2.connect(creds.pg_local()); cur = con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
B = pd.read_sql("""SELECT event_id, event_dt, selection_id, win_lose won, bsp::float8 pb, NULLIF(morningwap,0)::float8 pm, morning_vol::float8 mv
   FROM racing_bsp WHERE lower(market)='win' AND lower(country) IN ('uk','ire') AND event_dt>='2026-09-07' AND bsp>1.01 AND bsp<1000""", con)
B = B.drop_duplicates(['event_id', 'selection_id'])
B = B[B.pm.notna() & (B.pm > 1.01) & (B.pm < 1000) & B.mv.notna() & (B.mv > 0)]
B['nr'] = B.groupby('event_id').selection_id.transform('size'); B = B[B.nr >= 5].copy()
B['s'] = B.mv / B.groupby('event_id').mv.transform('sum'); B['q0'] = 1 / B.pm; B['q'] = B.q0 / B.groupby('event_id').q0.transform('sum'); B['R'] = B.s / B.q
B['day'] = pd.to_datetime(B.event_dt).dt.date
print(f'racing_bsp win runners with R {len(B):,}, races {B.event_id.nunique():,}, {B.day.min()} to {B.day.max()}, R<0.5 {int((B.R<0.5).sum()):,}', flush=True)
RB = {(int(a), b): (r, p, q) for a, b, r, p, q in zip(B.selection_id, B.day, B.R, B.pm, B.pb)}
RS = pd.read_sql("SELECT market_id, selection_id, won, bsp::float8 bsp FROM finder_rresults", con)
BSP = {(m, int(s)): b for m, s, b in zip(RS.market_id, RS.selection_id, RS.bsp) if b == b}
print(f'finder_rresults runners {len(RS):,}, markets {RS.market_id.nunique():,}, bsp known {len(BSP):,}', flush=True)
cur.execute("select market_name,count(distinct market_id) from finder_rlog where market_name ~* 'place|tbp' group by 1 order by 2 desc limit 5"); print('place-like market names:', cur.fetchall(), flush=True)

E17, E172, ATL, chk = [], [], [], []
stats = dict(markets=0, runners=0, joined=0)
cur.execute("select min(captured_at)::date,max(captured_at)::date from finder_rlog"); lo, hi = cur.fetchone(); print('log days', lo, hi, flush=True)
wk = lo
while wk <= hi:
    wk2 = wk + dt.timedelta(days=7)
    D = pd.read_sql("""SELECT market_id, selection_id, extract(epoch from captured_at)::float8 ts, extract(epoch from market_start)::float8 st,
          back_price::float8 b, lay_price::float8 l, last_traded::float8 ltp, inplay
        FROM finder_rlog WHERE captured_at>=%s::timestamptz - interval '5 hours' AND captured_at<%s::timestamptz + interval '1 hour'
          AND market_start>=%s AND market_start<%s AND market_name !~* 'place|tbp'""", con, params=(str(wk), str(wk2), str(wk), str(wk2)))
    D = D.sort_values(['market_id', 'selection_id', 'ts'])
    for mid, gm in D.groupby('market_id', sort=False):
        stats['markets'] += 1
        st = float(gm.st.iloc[0]); day = dt.datetime.fromtimestamp(st, UK).date()
        sigs = []
        for sid, g in gm.groupby('selection_id', sort=False):
            stats['runners'] += 1; sid = int(sid)
            ts, b, l, ltp, ip = g.ts.values, g.b.values, g.l.values, g.ltp.values, g.inplay.values
            pre = ~ip & (ts <= st + 900)
            if pre.sum() < 3: continue
            ts, b, l, ltp = ts[pre], b[pre], l[pre], ltp[pre]
            okb = np.where(~np.isnan(b))[0]
            if len(okb) == 0: continue
            jl = int(okb[-1]); xl = float(b[jl])
            # atlas
            for T in (240, 120, 60, 30, 15, 5, 1):
                i = last_in(ts, st - T * M - 60, st - T * M + 60)
                if i is None: continue
                ok = not (np.isnan(b[i]) or np.isnan(l[i]))
                ATL.append((T, rband(l[i] if not np.isnan(l[i]) else (b[i] if not np.isnan(b[i]) else 1000.)), ok, nticks(b[i], l[i]) if ok else -1))
            # item 17
            key = (sid, day)
            if key in RB:
                stats['joined'] += 1
                R, pm, pb = RB[key]; bsp = BSP.get((mid, sid), None)
                if bsp is not None and len(chk) < 50000: chk.append(abs(pb / bsp - 1))
                grp = rgroup(R)
                if grp:
                    for name, hh, mm in (('10:00', 10, 0), ('11:30', 11, 30), ('13:00', 13, 0)):
                        c = clock_utc(day, hh, mm)
                        if st - c < 5 * M: continue
                        i = int(np.searchsorted(ts, c, side='left'))
                        if i >= len(ts) or ts[i] > c + 120: continue
                        base = dict(mid=mid, sid=sid, st=st, clock=name, grp=grp, band=rband(pm), R=R)
                        if i + 1 < len(ts) and ts[i + 1] - ts[i] <= 120 and not np.isnan(l[i]) and not np.isnan(l[i + 1]) and jl > i + 1:
                            L = max(l[i], l[i + 1]); a = step(L, 1)
                            if a < 1000:
                                sp = nticks(b[i], l[i]) if not np.isnan(b[i]) else -1
                                E17.append(dict(base, kind='LAST', pnl=lay_hedge(a, xl), sp=sp, lay=L, stake=10 / (a - 1)))
                                E17.append(dict(base, kind='LAST_NOTICK', pnl=net(10 / (L - 1) * (1 - L / xl)), sp=sp, lay=L, stake=10 / (L - 1)))
                                if bsp is not None: E17.append(dict(base, kind='BSP', pnl=lay_hedge(a, bsp), sp=sp, lay=L, stake=10 / (a - 1)))
                        if not np.isnan(b[i]):
                            X = float(b[i]); pi = prints(ts, ltp)
                            if len(pi):
                                tp, pp = ts[pi], ltp[pi]; s0 = int(np.searchsorted(tp, ts[i], side='right')) - 1
                                k = through(tp, pp, s0, X, st - 5 * M) if s0 >= -1 else None
                                filled = k is not None and tp[k] < ts[jl]
                                E17.append(dict(base, kind='RESTED', filled=filled, pnl=lay_hedge(X, xl) if filled and X > 1.01 else np.nan, sp=0, lay=X, stake=10 / (X - 1) if X > 1.01 else np.nan))
            # item 172, one candidate per runner
            pi = prints(ts, ltp)
            if len(pi) < 3: continue
            tp, pp = ts[pi], ltp[pi]
            i0 = last_in(tp, st - 45 * M, st - 20 * M); j0 = last_in(tp, st - 15 * M, st - 10 * M)
            if i0 is None or j0 is None or j0 <= i0: continue
            r = pp[j0] / pp[i0]; c = 'DRIFT' if r >= 1.10 - 1e-9 else 'FLAT' if 0.98 - 1e-9 <= r <= 1.02 + 1e-9 else None
            bd = b169(pp[j0])
            if c is None or bd is None: continue
            sigs.append(dict(mid=mid, sid=sid, st=st, c=c, bd=bd, r=r, L=float(pp[j0]), tsig=tp[j0], ts=ts, b=b, l=l, tp=tp, pp=pp, j0=j0, jl=jl, xl=xl))
        # one per race, per class and band: earliest signal print, ties to the shortest price
        seen = {}
        for s in sorted(sigs, key=lambda s: (s['tsig'], s['L'])):
            k = (s['c'], s['bd'])
            if k in seen: continue
            seen[k] = 1
            kf = through(s['tp'], s['pp'], s['j0'], s['L'], s['st'] - 5 * M)
            filled = kf is not None and s['tp'][kf] < s['ts'][s['jl']]
            rec = dict(mid=s['mid'], st=s['st'], c=s['c'], bd=s['bd'], L=s['L'], filled=filled, pnl=lay_hedge(s['L'], s['xl']) if filled and s['L'] > 1.01 else np.nan)
            ni = int(np.searchsorted(s['ts'], s['tsig'], side='right'))
            rec['cross'] = lay_hedge(step(s['l'][ni], 1), s['xl']) if ni < len(s['ts']) and ni < s['jl'] and not np.isnan(s['l'][ni]) else np.nan
            rec['mv'] = np.log(s['L'] / s['xl'])
            E172.append(rec)
    print(f'week {wk} done, markets {stats["markets"]}, {time.time()-T0:.0f}s', flush=True)
    wk = wk2
print(stats, flush=True)
if chk:
    a = np.array(chk); print(f'JOIN GATE racing_bsp bsp v racing_results bsp: within 2% on {np.mean(a<0.02):.3f} of {len(a):,}', flush=True)

def line(x, col='pnl'):
    x = x[x[col].notna()]
    if len(x) == 0: return None
    v = x[col].values; n = len(v); med = np.median(x.st.values); a = x[x.st <= med]; c = x[x.st > med]
    tr = tstat(x.groupby('mid')[col].mean().values) if x.mid.nunique() > 1 else 0.0; tt = tstat(v); t = min(tr, tt)
    return dict(n=n, races=x.mid.nunique(), per10=v.mean(), t_trade=tt, t_race=tr, n1=len(a), h1=a[col].mean(), n2=len(c), h2=c[col].mean(), big=v.max() / max(1e-9, v.sum()) if v.sum() > 0 else np.nan,
                PASS=passes(n, len(a), len(c), t, a[col].mean(), c[col].mean(), v.mean()))

print('\n== ATLAS: real spread in ticks, by minutes before the off and price band of the lay side (no read = one side empty)')
A = pd.DataFrame(ATL, columns=['T', 'band', 'ok', 'sp'])
rows = []
for (T, bd), g in A.groupby(['T', 'band']):
    o = g[g.ok]
    rows.append(dict(T=T, band=bd, rows=len(g), both_sides=round(g.ok.mean(), 3), med_ticks=o.sp.median() if len(o) else np.nan, p75=o.sp.quantile(.75) if len(o) else np.nan, le1=round((o.sp <= 1).mean(), 3) if len(o) else np.nan, le3=round((o.sp <= 3).mean(), 3) if len(o) else np.nan))
print(pd.DataFrame(rows).sort_values(['band', 'T'], ascending=[True, False]).to_string(index=False))

print('\n== ITEM 17: R<0.5 and control, real lay touch. 10:00 carries look-ahead, not scored')
X = pd.DataFrame(E17); rows = []
if len(X):
    for (kd, ck, gp), g in X.groupby(['kind', 'clock', 'grp']):
        for bd, h in [('ALL', g)] + list(g.groupby('band')):
            r = line(h)
            if r is None: continue
            fr = h.filled.astype(bool).mean() if kd == 'RESTED' else np.nan
            rows.append(dict(kind=kd, clock=ck, grp=gp, band=bd, offered=len(h), fill=fr, med_sp=h.sp.median(), med_stake=h.stake.median(), **r))
    T17 = pd.DataFrame(rows)
    T17.loc[(T17.clock == '10:00') | (T17.grp == 'CTRL') | (T17.kind == 'LAST_NOTICK'), 'PASS'] = False
    print(T17.sort_values(['kind', 'grp', 'clock', 'band']).round(3).to_string(index=False))
print('\n== ITEM 172: drift 10%+, offer at the signal print, through-fill by T-5, out at the last pre-off touch. Only DRIFT 3-6 is scored')
Y = pd.DataFrame(E172); rows = []
if len(Y):
    for (c, bd), g in Y.groupby(['c', 'bd']):
        r = line(g); rc = line(g, 'cross')
        rows.append(dict(cls=c, band=bd, signals=len(g), fill=g.filled.mean(), per_signal=(g.pnl.fillna(0)).mean(), mv_filled=g[g.filled].mv.mean(), mv_unfilled=g[~g.filled].mv.mean(), cross_n=rc['n'] if rc else 0, cross=rc['per10'] if rc else np.nan, **(r or {})))
    T172 = pd.DataFrame(rows); T172.loc[~((T172.cls == 'DRIFT') & (T172.band == '3-6')), 'PASS'] = False
    print(T172.round(3).to_string(index=False))
print('\n== SURVIVORS')
out = []
if len(X): out += [f"17 {r.kind} {r.clock} {r.grp} {r.band} n {r.n} {r.per10:+.3f} t {r.t_race:.2f} h1 {r.h1:+.3f} h2 {r.h2:+.3f}" for r in T17[T17.PASS == True].itertuples()]
if len(Y): out += [f"172 {r.cls} {r.band} n {r.n} {r.per10:+.3f} t {r.t_race:.2f}" for r in T172[T172.PASS == True].itertuples()]
print('\n'.join(out) if out else 'none')
print(f'time {time.time()-T0:.0f}s')
PY
