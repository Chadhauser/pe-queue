#!/bin/bash
# 629 (Tue 17 Nov 2026, 07:10). Peter: "why can't you go back and test those bets it lost on?" Loser autopsy on the kept cells' full history:
# what the losing bets have in common (price vs fair, last-hour move, hour, weekday, country); a filter learned on the older half only and
# judged on the newer half; plus the bot's own losing paper bets. Background (one query per market type, each under 4 minutes).
# Writes reports/loser_autopsy.md.
cat > /root/pe-sports/team/loser_autopsy.py <<'PY'
#!/usr/bin/env python3
"""629 Loser autopsy. Peter: "why can't you go back and test those bets it lost on?"
For every kept cell, rebuild every historical bet at a takeable price (last trade >=120 s before the off, one tick worse), then look at
what the LOSING bets have in common: how far the price was from fair, how the price moved in the last hour, hour of day, weekday, country.
A filter is built ONLY from the first half of history (drop any bucket that lost in half 1 with 50+ bets), then judged on the second half,
which the filter never saw. Also lists the bot's own losing paper bets with their price against fair."""
import sys, datetime as dt, psycopg2, pandas as pd, numpy as np
sys.path.insert(0, '/root/pe-queue/runner'); import creds
COMM = 0.02; ST = 2.0
LADDER = [(2, .01), (3, .02), (4, .05), (6, .1), (10, .2), (20, .5), (30, 1), (50, 2), (100, 5), (1000, 10)]
def tick(p):
    for hi, t in LADDER:
        if p < hi: return t
    return 10
def up(p): return round(min(1000, p + tick(p)), 2)
def down(p): return round(max(1.01, p - tick(p - 1e-9)), 2)
assert up(2.0) == 2.02 and down(2.0) == 1.99 and up(3.95) == 4.0
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor(); c.execute("SET statement_timeout='230s'")
c.execute("SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_other'"); cols = {r[0] for r in c.fetchall()}
ctry = 'country' if 'country' in cols else ('country_code' if 'country_code' in cols else None)
c.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed")
CELLS = [(s, m, float(a), float(b), sd, float(f)) for s, m, a, b, sd, f in c.fetchall()]
out = [f"# Loser autopsy — {dt.datetime.utcnow():%F %H:%M} UTC", "",
       "Every historical bet in the kept cells at a takeable price (one tick worse than the last trade 2 min before the off), £2, 2% commission.",
       "Filter learned on the OLDER half only; the NEWER half is the judge.", ""]
