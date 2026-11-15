"""Why does the Draw win so rarely in item 342's May-Jul 2023 control? Read only. Three independent counts: official results, af_fixtures, and the job's own matched games split by whether the Draw printed near kick-off."""
import sys
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs')
import creds, psycopg2, pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from lib_cand import norm, loose
from lib_official import group, secs
c = psycopg2.connect(creds.pg_local()); c.autocommit = True
c.cursor().execute("SET work_mem='64MB'; SET statement_timeout='900s'")
A, B = '2023-05-01', '2023-08-01'
MK = pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s", c, params=(A, B))
MK = MK[[group(str(e)) is None for e in MK.event_name]]
R = pd.read_sql("SELECT market_id,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND sel='The Draw' AND status IN ('WINNER','LOSER')", c)
MK = MK.merge(R, on='market_id', how='left')
MK['off_draw'] = MK.status.map({'WINNER': 1.0, 'LOSER': 0.0})
print('A official, senior MO markets May-Jul 2023: markets', len(MK), 'with result', int(MK.off_draw.notna().sum()), 'Draw share', round(MK.off_draw.mean(), 3))
F = pd.read_sql("SELECT fixture_id,season,league_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND kickoff>=%s AND kickoff<%s", c, params=(A, B))
F['d'] = (F.hg == F.ag).astype(float)
print('B af_fixtures FT May-Jul 2023: n', len(F), 'Draw share', round(F.d.mean(), 3))
print(F.groupby('season').d.agg(['size', 'mean']).round(3).to_string())
MP = set(pd.read_sql("SELECT substr(understat_id,3)::bigint f FROM af_price_map", c).f)
U = F[~F.fixture_id.isin(MP)]; print('B2 unmapped: n', len(U), 'Draw share', round(U.d.mean(), 3))
F['k'] = pd.to_datetime(F.kickoff, utc=True); F = F.sort_values('k').reset_index(drop=True)
F['H'] = F.home.map(norm); F['A'] = F.away.map(norm); kt = F.k.dt.tz_convert(None).values.astype('datetime64[ns]')
MK['mt'] = pd.to_datetime(MK.market_time, utc=True); fx = []
for r in MK.itertuples():
    h, _x, a = str(r.event_name).partition(' v ')
    lo = np.searchsorted(kt, np.datetime64((r.mt - pd.Timedelta(minutes=20)).tz_convert(None))); hi = np.searchsorted(kt, np.datetime64((r.mt + pd.Timedelta(minutes=20)).tz_convert(None)), side='right')
    fx.append(loose(norm(h), norm(a), [(q.H, q.A, int(q.fixture_id)) for q in F.iloc[lo:hi].itertuples()]))
MK['fx'] = fx; M = MK[MK.fx.notna()].copy(); M['fx'] = M.fx.astype(int); M = M.drop_duplicates('fx', keep=False)
M = M.merge(F[['fixture_id', 'd', 'k', 'season']], left_on='fx', right_on='fixture_id')
both = M[M.off_draw.notna()]
print('C matched to one fixture: n', len(M), 'af Draw share', round(M.d.mean(), 3), 'official Draw share', round(both.off_draw.mean(), 3), 'af agrees with official', round((both.d == both.off_draw).mean(), 3), 'on', len(both))
ids = list(M.market_id); fp = {}
for i in range(0, len(ids), 500):
    P = pd.read_sql("SELECT market_id,min(ts) f FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND sel='The Draw' AND inplay AND ltp>=1.01 AND ltp<1000 GROUP BY 1", c, params=(ids[i:i+500],))
    fp.update(dict(zip(P.market_id, secs(P.f))))
M['fp'] = M.market_id.map(fp); M['el'] = M.fp - M.k.map(lambda x: x.timestamp())
M['band'] = pd.cut(M.el, [-1e9, -300, 300, 900, 3000, 1e9], labels=['before ko-5', 'within 5 (the job)', '5-15', '15-50', '50+']).astype(object).fillna('no in-play print')
print('D matched games by first in-play Draw print against af kick-off:')
print(M.groupby('band').agg(n=('d', 'size'), af_draw=('d', 'mean'), official=('off_draw', 'mean')).round(3).to_string())
print('   by month, band within 5:'); W = M[M.band == 'within 5 (the job)']
print(W.groupby(W.k.dt.strftime('%Y-%m')).agg(n=('d', 'size'), af_draw=('d', 'mean'), official=('off_draw', 'mean')).round(3).to_string())
print('   later months, same read, Aug-Oct 2023 for comparison:')
c.close()
