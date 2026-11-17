#!/bin/bash
# 652 + 653 (Tue 17 Nov 2026, 16:30). Two data-led tests on data we already own, no purchase (Peter: "be smarter, this is a business"):
#  652 cross-market coherence: price Betfair's THIN markets (over/under 1.5/3.5/4.5, both teams to score, correct score) from its own DEEP
#      ones (match odds + over/under 2.5) with a Poisson score model; bet the thin market when it disagrees. Writes reports/coherence.md.
#  653 team news: regulars missing (API-Football minutes) against the Betfair price move from 55 to 2 min before the off; trade in and out.
#      Writes reports/team_news.md.
# Both: rule chosen on the older half, judged on the newer half. Background, one after the other, 3 h cap each.
T=/root/pe-sports/team
cat > $T/coherence.py <<'PY'
#!/usr/bin/env python3
"""652 Cross-market coherence: price Betfair's THIN football markets from its own DEEP ones. No outside data.
For every match, take the last Betfair trade 2-180 min before the off in match odds and over/under 2.5 (the deep, sharp markets), remove
the margin, and fit the two goal rates (home, away) of a Poisson score model that reproduce them. From those two numbers every thin market
on the same match has a fair price: over/under 1.5, 3.5, 4.5, both teams to score, correct score. Bet a thin market when its Betfair
price, one tick worse, beats that fair price by m. m is CHOSEN on the older half of matches and judged on the newer half.
£2, 2% commission, settled from Betfair results."""
import sys, re, datetime as dt, psycopg2, pandas as pd, numpy as np
from math import factorial
sys.path.insert(0, '/root/pe-queue/runner'); import creds
COMM = 0.02; ST = 2.0; MS = (0.0, 0.02, 0.04, 0.06, 0.10)
LADDER = [(2, .01), (3, .02), (4, .05), (6, .1), (10, .2), (20, .5), (30, 1), (50, 2), (100, 5), (1000, 10)]
def up(p):
    for hi, t in LADDER:
        if p < hi - 1e-9: return round(min(1000, p + t), 2)
    return 1000.0
def down(p):
    for hi, t in LADDER:
        if p - 1e-9 < hi: return round(max(1.01, p - t), 2)
    return round(p - 10, 2)
assert up(2.0) == 2.02 and down(2.0) == 1.99
# ---- Poisson grid: every (home rate, away rate) pair and the probabilities it implies
G = np.round(np.arange(0.15, 4.01, 0.05), 2); N = 11
pois = np.array([[np.exp(-l) * l ** k / factorial(k) for k in range(N)] for l in G])            # [rate, goals]
LH, LA = np.meshgrid(np.arange(len(G)), np.arange(len(G)), indexing='ij'); LH = LH.ravel(); LA = LA.ravel()
M = pois[LH][:, :, None] * pois[LA][:, None, :]                                                   # [pair, home goals, away goals]
M = M / M.sum((1, 2), keepdims=True)                                                             # put the >10-goal tail back in
hg, ag = np.meshgrid(np.arange(N), np.arange(N), indexing='ij'); tot = hg + ag
P = {'home': (M * (hg > ag)).sum((1, 2)), 'draw': (M * (hg == ag)).sum((1, 2)), 'away': (M * (hg < ag)).sum((1, 2))}
for ln in (1.5, 2.5, 3.5, 4.5): P[f'over{ln}'] = (M * (tot > ln)).sum((1, 2))
P['btts'] = (M * ((hg > 0) & (ag > 0))).sum((1, 2))
for i in range(4):
    for j in range(4): P[f'cs{i}-{j}'] = M[:, i, j]
small = (hg <= 3) & (ag <= 3)
P['cs_aoh'] = (M * (~small & (hg > ag))).sum((1, 2)); P['cs_aoa'] = (M * (~small & (hg < ag))).sum((1, 2)); P['cs_aod'] = (M * (~small & (hg == ag))).sum((1, 2))
assert np.allclose(P['home'] + P['draw'] + P['away'], 1, atol=1e-6)
cs_sum = sum(P[f'cs{i}-{j}'] for i in range(4) for j in range(4)) + P['cs_aoh'] + P['cs_aoa'] + P['cs_aod']; assert np.allclose(cs_sum, 1, atol=1e-6)
TARGET = np.stack([P['home'], P['draw'], P['away'], P['over2.5']], 1)                              # what the deep markets pin down
def fit(obs):
    """obs [n,4] devigged home/draw/away/over2.5 -> index of the best pair for each match (least squares)."""
    out = np.empty(len(obs), int)
    for i in range(0, len(obs), 1500):
        o = obs[i:i + 1500]; d = ((o[:, None, :] - TARGET[None, :, :]) ** 2).sum(2); out[i:i + 1500] = d.argmin(1)
    return out
