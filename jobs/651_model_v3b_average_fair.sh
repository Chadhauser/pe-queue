#!/bin/bash
# 651 (Tue 17 Nov 2026, 15:15). football-data stopped carrying Pinnacle closing odds in Jan 2026, so the v3 rules cannot be paper-tested
# against Pinnacle going forward. Re-run v3 with the bookmakers' AVERAGE closing/opening price (AvgC*/Avg*, margin removed) as fair -
# published every week - including over/under 2.5 at 2 minutes. Same method: margin chosen on the older half, judged on the newer half.
# Background, 3 h cap. Writes reports/model_v3b.md.
cat > /root/pe-sports/team/model_v3b.py <<'PY'
#!/usr/bin/env python3
"""651 Fair price v3b: the MARKET AVERAGE (football-data AvgC*, margin removed) as the fair price - Pinnacle closing left football-data in Jan 2026, the average is there every week. Otherwise as 648, Betfair as the place to bet. What the solo winners do.
Football MATCH_ODDS and OVER_UNDER_25, Betfair Basic history 2019 onward (bf_hist_other) joined to football-data (fd_matches) by date and
team names. Fair = Pinnacle with its margin removed: CLOSING odds against the Betfair price 2 minutes before the off, OPENING odds against
the Betfair price 6 hours before the off (the softer, earlier price). Bet when the Betfair price, one tick worse, beats fair by m.
The margin is CHOSEN on the older half of matches and only REPORTED on the newer half. £2, 2% commission, settled from Betfair results."""
import sys, re, unicodedata, datetime as dt, psycopg2, pandas as pd, numpy as np
sys.path.insert(0, '/root/pe-queue/runner'); import creds
COMM = 0.02; ST = 2.0; MS = (0.01, 0.02, 0.03, 0.05, 0.08)
LADDER = [(2, .01), (3, .02), (4, .05), (6, .1), (10, .2), (20, .5), (30, 1), (50, 2), (100, 5), (1000, 10)]
def up(p):
    for hi, t in LADDER:
        if p < hi - 1e-9: return round(min(1000, p + t), 2)
    return 1000.0
def down(p):
    for hi, t in LADDER:
        if p - 1e-9 < hi: return round(max(1.01, p - t), 2)
    return round(p - 10, 2)
assert up(2.0) == 2.02 and down(2.0) == 1.99 and up(1.99) == 2.0 and down(3.0) == 2.98
STOP = {'fc', 'cf', 'sc', 'afc', 'ac', 'fk', 'sk', 'if', 'bk', 'cd', 'ud', 'sd', 'de', 'the', 'club', 'calcio', 'ssc', 'as', 'us', 'rc', 'vfb', 'vfl', 'tsg', 'sv', 'fsv', 'real', 'town', 'city', 'united', 'utd', 'athletic', 'sporting'}
ALIAS = {'wolves': 'wolverhampton', 'spurs': 'tottenham', 'man': 'manchester', 'nottm': 'nottingham', 'sheff': 'sheffield', 'psg': 'paris',
         'inter': 'internazionale', 'mgladbach': 'monchengladbach', 'munchen': 'munich', 'muenchen': 'munich', 'qpr': 'queens'}
def toks(s):
    s = unicodedata.normalize('NFKD', str(s or '')).encode('ascii', 'ignore').decode().lower()
    return {ALIAS.get(w, w) for w in re.findall(r'[a-z0-9]+', s) if w not in STOP and len(w) > 2}
def same(a, b): return bool(toks(a) & toks(b))
assert same('Man City', 'Manchester City') and same('Bayern Munich', 'Bayern München') and not same('Arsenal', 'Chelsea') and same('Wolves', 'Wolverhampton') and same('Sheff Utd', 'Sheffield United') and same('Nottm Forest', 'Nottingham Forest')
def devig(*odds):
    inv = [1 / o for o in odds]; s = sum(inv); return [x / s for x in inv]