rows = []
for sport, mt in sorted({(s, m) for s, m, *_ in CELLS}):
    extra = f", o.{ctry} AS country" if ctry else ", NULL::text AS country"
    q = f"""WITH p AS (SELECT DISTINCT ON (o.market_id,o.sel) o.market_id,o.sel,o.market_time,o.ltp{extra} FROM bf_hist_other o
              WHERE o.sport=%s AND o.market_type=%s AND NOT o.inplay AND o.ltp>1 AND o.ltp<1000 AND o.ts<=o.market_time-interval '120 seconds'
              ORDER BY o.market_id,o.sel,o.ts DESC)
            SELECT p.*, (r.status='WINNER')::int won FROM p JOIN bf_hist_result r ON r.market_id=p.market_id AND r.sel=p.sel
            WHERE r.status IN ('WINNER','LOSER')"""
    try: df = pd.read_sql(q, con, params=(sport, mt))
    except Exception as e: out.append(f"- {sport} {mt}: price query failed ({str(e)[:70]})"); con.rollback(); continue
    q60 = """SELECT DISTINCT ON (o.market_id,o.sel) o.market_id,o.sel,o.ltp AS ltp60 FROM bf_hist_other o
             WHERE o.sport=%s AND o.market_type=%s AND NOT o.inplay AND o.ltp>1 AND o.ltp<1000 AND o.ts<=o.market_time-interval '60 minutes'
             ORDER BY o.market_id,o.sel,o.ts DESC"""
    try: d60 = pd.read_sql(q60, con, params=(sport, mt)); df = df.merge(d60, on=['market_id', 'sel'], how='left')
    except Exception as e: con.rollback(); df['ltp60'] = np.nan; out.append(f"- {sport} {mt}: 60-min price unavailable ({str(e)[:50]})")
    df['ltp'] = df.ltp.astype(float); df['ltp60'] = pd.to_numeric(df.ltp60, errors='coerce'); df['p'] = 1 / df.ltp
    for s, m, a, b, side, ff in [x for x in CELLS if x[0] == sport and x[1] == mt]:
        d = df[(df.p >= a) & (df.p < b)].copy()
        if d.empty: continue
        d['cell'] = f"{s} {m} {a:.2f}-{b:.2f} {side}"
        px = d.ltp.map(down if side == 'BACK' else up)
        g = np.where(side == 'BACK', np.where(d.won == 1, (px - 1) * ST, -ST), np.where(d.won == 1, -(px - 1) * ST, ST))
        d['pnl'] = np.where(g > 0, g * (1 - COMM), g)
        fair_p = d.p * ff
        d['val'] = np.where(side == 'BACK', fair_p * px - 1, 1 - fair_p * px)
        mv = (d.ltp - d.ltp60) / d.ltp60
        d['f_value'] = pd.cut(d.val, [-9, -0.02, 0, 0.01, 0.02, 0.04, 9], labels=['<-2%', '-2-0%', '0-1%', '1-2%', '2-4%', '4%+']).astype(str)
        d['f_move'] = np.select([mv.isna(), mv <= -0.05, mv < -0.01, mv <= 0.01, mv < 0.05], ['no 60m price', 'shortened 5%+', 'shortened 1-5%', 'flat', 'drifted 1-5%'], 'drifted 5%+')
        mt_ = pd.to_datetime(d.market_time, utc=True)
        d['f_hour'] = pd.cut(mt_.dt.hour, [-1, 11, 14, 17, 20, 24], labels=['<12', '12-14', '15-17', '18-20', '21+']).astype(str)
        d['f_weekend'] = np.where(mt_.dt.weekday >= 5, 'weekend', 'weekday')
        d['f_country'] = d.country.fillna('?').astype(str) if ctry else '?'
        rows.append(d)
if not rows:
    open('/root/pe-queue/reports/loser_autopsy.md', 'w').write("\n".join(out + ["no data"])); sys.exit()
D = pd.concat(rows).sort_values('market_time'); split = D.market_time.quantile(0.5)
FEATS = ['f_value', 'f_move', 'f_hour', 'f_weekend', 'f_country']
def p100(x): return x.pnl.sum() / (len(x) * ST) * 100 if len(x) else float('nan')
res = []; findings = []
for cl, d in D.groupby('cell'):
    h1 = d[d.market_time < split]; h2 = d[d.market_time >= split]
    if len(h1) < 200 or len(h2) < 100: continue
    keep1 = pd.Series(True, index=h1.index); keep2 = pd.Series(True, index=h2.index); dropped = []
    for f in FEATS:                                   # greedy: drop a feature's losing half-1 buckets only if it lifts half 1
        g = h1[keep1].groupby(f).pnl.agg(['count', 'sum'])
        g['per'] = g['sum'] / g['count']
        cand = [k for k, r in g.sort_values('per').iterrows() if r['count'] >= 50 and r['sum'] < 0]   # worst first
        bad = []
        for k in cand:
            t1 = keep1 & ~h1[f].isin(bad + [k])
            if t1.sum() >= 150 and p100(h1[t1]) > p100(h1[keep1 & ~h1[f].isin(bad)]): bad.append(k)
        if not bad: continue
        keep1 = keep1 & ~h1[f].isin(bad); keep2 = keep2 & ~h2[f].isin(bad); dropped.append(f"{f[2:]}: {', '.join(map(str, bad[:4]))}")
    res.append((cl, len(h2), p100(h2), int(keep2.sum()), p100(h2[keep2]), p100(h1), p100(h1[keep1]), '; '.join(dropped) or 'nothing to drop'))