k = fit(np.array([[P['home'][1234], P['draw'][1234], P['away'][1234], P['over2.5'][1234]]])); assert k[0] == 1234   # known answer
def settle(side, px, won):
    g = ((px - 1) * ST if won else -ST) if side == 'BACK' else (-(px - 1) * ST if won else ST)
    return g * (1 - COMM) if g > 0 else g
def sel_key(mt, sel):
    s = str(sel).lower()
    if mt == 'MATCH_ODDS': return 'draw' if 'draw' in s else None
    if mt.startswith('OVER_UNDER_'):
        ln = int(mt[-2:]) / 10
        return (f'over{ln}' if 'over' in s else (f'under{ln}' if 'under' in s else None))
    if mt == 'BOTH_TEAMS_TO_SCORE': return 'btts' if s.strip() == 'yes' else ('btts_no' if s.strip() == 'no' else None)
    if mt == 'CORRECT_SCORE':
        m = re.match(r'^\s*(\d)\s*-\s*(\d)\s*$', s)
        if m and int(m.group(1)) <= 3 and int(m.group(2)) <= 3: return f'cs{m.group(1)}-{m.group(2)}'
        if 'any other home' in s: return 'cs_aoh'
        if 'any other away' in s: return 'cs_aoa'
        if 'any other draw' in s: return 'cs_aod'
    return None
assert sel_key('OVER_UNDER_35', 'Over 3.5 Goals') == 'over3.5' and sel_key('CORRECT_SCORE', '2 - 1') == 'cs2-1' and sel_key('BOTH_TEAMS_TO_SCORE', 'Yes') == 'btts'
def fair_p(key, idx):
    if key.startswith('under'): return 1 - P['over' + key[5:]][idx]
    if key == 'btts_no': return 1 - P['btts'][idx]
    return P[key][idx]
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor(); c.execute("SET statement_timeout='10000s'"); c.execute("SET work_mem='256MB'")
TYPES = ['MATCH_ODDS', 'OVER_UNDER_25', 'OVER_UNDER_15', 'OVER_UNDER_35', 'OVER_UNDER_45', 'BOTH_TEAMS_TO_SCORE', 'CORRECT_SCORE']
frames = []
for mt in TYPES:
    q = """WITH p AS (SELECT DISTINCT ON (o.market_id, o.sel) o.market_id, o.sel, o.event_name, o.market_time, o.ltp FROM bf_hist_other o
              WHERE o.sport='Soccer' AND o.market_type=%s AND NOT o.inplay AND o.ltp>1 AND o.ltp<1000
                AND o.ts <= o.market_time - interval '120 seconds' AND o.ts >= o.market_time - interval '3 hours'
              ORDER BY o.market_id, o.sel, o.ts DESC)
           SELECT p.*, (r.status='WINNER')::int AS won FROM p JOIN bf_hist_result r ON r.market_id=p.market_id AND r.sel=p.sel WHERE r.status IN ('WINNER','LOSER')"""
    try: d = pd.read_sql(q, con, params=(mt,)); d['mt'] = mt; frames.append(d); print(mt, len(d), flush=True)
    except Exception as e: print(mt, "query failed", str(e)[:100], flush=True); con.rollback()
X = pd.concat(frames); X['ltp'] = X.ltp.astype(float); X['ev'] = X.event_name.astype(str) + '|' + X.market_time.astype(str)
# deep markets -> observed probabilities per match
mo = X[X.mt == 'MATCH_ODDS'].copy(); ou = X[X.mt == 'OVER_UNDER_25'].copy()
def leg_mo(r):
    s = str(r.sel).lower()
    if 'draw' in s: return 'draw'
    h, _, a = str(r.event_name).partition(' v ')
    return 'home' if str(r.sel) == h.strip() else ('away' if str(r.sel) == a.strip() else None)
