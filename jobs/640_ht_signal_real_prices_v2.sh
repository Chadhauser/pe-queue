#!/bin/bash
# 640 (Tue 17 Nov 2026, 07:55). 637 again with the 31 Oct - 11 Nov archive files and the price log as sources (local tape starts 12 Nov). Re-price all 181 half-time goal-signal alerts (25 Oct - 7 Nov) at the REAL back price on the in-play tape at
# the moment of the alert (paper P&L used an assumed price for 159 of them). Per rule, both halves. Writes reports/ht_real_prices.md.
cat > /root/pe-sports/team/ht_reprice.py <<'PY'
#!/usr/bin/env python3
"""637 Re-price every half-time goal-signal alert (goal_alerts, 25 Oct - 7 Nov) at the REAL Betfair back price recorded on the in-play
tape (liq_sample) at the moment of the alert, one tick worse, held to full time, 2% commission, £50 as alerted. Paper P&L used an assumed
price for 159 of 181 alerts. Output per rule: alerts, priced, win rate, real £ and per £100, paper £, older/newer half."""
import sys, re, unicodedata, datetime as dt, psycopg2, pandas as pd, numpy as np
sys.path.insert(0, '/root/pe-queue/runner'); import creds
COMM = 0.02
LADDER = [(2, .01), (3, .02), (4, .05), (6, .1), (10, .2), (20, .5), (30, 1), (50, 2), (100, 5), (1000, 10)]
def down(p):
    for hi, t in LADDER:
        if p - 1e-9 < hi: return round(max(1.01, p - t), 2)
    return round(p - 10, 2)
assert down(1.5) == 1.49 and down(2.0) == 1.99 and down(3.0) == 2.98
STOP = {'fc', 'cf', 'sc', 'afc', 'ac', 'fk', 'sk', 'if', 'bk', 'cd', 'ud', 'sd', 'de', 'the', 'club', 'calcio', 'ssc', 'as', 'us', 'rc', 'vfb', 'vfl', 'tsg', 'sv', '1', 'fsv', 'real'}
def toks(s):
    s = unicodedata.normalize('NFKD', str(s or '')).encode('ascii', 'ignore').decode().lower()
    s = s.replace('utd', 'united').replace('&', ' ')
    for a, b in (('wolves', 'wolverhampton'), ('spurs', 'tottenham'), ('man ', 'manchester '), ('psg', 'paris'), ('inter ', 'internazionale ')): s = (s + ' ').replace(a, b)
    return {w for w in re.findall(r'[a-z0-9]+', s) if w not in STOP and len(w) > 2}
def same(a, b):
    ta, tb = toks(a), toks(b)
    return bool(ta & tb)
assert same('Manchester United', 'Man Utd') and same('Bayern München', 'Bayern Munich') and not same('Arsenal', 'Chelsea')
def line_of(action, score):
    m = re.search(r'(Over|Under)\s+(\d\.5)', action or '')
    if m: return m.group(1), float(m.group(2))
    m = re.search(r'(Over|Under)\s*\[HT_TOTAL\+0\.5\]', action or '')
    if m and score and '-' in score:
        h, a = score.split('-'); return m.group(1), int(h) + int(a) + 0.5
    return None, None
assert line_of('BACK Over 2.5 Goals', '1-0') == ('Over', 2.5) and line_of('BACK Over [HT_TOTAL+0.5] Goals', '3-1') == ('Over', 4.5)
import glob, io, subprocess, os
LIQCOLS = ['ts', 'market_id', 'event_name', 'competition', 'mkt', 'sel', 'minute', 'ltp', 'back_px', 'back_sz', 'lay_px', 'lay_sz', 'back3_sz', 'lay3_sz', 'total_matched']
_DAY = {}
def arch_day(d):
    """liq_sample archive file for one day, over/under rows only: ts, event_name, sel, back_px, mkt."""
    if d in _DAY: return _DAY[d]
    f = f'/root/pe-archive/liq_sample/{d}.csv.zst'; X = None
    if os.path.exists(f):
        raw = subprocess.run(['zstd', '-dc', f], capture_output=True).stdout
        hdr = 'market_id' in raw[:400].decode('utf8', 'ignore').split('\n')[0]
        X = pd.read_csv(io.BytesIO(raw), header=0 if hdr else None, names=None if hdr else LIQCOLS, usecols=['ts', 'event_name', 'mkt', 'sel', 'back_px'], low_memory=False)
        X = X[X.mkt.astype(str).str.startswith('OU')].copy(); X['ts'] = pd.to_datetime(X.ts, utc=True, errors='coerce')
        X['back_px'] = pd.to_numeric(X.back_px, errors='coerce'); X = X.dropna(subset=['ts', 'back_px']); X = X[X.back_px > 1]
    _DAY[d] = X; return X
