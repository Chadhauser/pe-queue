import sys, psycopg2, pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/root/pe-queue/runner')
import creds
def side_of(name, ev):
    if name == 'DRAW':
        return 'DRAW'
    h, a = [x.upper() for x in ev.split(' v ', 1)]
    H, A = name in h, name in a
    return 'HOME' if H and not A else 'AWAY' if A and not H else None
def x_name(xs, names):
    if xs == 'THE DRAW':
        return 'DRAW' if 'DRAW' in names else None
    fit = [n for n in names if n != 'DRAW' and (n in xs or xs in n)]
    return fit[0] if len(fit) == 1 else None
con = psycopg2.connect(creds.pg_local())
HM = pd.read_sql("SELECT event_name ev,sel,ts,minute FROM liq_sample WHERE mkt='HT_MO' AND back_px<=1.2 AND lay_px<=1.2 ORDER BY ts", con)
HX = HM.groupby('ev').tail(1).set_index('ev')
print('last HT_MO winner row, minute quantiles', HX.minute.quantile([.05, .5, .95, .99]).to_dict())
D = pd.read_sql("SELECT event_name ev,mkt,sel,ts,minute,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt=ANY(%s) AND minute>=40 AND back_px IS NOT NULL AND lay_px IS NOT NULL", con, params=(['HTFT', 'MO'],))
con.close()
rows = []
for ev, g in D.groupby('ev', sort=False):
    if ev not in HX.index or ' v ' not in ev:
        continue
    hf = g[g.mkt == 'HTFT']
    mo = g[g.mkt == 'MO'].drop_duplicates(['ts', 'sel'], keep=False)
    if hf.empty or mo.empty:
        continue
    names = {p for s in hf.sel.unique() for p in s.split('/') if '/' in s}
    xn = x_name(HX.loc[ev, 'sel'], names)
    if xn is None:
        continue
    hf = hf.assign(pre=hf.sel.str.split('/').str[0], f=hf.sel.str.split('/').str[-1])
    hf['s'] = [side_of(f, ev) for f in hf.f]
    j = hf.merge(mo[['ts', 'sel', 'b', 'l']].rename(columns=dict(sel='s', b='mb', l='ml')), on=['ts', 's'])
    j['isx'] = j.pre == xn
    j['after'] = j.ts > HX.loc[ev, 'ts']
    rows.append(j[['ev', 'minute', 'b', 'l', 'mb', 'ml', 'isx', 'after']])
T = pd.concat(rows)
T = T[(T.l <= T.b * 1.25) & (T.ml <= T.mb * 1.05)]
T['gap'] = 100 * (2 / (T.b + T.l) - 2 / (T.mb + T.ml))
T['band'] = pd.cut(T.minute, [39, 45, 51, 60, 75, 200], labels=['40-45', '46-51', '52-60', '61-75', '76+'])
print('tight books only; gap = mid implied HT/FT less mid implied MO, points')
print(T.groupby(['isx', 'band'], observed=True).gap.agg(n='count', median='median', mad=lambda x: (x - x.median()).abs().median()).round(2).to_string())
print('after the HT_MO winner row, X runners, minute 52+'); s = T[T.isx & T.after & (T.minute >= 52)]
print(len(s), 'share within 3 points', round((s.gap.abs() <= 3).mean(), 3))
print('by game: worst median gap'); print(s.groupby('ev').gap.median().abs().sort_values().tail(5).round(1).to_string())