out += ["## Each cell: newer half before and after the filter learned on the older half", "",
        "| cell | newer-half bets | per £100 now | bets after filter | per £100 after | what the losers had in common (dropped) |", "|---|---|---|---|---|---|"]
for cl, n2, a2, k2, b2, a1, b1, dr in sorted(res, key=lambda r: -(r[4] if r[3] else -99)):
    out.append(f"| {cl} | {n2} | £{a2:+.1f} | {k2} | £{b2:+.1f} | {dr} |")
tot_b = sum(r[1] for r in res); tot_a = sum(r[3] for r in res)
def wavg(idx_n, idx_v):
    n = sum(r[idx_n] for r in res); return sum(r[idx_n] * r[idx_v] for r in res if r[idx_n]) / n if n else float('nan')
out += ["", f"All cells, newer half: {tot_b} bets at £{wavg(1,2):+.1f} per £100 before; {tot_a} bets at £{wavg(3,4):+.1f} per £100 after the filter.", ""]
# where the losses sit, across all cells, newer half (for the reader, not used to fit)
out += ["## Where the losing money sits (all cells, older half, the half the filter learned from)", ""]
H1 = D[D.market_time < split]
for f in FEATS:
    g = H1.groupby(f).pnl.agg(['count', 'sum']); g['per100'] = g['sum'] / (g['count'] * ST) * 100
    g = g[g['count'] >= 100].sort_values('per100')
    out.append(f"- {f[2:]}: " + "; ".join(f"{k} £{r.per100:+.1f} (n {int(r['count'])})" for k, r in g.iterrows()))
# the bot's own paper losers
c.execute("""SELECT mkt, side, price, fair, won, pnl, event_name, version FROM bookie_paper WHERE status='settled' AND ts>'2026-11-11' ORDER BY ts""")
bp = pd.DataFrame(c.fetchall(), columns=['mkt', 'side', 'price', 'fair', 'won', 'pnl', 'event', 'version'])
if len(bp):
    bp[['price', 'fair', 'pnl']] = bp[['price', 'fair', 'pnl']].astype(float)
    bp['edge'] = np.where(bp.side == 'BACK', bp.price / bp.fair - 1, 1 - bp.price / bp.fair)
    bp['edge_b'] = pd.cut(bp.edge, [-9, 0.01, 0.03, 9], labels=['under 1%', '1-3%', '3%+']).astype(str)
    out += ["", f"## The bot's own settled paper bets since 11 Nov: {len(bp)}, £{bp.pnl.sum():+.2f}", ""]
    for k, g in bp.groupby('edge_b'): out.append(f"- price better than fair by {k}: {len(g)} bets, £{g.pnl.sum():+.2f}")
    out.append("")
    for k, g in bp.groupby(['mkt', 'side']): out.append(f"- {k[0]} {k[1]}: {len(g)} bets, £{g.pnl.sum():+.2f}")
open('/root/pe-queue/reports/loser_autopsy.md', 'w').write("\n".join(out) + "\n"); print("\n".join(out))
PY
python3 -m py_compile /root/pe-sports/team/loser_autopsy.py && echo compiles || exit 1
cd /root/pe-sports/team && nohup setsid bash -c 'nice -n 10 timeout 10800 python3 loser_autopsy.py > loser_autopsy.log 2>&1 || echo "STOPPED: see loser_autopsy.log" >> /root/pe-queue/reports/loser_autopsy.md; cd /root/pe-queue && git add reports/loser_autopsy.md && git commit -qm "loser autopsy (629)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q' >/dev/null 2>&1 < /dev/null &
sleep 20; tail -3 /root/pe-sports/team/loser_autopsy.log; echo "629 started in the background"