mo['leg'] = [leg_mo(r) for r in mo.itertuples()]
mo = mo.dropna(subset=['leg']).pivot_table(index='ev', columns='leg', values='ltp', aggfunc='last').dropna()
ou['leg'] = np.where(ou.sel.astype(str).str.lower().str.contains('over'), 'o', 'u')
ou = ou.pivot_table(index='ev', columns='leg', values='ltp', aggfunc='last').dropna()
D = mo.join(ou, how='inner')
inv = 1 / D[['home', 'draw', 'away']]; mo_p = inv.div(inv.sum(1), axis=0)
oi = 1 / D[['o', 'u']]; ou_p = oi['o'] / oi.sum(1)
obs = np.column_stack([mo_p.home, mo_p.draw, mo_p.away, ou_p]); idx = pd.Series(fit(obs), index=D.index)
err = np.sqrt(((obs - TARGET[idx.values]) ** 2).mean(1)); good = pd.Series(err < 0.02, index=D.index)   # deep markets must be self-consistent
print("matches with both deep markets:", len(D), "well fitted:", int(good.sum()), flush=True)
# thin markets
T = X[X.mt.isin(TYPES[2:])].copy()
T['key'] = [sel_key(a, b) for a, b in zip(T.mt, T.sel)]; T = T.dropna(subset=['key'])
T = T[T.ev.isin(good[good].index)]; T['i'] = T.ev.map(idx)
T['fp'] = [fair_p(kk, ii) for kk, ii in zip(T.key, T.i)]
T['pb'] = T.ltp.map(down); T['pl'] = T.ltp.map(up)
T['vb'] = T.fp * T.pb - 1; T['vl'] = 1 - T.fp * T.pl
T['t'] = pd.to_datetime(T.market_time, utc=True); split = T.t.quantile(0.5)
T['grp'] = T.mt.str.replace('OVER_UNDER_', 'OU') + ' ' + T.key.str.replace(r'^(over|under)\d\.\d', lambda m: m.group(1), regex=True)
out = [f"# Cross-market coherence — thin markets priced from deep ones — {dt.datetime.utcnow():%F %H:%M} UTC", "",
       f"Matches with match odds and over/under 2.5 both traded 2-180 min before the off: {len(D):,}; deep markets self-consistent (fit error < 2%): {int(good.sum()):,}.",
       "Thin market bet one tick worse than its last trade; margin chosen on the OLDER half, judged on the NEWER half; £2, 2% commission.", "",
       "Calibration on the newer half (lower = better): log loss of the Poisson fair price vs the thin market's own price.", ""]
for g, d in T[T.t >= split].groupby('grp'):
    if len(d) < 2000: continue
    y = d.won.values; pm = np.clip(1 / d.ltp.values, 1e-4, 1 - 1e-4); pf = np.clip(d.fp.values, 1e-4, 1 - 1e-4)
    ll = lambda p: -np.mean(y * np.log(p) + (1 - y) * np.log(1 - p))
    out.append(f"- {g}: Poisson {ll(pf):.4f} vs market {ll(pm):.4f} ({len(d):,} runners)")
out += ["", "| thin market | side | margin | older bets | older £/100 | NEWER bets | NEWER £/100 | NEWER £ at £2 |", "|---|---|---|---|---|---|---|---|"]
rows = []
for g, d in T.groupby('grp'):
    for side, vcol, pcol in (('BACK', 'vb', 'pb'), ('LAY', 'vl', 'pl')):
        d = d.copy(); d['pnl'] = [settle(side, p, w) for p, w in zip(d[pcol], d.won)]
        h1 = d[d.t < split]; h2 = d[d.t >= split]; best = None
        for m in MS:
            a = h1[h1[vcol] >= m]
            if len(a) >= 300:
                r = a.pnl.sum() / (len(a) * ST) * 100
                if best is None or r > best[1]: best = (m, r, len(a))
        if not best: continue
        b = h2[h2[vcol] >= best[0]]
        rows.append((g, side, best[0], best[2], best[1], len(b), b.pnl.sum() / max(1, len(b) * ST) * 100, b.pnl.sum()))
for r in sorted(rows, key=lambda x: -x[6]):
    flag = ' ✅' if r[4] > 0 and r[6] > 0 and r[5] >= 150 else ''
    out.append(f"| {r[0]} | {r[1]} | {r[2]:.0%} | {r[3]} | £{r[4]:+.1f} | {r[5]} | £{r[6]:+.1f} | £{r[7]:+.2f}{flag} |")
