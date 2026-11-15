"""Item 342's control, step by step: where does the Draw rate fall? Same FOUL history as the job. Read only."""
import sys
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs')
import creds, psycopg2, pandas as pd, numpy as np, warnings
from collections import defaultdict, deque
warnings.filterwarnings('ignore')
from lib_cand import norm, loose
from lib_official import group, secs
def foul_state(games):
    H = defaultdict(lambda: deque(maxlen=5)); out = {}; i = 0
    while i < len(games):
        j = i
        while j < len(games) and games[j][1] == games[i][1]: j += 1
        for f, t, h, a, hf, af in games[i:j]:
            if len(H[h]) == 5 and len(H[a]) == 5: out[f] = (sum(H[h]) / 5 + sum(H[a]) / 5) / 2
        for f, t, h, a, hf, af in games[i:j]:
            if hf == hf and af == af: H[h].append(hf + af); H[a].append(hf + af)
        i = j
    return out
c = psycopg2.connect(creds.pg_local()); c.autocommit = True
c.cursor().execute("SET work_mem='64MB'; SET statement_timeout='900s'")
S = pd.read_sql("SELECT f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.home,f.away,f.hg,f.ag,s.is_home,(s.raw->>'Fouls')::float fl FROM af_fixtures f JOIN af_stats s USING(fixture_id) WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ag IS NOT NULL AND f.season IN (2023,2024,2025,2026)", c)
F = S[S.is_home == True].merge(S[S.is_home == False][['fixture_id', 'fl']], on='fixture_id', suffixes=('_h', '_a')).drop_duplicates('fixture_id')
F['tt'] = secs(F.kickoff); R = {}
for _, g in F.sort_values('tt').groupby(['league_id', 'season']):
    R.update(foul_state([tuple(x) for x in g[['fixture_id', 'tt', 'home', 'away', 'fl_h', 'fl_a']].itertuples(index=False)]))
F['fv'] = F.fixture_id.map(R); F['k'] = pd.to_datetime(F.kickoff, utc=True); F['d'] = (F.hg == F.ag).astype(float)
MP = set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map", c).f)
for lab, A, B in (('May-Jul 2023', '2023-05-01', '2023-08-01'), ('Aug-Oct 2023, later months', '2023-08-01', '2023-11-01')):
    a, b = pd.Timestamp(A, tz='UTC'), pd.Timestamp(B, tz='UTC')
    W = F[(F.k >= a) & (F.k < b)]
    print(f"\n== {lab}")
    print(' stats row, season 2023 on: n', len(W), 'Draw', round(W.d.mean(), 3))
    X = W[W.fixture_id.isin(R) & ~W.fixture_id.isin(MP)].sort_values('k').reset_index(drop=True)
    print(' five earlier games, unmapped: n', len(X), 'Draw', round(X.d.mean(), 3))
    X['H'] = X.home.map(norm); X['A'] = X.away.map(norm); kt = X.k.dt.tz_convert(None).values.astype('datetime64[ns]')
    MK = pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s", c, params=(A, B))
    MK = MK[[group(str(e)) is None for e in MK.event_name]]; MK['mt'] = pd.to_datetime(MK.market_time, utc=True); fx = []
    for r in MK.itertuples():
        h, _x, aw = str(r.event_name).partition(' v ')
        lo = np.searchsorted(kt, np.datetime64((r.mt - pd.Timedelta(minutes=20)).tz_convert(None))); hi = np.searchsorted(kt, np.datetime64((r.mt + pd.Timedelta(minutes=20)).tz_convert(None)), side='right')
        fx.append(loose(norm(h), norm(aw), [(q.H, q.A, int(q.fixture_id)) for q in X.iloc[lo:hi].itertuples()]))
    MK['fx'] = fx; M = MK[MK.fx.notna()].copy(); M['fx'] = M.fx.astype(int); M = M.drop_duplicates('fx', keep=False)
    M = M.merge(X[['fixture_id', 'd', 'k', 'league', 'season', 'fv']], left_on='fx', right_on='fixture_id')
    print(' matched to one market: n', len(M), 'Draw', round(M.d.mean(), 3))
    fp = {}; ids = list(M.market_id)
    for i in range(0, len(ids), 500):
        P = pd.read_sql("SELECT market_id,min(ts) f FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND sel='The Draw' AND inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '6 minutes' AND ts<=market_time+interval '25 minutes' GROUP BY 1", c, params=(ids[i:i + 500],))
        fp.update(dict(zip(P.market_id, secs(P.f))))
    M['el'] = M.market_id.map(fp) - M.k.map(lambda x: x.timestamp())
    near = M[M.el.abs() <= 300]; late = M[~(M.el.abs() <= 300)]
    print(' Draw printed within 5 min of kick-off (the job): n', len(near), 'Draw', round(near.d.mean(), 3))
    print(' no such print, dropped by the job: n', len(late), 'Draw', round(late.d.mean(), 3))
    print(near.groupby(near.k.dt.strftime('%Y-%m')).d.agg(['size', 'mean']).round(3).to_string())
    print(near.groupby('league').d.agg(['size', 'mean']).sort_values('size', ascending=False).head(8).round(3).to_string())
c.close()