assert abs(sum(devig(2.0, 3.5, 4.0)) - 1) < 1e-12
def settle(side, px, won):
    g = ((px - 1) * ST if won else -ST) if side == 'BACK' else (-(px - 1) * ST if won else ST)
    return g * (1 - COMM) if g > 0 else g
assert settle('BACK', 3.0, True) == 3.92 and settle('LAY', 3.0, True) == -4.0 and settle('LAY', 3.0, False) == 1.96
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor(); c.execute("SET statement_timeout='10500s'"); c.execute("SET work_mem='256MB'")
FD = pd.read_sql("""SELECT date, home, away, (raw->>'AvgH')::float ah, (raw->>'AvgD')::float ad, (raw->>'AvgA')::float aa,
   (raw->>'AvgCH')::float ach, (raw->>'AvgCD')::float acd, (raw->>'AvgCA')::float aca, (raw->>'Avg>2.5')::float ao, (raw->>'Avg<2.5')::float au,
   (raw->>'AvgC>2.5')::float aco, (raw->>'AvgC<2.5')::float acu FROM fd_matches WHERE date >= '2019-01-01' AND raw ? 'AvgCH'""", con)
FD['date'] = pd.to_datetime(FD.date).dt.date
BYDATE = {d: g for d, g in FD.groupby('date')}
def bf(mt, secs):
    q = """WITH p AS (SELECT DISTINCT ON (o.market_id, o.sel) o.market_id, o.sel, o.event_name, o.market_time, o.ltp FROM bf_hist_other o
              WHERE o.sport='Soccer' AND o.market_type=%s AND NOT o.inplay AND o.ltp>1 AND o.ltp<1000 AND o.market_time>='2019-01-01'
                AND o.ts <= o.market_time - make_interval(secs => %s) AND o.ts >= o.market_time - make_interval(secs => %s)
              ORDER BY o.market_id, o.sel, o.ts DESC)
           SELECT p.*, (r.status='WINNER')::int AS won FROM p JOIN bf_hist_result r ON r.market_id=p.market_id AND r.sel=p.sel WHERE r.status IN ('WINNER','LOSER')"""
    return pd.read_sql(q, con, params=(mt, secs, secs + 3 * 3600))
out = [f"# Fair price v3b — market-average fair, Betfair price — {dt.datetime.utcnow():%F %H:%M} UTC", "",
       "Fair = the bookmakers' average price with its margin removed (football-data AvgC*). 2 min before the off against the closing average; 6 h before against the opening average.",
       "Bet one tick worse than the last Betfair trade. Margin picked on the OLDER half, judged on the NEWER half. £2, 2% commission.", ""]
bets = []; joins = {}
for mt, legs in (('MATCH_ODDS', ('home', 'draw', 'away')), ('OVER_UNDER_25', ('over', 'under'))):
    for timing, secs in (('2 min', 120), ('6 h', 6 * 3600)):
        try: B = bf(mt, secs)
        except Exception as e: out.append(f"- {mt} {timing}: Betfair query failed ({str(e)[:80]})"); con.rollback(); continue
        B['ltp'] = B.ltp.astype(float); B['d'] = pd.to_datetime(B.market_time, utc=True).dt.date
        n_mk = B.market_id.nunique(); n_ok = 0
        for mid, g in B.groupby('market_id'):
            ev = str(g.event_name.iloc[0]); d = g.d.iloc[0]
            if ' v ' not in ev: continue
            h, a = ev.split(' v ', 1)
            cand = [r for r in BYDATE.get(d, pd.DataFrame()).itertuples() if same(r.home, h) and same(r.away, a)] if d in BYDATE else []
            if len(cand) != 1: continue
            r = cand[0]
            if mt == 'MATCH_ODDS':
                o = (r.ach, r.acd, r.aca) if timing == '2 min' else (r.ah, r.ad, r.aa)
                if any(pd.isna(x) or x <= 1 for x in o): continue
                fp = dict(zip(legs, devig(*o)))
                def leg(sel): return 'draw' if 'draw' in sel.lower() else ('home' if same(sel, h) and not same(sel, a) else ('away' if same(sel, a) and not same(sel, h) else None))
            else:
                ou = (r.aco, r.acu) if timing == '2 min' else (r.ao, r.au)
                if any(pd.isna(x) or x <= 1 for x in ou): continue
                fp = dict(zip(legs, devig(*ou)))
                def leg(sel): return 'over' if 'over' in sel.lower() else ('under' if 'under' in sel.lower() else None)
            ok = False
            for x in g.itertuples():
                lg = leg(str(x.sel))
                if lg is None: continue
                ok = True; p = fp[lg]
                pb = down(x.ltp); pl = up(x.ltp)
                bets.append((mt, timing, lg, 'BACK', x.market_time, p * pb - 1, settle('BACK', pb, x.won)))
                bets.append((mt, timing, lg, 'LAY', x.market_time, 1 - p * pl, settle('LAY', pl, x.won)))
            n_ok += ok
        joins[(mt, timing)] = (n_mk, n_ok)