def tape(mkt, ln, a, b):
    """(ts, event_name, sel, back_px) rows: local liq_sample, else the archive file, else bf_price_log (market name holds the line)."""
    c.execute("SELECT ts, event_name, sel, back_px FROM liq_sample WHERE mkt=%s AND ts BETWEEN %s AND %s AND back_px > 1 ORDER BY ts", (mkt, a, b))
    T = c.fetchall()
    if T: return T
    X = arch_day(a.date().isoformat())
    if X is not None and len(X):
        Y = X[(X.mkt == mkt) & (X.ts >= a) & (X.ts <= b)].sort_values('ts')
        if len(Y): return list(Y[['ts', 'event_name', 'sel', 'back_px']].itertuples(index=False, name=None))
    c.execute("""SELECT captured_at, split_part(market_name, ' - ', 1), selection_name, back_price FROM bf_price_log
                 WHERE captured_at BETWEEN %s AND %s AND market_name ILIKE %s AND back_price > 1 ORDER BY captured_at""", (a, b, f'%Over/Under {ln} Goals%'))
    return c.fetchall()
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor(); c.execute("SET statement_timeout='120s'")
A = pd.read_sql("""SELECT id, sent_at, strategy_id, fixture, score, action, stake_gbp, outcome, pnl_paper, real_price FROM goal_alerts
                   WHERE sent_at > '2026-10-25' AND coalesce(alert_type,'') <> 'BOOT_TEST' AND outcome IS NOT NULL ORDER BY sent_at""", con)
c.execute("SELECT min(ts), max(ts) FROM liq_sample"); t0, t1 = c.fetchone()
rows = []; why = {'no line': 0, 'no tape rows': 0, 'no name match': 0, 'no selection': 0}
for r in A.itertuples():
    side, ln = line_of(r.action, r.score)
    if side is None: why['no line'] += 1; continue
    mkt = f"OU{int(ln * 10):02d}" if ln < 10 else None
    T = tape(mkt, ln, r.sent_at - dt.timedelta(minutes=1), r.sent_at + dt.timedelta(minutes=6))
    if not T: why['no tape rows'] += 1; continue
    home, away = (str(r.fixture).split(' v ', 1) + [''])[:2]
    T = [t for t in T if ' v ' in str(t[1]) and same(home, str(t[1]).split(' v ')[0]) and same(away, str(t[1]).split(' v ')[1])]
    if not T: why['no name match'] += 1; continue
    T = [t for t in T if side.lower() in str(t[2]).lower() and f"{ln}" in str(t[2])]
    if not T: why['no selection'] += 1; continue
    after = [t for t in T if t[0] >= r.sent_at] or T
    px = down(float(after[0][3])); st = float(r.stake_gbp or 50)
    won = str(r.outcome).upper().startswith('WIN')
    pnl = st * (px - 1) * (1 - COMM) if won else -st
    rows.append(dict(rule=r.strategy_id, sent=r.sent_at, px=px, won=won, real=pnl, paper=float(r.pnl_paper or 0), stake=st))
D = pd.DataFrame(rows)
out = [f"# Half-time goal signal at REAL prices — {dt.datetime.utcnow():%F %H:%M} UTC", "",
       f"Alerts 25 Oct - 7 Nov: {len(A)}. Priced from the in-play tape: {len(D)}. Not priced: " + ", ".join(f"{k} {v}" for k, v in why.items()) + f". Sources: local tape from {t0}, archive files 31 Oct - 11 Nov, price log before that.",
       "Real price = first back price on the tape at or after the alert, one tick worse; held to full time; 2% commission; stake as alerted.", ""]
if len(D):
    med = D.sent.median()
    out += ["| rule | priced | won | real £ | per £100 | paper £ (same bets) | older half £ | newer half £ |", "|---|---|---|---|---|---|---|---|"]
    for k, g in sorted(D.groupby('rule'), key=lambda x: -x[1].real.sum()):
        o = g[g.sent < med].real.sum(); n = g[g.sent >= med].real.sum()
        out.append(f"| {k} | {len(g)} | {int(g.won.sum())} | £{g.real.sum():+.2f} | £{g.real.sum() / g.stake.sum() * 100:+.1f} | £{g.paper.sum():+.2f} | £{o:+.2f} | £{n:+.2f} |")
    out += ["", f"ALL: {len(D)} priced, {int(D.won.sum())} won, real £{D.real.sum():+.2f} (£{D.real.sum() / D.stake.sum() * 100:+.1f} per £100) against paper £{D.paper.sum():+.2f} on the same bets."]
open('/root/pe-queue/reports/ht_real_prices.md', 'w').write("\n".join(out) + "\n"); print("\n".join(out))
PY
cd /root/pe-sports/team && python3 -m py_compile ht_reprice.py && timeout 3000 nice -n 10 python3 ht_reprice.py > ht_reprice.log 2>&1 || { echo "STOPPED at re-price: $(tail -3 ht_reprice.log)" > /root/pe-queue/reports/ht_real_prices.md; }
cd /root/pe-queue && git add reports/ht_real_prices.md && git commit -qm "640: HT goal signal at real prices (archive)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "640 done"