out += ["", "✅ = profitable on BOTH halves with 150+ newer-half bets: goes onto forward paper under the 100-bet gate."]
open('/root/pe-queue/reports/coherence.md', 'w').write("\n".join(out) + "\n"); print("\n".join(out))
pd.DataFrame(rows, columns=['grp', 'side', 'm', 'n1', 'r1', 'n2', 'r2', 'pnl2']).to_csv('/root/pe-sports/team/coherence_cells.csv', index=False)
PY
cat > $T/team_news.py <<'PY'
#!/usr/bin/env python3
"""653 Team news: does knowing which regular players are missing (line-ups come out ~60 min before kick-off) predict how the Betfair
match-odds price moves before the off? Data we own: API-Football player minutes (af_player_stats) and Betfair history (bf_hist_other).
A 'regular' played 60+ minutes in at least 3 of the team's previous 5 matches. 'Missing' = a regular with no minutes in this match.
Signal d = home regulars missing - away regulars missing. Trade (in and out, never held to the result): when d >= k, LAY home at the last
price 55+ min before the off and BACK it back at the last price 2+ min before (one tick worse each way); when d <= -k, the reverse.
k is CHOSEN on the older half of matches and judged on the newer half. £2, 2% commission on winning greens."""
import sys, datetime as dt, psycopg2, pandas as pd, numpy as np
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-queue/jobs'); import creds
import lib_afmatch as AM
COMM = 0.02; ST = 2.0
LADDER = [(2, .01), (3, .02), (4, .05), (6, .1), (10, .2), (20, .5), (30, 1), (50, 2), (100, 5), (1000, 10)]
def up(p):
    for hi, t in LADDER:
        if p < hi - 1e-9: return round(min(1000, p + t), 2)
    return 1000.0
def down(p):
    for hi, t in LADDER:
        if p - 1e-9 < hi: return round(max(1.01, p - t), 2)
    return round(p - 10, 2)
def g_back_lay(b, l): return ST * (b / l - 1)
def g_lay_back(l, b): return ST * (1 - l / b)
def net(g): return g * (1 - COMM) if g > 0 else g
assert abs(g_back_lay(3.0, 2.5) - 0.4) < 1e-9 and abs(g_lay_back(2.5, 3.0) - 2 * (1 - 2.5 / 3)) < 1e-9
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor(); c.execute("SET statement_timeout='10000s'")
PS = pd.read_sql("""SELECT s.fixture_id, s.team, s.player_id, coalesce(s.minutes,0) AS minutes, f.kickoff, f.home, f.away
                    FROM af_player_stats s JOIN af_fixtures f USING (fixture_id) WHERE f.status IN ('FT','AET','PEN')""", con)
out = [f"# Team news — regulars missing vs the Betfair price move before the off — {dt.datetime.utcnow():%F %H:%M} UTC", ""]
if PS.empty:
    open('/root/pe-queue/reports/team_news.md', 'w').write("\n".join(out + ["no player data"]) + "\n"); sys.exit()
PS['kickoff'] = pd.to_datetime(PS.kickoff, utc=True)
# regulars per team before each fixture
miss = {}
for team, g in PS.groupby('team'):
    fx = g.groupby('fixture_id').kickoff.first().sort_values()
    order = list(fx.index)
    played = {f: dict(zip(x.player_id, x.minutes)) for f, x in g.groupby('fixture_id')}
    for n, f in enumerate(order):
        if n < 5: continue
        prev = order[n - 5:n]; cnt = {}
        for p in prev:
            for pid, mins in played[p].items():
                if mins >= 60: cnt[pid] = cnt.get(pid, 0) + 1
        regs = [pid for pid, k in cnt.items() if k >= 3]
        miss[(f, team)] = sum(1 for pid in regs if played[f].get(pid, 0) == 0)
FX0 = PS.groupby('fixture_id').agg(kickoff=('kickoff', 'first'), home=('home', 'first'), away=('away', 'first')).reset_index()
FX0['d'] = [miss.get((r.fixture_id, r.home), np.nan) - miss.get((r.fixture_id, r.away), np.nan) for r in FX0.itertuples()]
FX0 = FX0.dropna(subset=['d'])
out.append(f"Fixtures with player minutes for both teams and 5 previous matches each: {len(FX0):,} ({FX0.kickoff.min():%d %b %Y} to {FX0.kickoff.max():%d %b %Y}).")
a, b = FX0.kickoff.min() - pd.Timedelta(days=1), FX0.kickoff.max() + pd.Timedelta(days=1)
FX = AM.fixtures(con, a, b, unmapped_only=False)
MK = AM.match(con, 'MATCH_ODDS', a, b, FX)
MK = MK.merge(FX0[['fixture_id', 'd']], left_on='fx', right_on='fixture_id')
out.append(f"Matched to a Betfair match-odds market: {len(MK):,}.")
mids = list(MK.market_id)
pr = []
for i in range(0, len(mids), 500):
    pr.append(pd.read_sql("""SELECT market_id, sel, ts, market_time, ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS'
                             AND market_id = ANY(%s) AND NOT inplay AND ltp > 1 AND ltp < 1000 AND ts >= market_time - interval '4 hours' AND ts <= market_time""",
                          con, params=(mids[i:i + 500],)))