out += ["## Matched", ""] + [f"- {k[0]} {k[1]}: {v[1]:,} of {v[0]:,} Betfair markets matched to an average price" for k, v in joins.items()] + [""]
D = pd.DataFrame(bets, columns=['mt', 'timing', 'leg', 'side', 't', 'val', 'pnl'])
if D.empty:
    open('/root/pe-queue/reports/model_v3b.md', 'w').write("\n".join(out + ["no bets"]) + "\n"); sys.exit()
split = D.t.quantile(0.5)
out += ["## Newer half, with the margin chosen on the older half (per £100 staked)", "",
        "| market | timing | outcome | side | margin chosen | older-half bets | older £/100 | NEWER bets | NEWER £/100 | NEWER £ at £2 |", "|---|---|---|---|---|---|---|---|---|---|"]
keep = []
for (mt, tm, lg, sd), g in D.groupby(['mt', 'timing', 'leg', 'side']):
    h1 = g[g.t < split]; h2 = g[g.t >= split]
    best = None
    for m in MS:
        a = h1[h1.val >= m]
        if len(a) >= 300:
            r = a.pnl.sum() / (len(a) * ST) * 100
            if best is None or r > best[1]: best = (m, r, len(a))
    if best is None: continue
    b = h2[h2.val >= best[0]]; r2 = b.pnl.sum() / max(1, len(b) * ST) * 100
    keep.append((mt, tm, lg, sd, best[0], best[2], best[1], len(b), r2, b.pnl.sum()))
for k in sorted(keep, key=lambda x: -x[8]):
    flag = ' ✅' if k[6] > 0 and k[8] > 0 and k[7] >= 100 else ''
    out.append(f"| {k[0]} | {k[1]} | {k[2]} | {k[3]} | {k[4]:.0%} | {k[5]} | £{k[6]:+.1f} | {k[7]} | £{k[8]:+.1f} | £{k[9]:+.2f}{flag} |")
out += ["", "✅ = profitable on BOTH halves with 100+ newer-half bets. These go onto forward paper under the same 100-bet gate."]
open('/root/pe-queue/reports/model_v3b.md', 'w').write("\n".join(out) + "\n"); print("\n".join(out))
pd.DataFrame(keep, columns=['mt', 'timing', 'leg', 'side', 'm', 'n1', 'r1', 'n2', 'r2', 'pnl2']).to_csv('/root/pe-sports/team/model_v3b_cells.csv', index=False)
PY
python3 -m py_compile /root/pe-sports/team/model_v3b.py && echo compiles || exit 1
cd /root/pe-sports/team && PGAPPNAME=batch_651 nohup setsid bash -c 'nice -n 10 timeout 10800 python3 model_v3b.py > model_v3b.log 2>&1 || echo "STOPPED: $(tail -3 model_v3b.log)" >> /root/pe-queue/reports/model_v3b.md; cd /root/pe-queue && git add reports/model_v3b.md && git commit -qm "model v3b (651)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q' >/dev/null 2>&1 < /dev/null &
sleep 20; echo "651 started"
