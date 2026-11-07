# lib_afmatch (Finder 2026-11-07, items 139, 184, 185, 403): af_fixtures to bf_hist_other by name and time, for months af_price_map does not cover, and a timestamp tape in place of the minute tape. Match logic from jobs/499_foul_draw_unseen.sh. Run directly for the known-answer checks. No secrets; read-only.
# TAPE TO CLOCK jobs/499_goal_timing.sh line 6: tape 46 at KO+46 min, tape 47 at KO+66, so a match minute in the second half sits about 19 minutes later on the clock than its number.
import numpy as np, pandas as pd
from lib_cand import norm, loose, step, back_settle, lay_settle
from lib_official import group, secs, first_in, fill
H2_LAG = 19
def clock_min(m):
    """Match minute to minutes after kick-off."""
    return m if m <= 46 else m + H2_LAG
def match_minute(el):
    """Minutes after kick-off to match minute. In the break (el 47..65) it reads 46."""
    return el if el <= 46 else max(el - H2_LAG, 46)
def entry(ts, px, ko, lo_min, hi_min, side):
    """(print index, fill one tick adverse) from the first print lo_min..hi_min after ko, worse of it and the next print within 120 s. None if no print, never a forward fill, or a back at the bottom of the ladder."""
    i = first_in(ts, ko + lo_min * 60, ko + hi_min * 60)
    if i is None: return None
    a = step(fill(ts, px, i, side), -1 if side == 'B' else 1)
    if side == 'B' and a <= 1.01: return None
    return i, a
def pnl(side, a, won):
    return back_settle(a, won) if side == 'B' else lay_settle(a, won)
def half(off):
    """1 or 2 by the date median of the games."""
    off = np.asarray(off, dtype=float); md = float(np.median(np.unique(off)))
    return np.where(off < md, 1, 2)
def fixtures(con, a, b, unmapped_only=True, cols=''):
    """FT fixtures with a score kicking off in [a,b), not in af_price_map if asked."""
    F = pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag,ht_hg,ht_ag" + cols + " FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND kickoff>=%s AND kickoff<%s", con, params=(a, b))
    if unmapped_only:
        M = set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map", con).f)
        F = F[~F.fixture_id.isin(M)]
    F['k'] = pd.to_datetime(F.kickoff, utc=True); F['H'] = F.home.map(norm); F['A'] = F.away.map(norm)
    return F.sort_values('k').reset_index(drop=True)
def match(con, market_type, a, b, FX, mins=20):
    """One market per fixture: senior markets of market_type in [a,b), within mins of the kick-off, loose name match, both ways unique. Returns market_id, event_name, mt, fx."""
    MK = pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND market_time>=%s AND market_time<%s", con, params=(market_type, a, b))
    MK['mt'] = pd.to_datetime(MK.market_time, utc=True)
    MK = MK[[group(str(e)) is None for e in MK.event_name]].copy()
    kt = FX.k.dt.tz_convert(None).values.astype('datetime64[ns]'); d = pd.Timedelta(minutes=mins); Ev = {}
    for (ev, mt), _ in MK.groupby(['event_name', 'mt'], sort=False):
        h, _x, aw = str(ev).partition(' v ')
        lo = np.searchsorted(kt, np.datetime64((mt - d).tz_convert(None))); hi = np.searchsorted(kt, np.datetime64((mt + d).tz_convert(None)), side='right')
        Ev[(ev, mt)] = loose(norm(h), norm(aw), [(q.H, q.A, int(q.fixture_id)) for q in FX.iloc[lo:hi].itertuples()])
    MK['fx'] = [Ev.get((e, m)) for e, m in zip(MK.event_name, MK.mt)]
    MK = MK[MK.fx.notna()].copy(); MK['fx'] = MK.fx.astype(int)
    return MK.drop_duplicates('fx', keep=False).reset_index(drop=True)
def tape(con, market_type, mids, sel_prefix, chunk=500, log=None):
    """market_id -> (ts, px) for the in-play prints of the one selection starting sel_prefix, sorted by time, one print per second. Real prints only."""
    out = {}
    for c in range(0, len(mids), chunk):
        P = pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000", con, params=(market_type, list(mids[c:c + chunk])))
        if not len(P): continue
        P = P[P.sel.str.strip().str.lower().str.startswith(sel_prefix)].copy()
        P['tt'] = secs(P.ts); P = P.drop_duplicates(['market_id', 'tt']).sort_values(['market_id', 'tt'], kind='stable')
        for m, x in P.groupby('market_id', sort=False): out[m] = (x.tt.values, x.ltp.values)
        if log: log(f"  tapes {min(c + chunk, len(mids))}/{len(mids)}")
    return out
def official_over(con, mids):
    """market_id -> True if Over won, from bf_hist_result, markets with one WINNER only. Used only to check the af score."""
    R = pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_id=ANY(%s) AND status='WINNER'", con, params=(list(mids),))
    R = R[~R.market_id.duplicated(keep=False)]
    return dict(zip(R.market_id, R.sel.str.strip().str.lower().str.startswith('over')))
def agreement(rows):
    """rows of (af says Over won, official says Over won or None). (agree, checked)."""
    c = [(a, b) for a, b in rows if b is not None]
    return sum(1 for a, b in c if bool(a) == bool(b)), len(c)
def checks():
    assert clock_min(30) == 30 and clock_min(46) == 46 and clock_min(47) == 66 and clock_min(70) == 89
    assert match_minute(30) == 30 and match_minute(50) == 46 and match_minute(66) == 47 and match_minute(89) == 70
    t = np.array([3700., 3900., 4300.]); p = np.array([2.0, 2.2, 3.0])
    # KO 100, window 60..71 min = 3700..4360. First print 3700, next 200 s later so too late to count: back 2.0 -> 1.99, lay 2.0 -> 2.02.
    assert entry(t, p, 100., 60, 71, 'B') == (0, 1.99) and entry(t, p, 100., 60, 71, 'L') == (0, 2.02)
    # Next print within 120 s: back takes the lower 2.0 -> 1.99, lay the higher 2.2 -> 2.22.
    t2 = np.array([3700., 3800.]); assert entry(t2, p[:2], 100., 60, 71, 'L') == (0, 2.22) and entry(t2, p[:2], 100., 60, 71, 'B') == (0, 1.99)
    # No print in the window: none, never a forward fill from an earlier print.
    assert entry(np.array([1000.]), np.array([2.0]), 100., 60, 71, 'B') is None
    assert entry(np.array([3700.]), np.array([1.02]), 100., 60, 71, 'B') is None and entry(np.array([3700.]), np.array([1.02]), 100., 60, 71, 'L') == (0, 1.03)
    assert abs(pnl('B', 1.99, True) - 9.702) < 1e-9 and pnl('B', 1.99, False) == -10 and pnl('L', 2.02, True) == -10 and abs(pnl('L', 2.02, False) - 10 / 1.02 * .98) < 1e-9
    assert list(half([1, 1, 2, 3])) == [1, 1, 2, 2]
    assert agreement([(True, True), (False, True), (True, None)]) == (1, 2)
    return True
if __name__ == '__main__':
    checks(); print("lib_afmatch known-answer checks: OK")