PR = pd.concat(pr) if pr else pd.DataFrame(columns=['market_id','sel','ts','market_time','ltp'])
PRG = {m: g for m, g in PR.groupby('market_id')}
rows = []
for r in MK.itertuples():
    h = str(r.event_name).partition(' v ')[0].strip()
    x = PRG.get(r.market_id)
    if x is None: continue
    x = x[x.sel.str.strip() == h]
    if x.empty: continue
    mt = pd.to_datetime(x.market_time.iloc[0], utc=True); ts = pd.to_datetime(x.ts, utc=True)
    e = x[ts <= mt - pd.Timedelta(minutes=55)]; z = x[(ts <= mt - pd.Timedelta(minutes=2)) & (ts > mt - pd.Timedelta(minutes=50))]
    if e.empty or z.empty: continue
    p0 = float(e.sort_values('ts').ltp.iloc[-1]); p1 = float(z.sort_values('ts').ltp.iloc[-1])
    rows.append(dict(t=mt, d=r.d, p0=p0, p1=p1, mv=np.log(p1 / p0),
                     lay=net(g_lay_back(up(p0), down(p1))), back=net(g_back_lay(down(p0), up(p1)))))
R = pd.DataFrame(rows)
out.append(f"With a home price both 55+ min and 2-50 min before the off: {len(R):,}."); out.append("")
if R.empty:
    open('/root/pe-queue/reports/team_news.md', 'w').write("\n".join(out) + "\n"); sys.exit()
out += ["## Home price move from 55 min to 2 min before the off, by regulars missing (home minus away)", "",
        "| home missing minus away | matches | average move (log, + = home drifted) | share drifted |", "|---|---|---|---|"]
R['db'] = R.d.clip(-3, 3)
for k, g in R.groupby('db'):
    out.append(f"| {int(k):+d}{'+' if abs(k) == 3 else ''} | {len(g)} | {g.mv.mean():+.4f} | {(g.mv > 0).mean():.0%} |")
split = R.t.quantile(0.5); h1 = R[R.t < split]; h2 = R[R.t >= split]
def trade(df, k):
    a = df[df.d >= k].lay; b = df[df.d <= -k].back; return pd.concat([a, b])
res = [(k, trade(h1, k)) for k in (1, 2, 3)]
ok = [(k, s) for k, s in res if len(s) >= 100]
out += ["", "## Trade it (lay the weakened home side at 55 min, back it at 2 min; the reverse for a weakened away side)", ""]
for k, s in res: out.append(f"- older half, k={k}: {len(s)} trades, £{s.sum():+.2f} (£{s.sum() / max(1, len(s) * ST) * 100:+.1f} per £100)")
if ok:
    kb = max(ok, key=lambda x: x[1].sum() / len(x[1]))[0]; s2 = trade(h2, kb); s1 = trade(h1, kb)
    flag = ' ✅ both halves' if s1.sum() > 0 and s2.sum() > 0 and len(s2) >= 100 else ''
    out.append(f"- CHOSEN k={kb}; NEWER half: {len(s2)} trades, £{s2.sum():+.2f} (£{s2.sum() / max(1, len(s2) * ST) * 100:+.1f} per £100){flag}")
ctrl = pd.concat([R.lay, R.back]); out.append(f"- control, every match both ways: {len(ctrl)} trades, £{ctrl.sum():+.2f} (£{ctrl.sum() / (len(ctrl) * ST) * 100:+.1f} per £100) — the cost of trading with no signal")
open('/root/pe-queue/reports/team_news.md', 'w').write("\n".join(out) + "\n"); print("\n".join(out))
PY
python3 -m py_compile $T/coherence.py $T/team_news.py && echo compiles || exit 1
cd $T && PGAPPNAME=batch_652 nohup setsid bash -c 'nice -n 10 timeout 10800 python3 coherence.py > coherence.log 2>&1 || echo "STOPPED: $(tail -3 coherence.log)" >> /root/pe-queue/reports/coherence.md; nice -n 10 timeout 10800 python3 team_news.py > team_news.log 2>&1 || echo "STOPPED: $(tail -3 team_news.log)" >> /root/pe-queue/reports/team_news.md; cd /root/pe-queue && git add reports/coherence.md reports/team_news.md; git commit -qm "652/653 coherence + team news" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q' >/dev/null 2>&1 < /dev/null &
sleep 20; echo "652/653 started"
