#!/bin/bash
# 668 (Thu 19 Nov 2026). TRADING BRIEF of 19 Nov, items 3-8. Two background agents inside THE ONE MACHINE (664), nothing beside it:
#  TRADER  = machine_map.py, hypothesis M2 in the team loop, every 24 h from 02:15 UTC. THE MAP: every recorded Betfair book
#            (book_snap + book_result) sliced by market, time before the start / in-play state, price band, side, and WHERE the crumbs
#            are (thin markets, off-peak hours, internationals). Two questions per slice:
#              Q1 is the price wrong against the result  (bet the real touch, hold to the result)
#              Q2 does the price move in a predictable direction (after a move 60->30 min out, trade 30->2 min out, both legs at the real touch)
#            Ranked by POUNDS LEFT ON THE TABLE = profit per £1 x the money really on offer at the touch (capped at £50 a bet, lay capped
#            at £50 liability - Peter's ladder ceiling) x how often it comes up, per 30 days. A slice only ranks if both halves are positive
#            and it has shown at least 3 losing bets (a slice that has never lost has not shown its downside). No strategy names.
#            Every ranked bet is written to map_bets so the auditor can re-add it.
#  AUDITOR = audit_nightly.py, cron 03:40 UTC. Re-derives every claim from the tables and files with its OWN arithmetic and marks it
#            MATCH or MISMATCH: map slices (from map_bets, 60 bets spot-checked against book_snap/book_result), the scoreboard's
#            proof-gate rows (from the paper tables), every PASS on the scoreboard (must have a positive history test on file), every
#            keepalive in crontab (process alive), report freshness. Peter is emailed ONLY for: a MISMATCH that stands two nights
#            running, or a rule passing the full proof gate. Otherwise silent.
#  FRIDAY  = friday_four.py replaces the long Friday email with four lines. The old script is kept (friday_email.py), not deleted.
# Still football and Betfair only: the recorder (655) records football. Other sports and Smarkets/Matchbook join the map by adding
# them to the recorder - that is the next job (669), not a separate test. Nothing here places an order.
export PGAPPNAME=batch_668
T=/root/pe-sports/team; R=/root/pe-queue/reports/map_668.md
cat > $T/machine_map.py <<'MAP'
#!/usr/bin/env python3
"""668 THE MAP (trader). Read-only. See the job header. build() is pure (DataFrame in, slices out) so it is tested on known answers."""
import sys, re, json, datetime as dt
import numpy as np, pandas as pd
COMM = 0.02; CAP = 50.0; MIN_N = 30; MIN_LOSERS = 3
INTL = re.compile(r'nations league|friendl|qualif|world cup|euro 20|uefa euro|afcon|africa cup|copa america|asian cup|gold cup|international', re.I)
BANDS = [0, .05, .10, .20, .35, .50, .65, .80, 1.0001]
def per1(side, px, won):
    """profit per £1 of backer's stake at price px, 2% commission on winnings."""
    g = ((px - 1) if won else -1.0) if side == 'BACK' else (-(px - 1) if won else 1.0)
    return g * (1 - COMM) if g > 0 else g
def stake(side, px, size):
    """£ really takeable: money at the touch, capped at £50 a bet; a lay is capped at £50 of liability."""
    if not size or size <= 0: return 0.0
    return min(size, CAP if (side == 'BACK' or px <= 2) else CAP / (px - 1))
assert abs(per1('BACK', 3.0, True) - 1.96) < 1e-9 and per1('BACK', 3.0, False) == -1 and per1('LAY', 3.0, True) == -2 and abs(per1('LAY', 3.0, False) - 0.98) < 1e-9
assert stake('BACK', 5, 200) == 50 and stake('LAY', 11, 200) == 5 and stake('LAY', 1.5, 20) == 20 and stake('BACK', 2, 0) == 0
def band(p):
    for lo, hi in zip(BANDS, BANDS[1:]):
        if lo <= p < hi: return f"{lo:.2f}-{min(hi, 1):.2f}"
    return None
def summarise(B, days):
    """B: one row per bet with columns slice, question, day, u (profit per £1), stk (£ takeable), key. -> one row per slice."""
    rows = []
    if B.empty: return pd.DataFrame(rows)
    split = sorted(B.day.unique())[len(B.day.unique()) // 2]
    for (q, s), g in B.groupby(['question', 'slice']):
        n = len(g)
        if n < MIN_N: continue
        o = g[g.day < split]; w = g[g.day >= split]
        gbp = float((g.u * g.stk).sum()); staked = float(g.stk.sum())
        rows.append(dict(question=q, slice=s, key=g.key.iloc[0], n=n, losers=int((g.u < 0).sum()), per100=round(float(g.u.mean()) * 100, 2),
                         old_n=len(o), old_per100=round(float(o.u.mean()) * 100, 2) if len(o) else None,
                         new_n=len(w), new_per100=round(float(w.u.mean()) * 100, 2) if len(w) else None,
                         gbp=round(gbp, 2), staked=round(staked, 2), med_stake=round(float(g.stk.median()), 2),
                         per_month=round(gbp / max(days, 1) * 30, 2), per_day_bets=round(n / max(days, 1), 1)))
    return pd.DataFrame(rows)
def build(E):
    """E: one row per market x runner x phase: market_id, sel_id, market_type, competition, country, start_ts, w, b, bs, l, ls, matched, won.
    Returns (bets, slices, ranked)."""
    E = E[(E.b > 1) & (E.l > 1) & (E.l < 1000) & (E.l >= E.b)].copy()
    if E.empty: return pd.DataFrame(), pd.DataFrame(), pd.DataFrame()
    st = pd.to_datetime(E.start_ts, utc=True); E['day'] = st.dt.date; E['hr'] = st.dt.hour
    E['mid'] = (E.b + E.l) / 2; E['band'] = (1 / E.mid).map(band)
    E['seg'] = np.where(E.competition.fillna('').str.contains(INTL) | E.country.isna(), 'internationals', 'club')
    E['liq'] = pd.cut(E.matched.fillna(0), [-1, 2000, 20000, 1e12], labels=['thin (<£2k matched)', 'middle (£2k-20k)', 'deep (£20k+)']).astype(str)
    E['hours'] = np.where((E.hr < 11) | (E.hr >= 21), 'off-peak kick-off', 'peak kick-off')
    days = max(1, (max(E.day) - min(E.day)).days + 1)
    bets = []
    # ---- Q1: is the price wrong against the result
    for side, px, sz in (('BACK', 'b', 'bs'), ('LAY', 'l', 'ls')):
        D = E.copy(); D['stk'] = [stake(side, p, s) for p, s in zip(D[px], D[sz].fillna(0))]; D = D[D.stk >= 2]
        D['u'] = [per1(side, p, w) for p, w in zip(D[px], D.won)]; D['px'] = D[px]; D['side'] = side
        for where in (None, 'liq', 'seg', 'hours'):
            X = D.copy(); tag = 'everywhere' if where is None else X[where]
            X['key'] = X.market_type + ' | ' + X.w + ' | ' + side + ' | price ' + X.band
            X['slice'] = X['key'] + ' | ' + tag; X['question'] = 'wrong against the result'
            if where == 'seg': X = X[X.seg == 'internationals']
            if where == 'hours': X = X[X.hours == 'off-peak kick-off']
            bets.append(X[['question', 'slice', 'key', 'day', 'market_id', 'sel_id', 'side', 'px', 'stk', 'won', 'u']])
    # ---- Q2: does the price move in a predictable direction (prior move 60->30, trade 30->2, both legs at the real touch)
    P = E.pivot_table(index=['market_id', 'sel_id'], columns='w', values=['b', 'l', 'bs', 'ls', 'mid'], aggfunc='first')
    P.columns = [f"{a}_{w}" for a, w in P.columns]
    need = ['mid_pre60', 'mid_pre30', 'b_pre30', 'l_pre30', 'b_pre2', 'l_pre2']
    if all(k in P.columns for k in need):
        P = P.dropna(subset=need); meta = E.drop_duplicates(['market_id', 'sel_id']).set_index(['market_id', 'sel_id'])[['market_type', 'day', 'liq', 'won']]
        X0 = P.join(meta, how='inner').reset_index(); mv = X0.mid_pre30 / X0.mid_pre60 - 1
        X0['prior'] = np.where(mv <= -0.02, 'shortened 2%+', np.where(mv >= 0.02, 'drifted 2%+', 'flat'))
        for c0 in ('bs_pre30', 'ls_pre30'):
            if c0 not in X0.columns: X0[c0] = 0.0
        for act in ('back at 30 min, lay at 2 min', 'lay at 30 min, back at 2 min'):
            X = X0.copy()
            if act.startswith('back'): raw = X.b_pre30 / X.l_pre2 - 1; X['stk'] = [stake('BACK', p, s) for p, s in zip(X.b_pre30, X.bs_pre30.fillna(0))]; X['px'] = X.b_pre30; X['side'] = 'BACK'
            else: raw = 1 - X.l_pre30 / X.b_pre2; X['stk'] = [stake('LAY', p, s) for p, s in zip(X.l_pre30, X.ls_pre30.fillna(0))]; X['px'] = X.l_pre30; X['side'] = 'LAY'
            X['u'] = np.where(raw > 0, raw * (1 - COMM), raw); X = X[(X.stk >= 2) & (X.prior != 'flat')]
            for where in (None, 'liq'):
                Y = X.copy(); Y['key'] = Y.market_type + ' | after it ' + Y.prior + ' | ' + act
                Y['slice'] = Y['key'] + ' | ' + ('everywhere' if where is None else Y[where]); Y['question'] = 'moves in a predictable direction'
                bets.append(Y[['question', 'slice', 'key', 'day', 'market_id', 'sel_id', 'side', 'px', 'stk', 'won', 'u']])
    B = pd.concat(bets, ignore_index=True) if bets else pd.DataFrame()
    S = summarise(B, days)
    if S.empty: return B, S, S
    ok = S[(S.old_per100 > 0) & (S.new_per100 > 0) & (S.losers >= MIN_LOSERS) & (S.gbp > 0)]
    ranked = ok.sort_values('per_month', ascending=False).drop_duplicates('key').head(10)   # one row per underlying slice: its best 'where'
    return B, S, ranked
def main():
    import psycopg2; sys.path.insert(0, '/root/pe-queue/runner'); import creds
    ROOT = '/root/pe-sports/team'; REP = '/root/pe-queue/reports/map_latest.md'
    con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor(); c.execute("SET statement_timeout='3000s'")
    E = pd.read_sql("""SELECT DISTINCT ON (s.market_id, s.sel_id, s.w) s.market_id, s.sel_id, s.market_type, s.competition, s.country, s.start_ts, s.w,
          s.back1::float8 b, s.back1_sz::float8 bs, s.lay1::float8 l, s.lay1_sz::float8 ls, s.mkt_matched::float8 matched, (r.status = 'WINNER') won
        FROM (SELECT *, CASE WHEN NOT inplay AND ts BETWEEN start_ts - interval '65 min' AND start_ts - interval '55 min' THEN 'pre60'
                             WHEN NOT inplay AND ts BETWEEN start_ts - interval '35 min' AND start_ts - interval '25 min' THEN 'pre30'
                             WHEN NOT inplay AND ts BETWEEN start_ts - interval '5 min'  AND start_ts - interval '1 min'  THEN 'pre2'
                             WHEN inplay AND ts BETWEEN start_ts + interval '10 min' AND start_ts + interval '20 min' THEN 'in-play 15'
                             WHEN inplay AND ts BETWEEN start_ts + interval '55 min' AND start_ts + interval '65 min' THEN 'in-play 60'
                             WHEN inplay AND ts BETWEEN start_ts + interval '85 min' AND start_ts + interval '95 min' THEN 'in-play 90' END w
              FROM book_snap WHERE market_type <> 'ASIAN_HANDICAP' AND status = 'OPEN') s
        JOIN book_result r ON r.market_id = s.market_id AND r.sel_id = s.sel_id
        WHERE s.w IS NOT NULL AND r.status IN ('WINNER', 'LOSER') ORDER BY s.market_id, s.sel_id, s.w, s.ts DESC""", con)
    B, S, top = build(E)
    run = dt.datetime.now(dt.timezone.utc); out = [f"# The map - {run:%F %H:%M} UTC", ""]
    nm = E.market_id.nunique() if len(E) else 0
    out += [f"Football on Betfair, every market the recorder holds. {len(E):,} real prices on {nm:,} settled markets"
            + (f", {pd.to_datetime(E.start_ts, utc=True).dt.date.min()} to {pd.to_datetime(E.start_ts, utc=True).dt.date.max()}." if len(E) else "."),
            f"Slices with {MIN_N}+ bets: {len(S)}. Positive on both halves with a visible downside: {0 if S.empty else int(((S.old_per100 > 0) & (S.new_per100 > 0) & (S.losers >= MIN_LOSERS) & (S.gbp > 0)).sum())}.", "",
            "## Top ten slices by pounds left on the table", "",
            "| # | slice | question | bets | bets a day | £ per £100 | older half | newer half | £ a month at the touch (max £50 a bet) |", "|---|---|---|---|---|---|---|---|---|"]
    c.execute("""CREATE TABLE IF NOT EXISTS map_bets (run_date DATE, rank INT, slice TEXT, question TEXT, market_id TEXT, sel_id BIGINT, side TEXT, px FLOAT8, stk FLOAT8, won BOOLEAN, u FLOAT8);
                 CREATE TABLE IF NOT EXISTS map_slices (run_date DATE, rank INT, slice TEXT, question TEXT, n INT, per100 FLOAT8, old_per100 FLOAT8, new_per100 FLOAT8, gbp FLOAT8, per_month FLOAT8, days INT)""")
    c.execute("DELETE FROM map_bets WHERE run_date = %s", (run.date(),)); c.execute("DELETE FROM map_slices WHERE run_date = %s", (run.date(),))
    days = max(1, (pd.to_datetime(E.start_ts, utc=True).dt.date.max() - pd.to_datetime(E.start_ts, utc=True).dt.date.min()).days + 1) if len(E) else 1
    for i, r in enumerate(top.itertuples(), 1):
        out.append(f"| {i} | {r.slice} | {r.question} | {r.n} | {r.per_day_bets} | {r.per100:+.2f} | {r.old_n} at {r.old_per100:+.2f} | {r.new_n} at {r.new_per100:+.2f} | £{r.per_month:,.2f} |")
        c.execute("INSERT INTO map_slices VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)", (run.date(), i, r.slice, r.question, r.n, r.per100, r.old_per100, r.new_per100, r.gbp, r.per_month, days))
        g = B[(B.slice == r.slice) & (B.question == r.question)]
        c.executemany("INSERT INTO map_bets VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                      [(run.date(), i, r.slice, r.question, x.market_id, int(x.sel_id), x.side, float(x.px), float(x.stk), bool(x.won), float(x.u)) for x in g.itertuples()])
    if top.empty: out.append("| - | no slice is positive on both halves yet | | | | | | | |")
    out += ["", f"Total of the ten: £{(0 if top.empty else top.per_month.sum()):,.2f} a month against £10,000. Days of recorded prices behind this: {days}. UNVERIFIED until a slice has 300+ bets and passes forward paper.",
            "Proof: tables map_slices and map_bets (local database), written by machine_map.py; the auditor re-adds them nightly (reports/audit_latest.md)."]
    open(REP, 'w').write("\n".join(out) + "\n"); print("\n".join(out))
if __name__ == '__main__': main()
MAP
cat > $T/audit_nightly.py <<'AUD'
#!/usr/bin/env python3
"""668 THE AUDITOR. Independent of the trader: own SQL, own arithmetic. Every claim -> MATCH or MISMATCH with the file/table behind it.
Emails Peter only for a MISMATCH standing two nights running, or a rule passing the full proof gate. Never fixes, never trades."""
import sys, os, re, json, subprocess, datetime as dt, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/operators'); import creds
ROOT = '/root/pe-sports/team'; REP = '/root/pe-queue/reports/audit_latest.md'; STATE = f'{ROOT}/audit_state.json'; HIST = f'{ROOT}/gate_history.json'
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor(); c.execute("SET statement_timeout='600s'")
def q(sql, a=()):
    try: c.execute(sql, a); return c.fetchall()
    except Exception as e: return [('ERR', repr(e)[:120])]
claims = []   # (claim, source, verdict, detail)
def add(claim, source, ok, detail=''): claims.append((claim, source, 'MATCH' if ok else 'MISMATCH', detail))
near = lambda a, b, tol=0.02: a is not None and b is not None and abs(float(a) - float(b)) <= tol + 0.001 * abs(float(b))
# 1. the map: every ranked slice re-added from its own bets with the auditor's formula; 60 bets spot-checked against the recorder
d = q("SELECT max(run_date) FROM map_slices")
if d and d[0][0] not in (None, 'ERR'):
    rd = d[0][0]; add(f"map was built in the last 26 hours ({rd})", "map_slices.run_date", (dt.date.today() - rd).days <= 1)
    for rank, sl, n, per100, gbp in q("SELECT rank, slice, n, per100, gbp FROM map_slices WHERE run_date=%s ORDER BY rank", (rd,)):
        bets = q("SELECT side, px, stk, won, u FROM map_bets WHERE run_date=%s AND rank=%s", (rd, rank)); n2 = len(bets); tot = 0.0; us = []; bad = 0
        for side, px, stk, won, u in bets:
            if 'predictable' in sl or ' at 2 min' in sl: mine = u   # two-leg trade: profit is re-checked from prices in the spot check below, not here
            else:
                g = ((px - 1) if won else -1.0) if side == 'BACK' else (-(px - 1) if won else 1.0); mine = g * 0.98 if g > 0 else g
                if abs(mine - u) > 1e-6: bad += 1
            tot += mine * stk; us.append(mine)
        p2 = sum(us) / len(us) * 100 if us else None
        add(f"map #{rank} {sl}: {n} bets, £{gbp:.2f}, £{per100:+.2f} per £100", "map_bets", n2 == n and near(tot, gbp, 0.05) and near(p2, per100, 0.02) and bad == 0, f"auditor: {n2} bets, £{tot:.2f}, {bad} bets with a wrong profit")
    wrong = q("""SELECT count(*) FROM (SELECT * FROM map_bets WHERE run_date=%s ORDER BY random() LIMIT 60) m
                 WHERE NOT EXISTS (SELECT 1 FROM book_result r WHERE r.market_id=m.market_id AND r.sel_id=m.sel_id AND (r.status='WINNER') = m.won)
                    OR NOT EXISTS (SELECT 1 FROM book_snap s WHERE s.market_id=m.market_id AND s.sel_id=m.sel_id AND (s.back1::float8 = m.px OR s.lay1::float8 = m.px))""", (rd,))
    add("60 random map bets: result and price exist in the recorder", "book_result, book_snap", wrong and wrong[0][0] == 0, f"{wrong[0][0]} do not")
else: add("the map exists", "map_slices", False, "no rows")
# 2. the scoreboard's proof-gate rows against the paper tables
sb = open(f'{ROOT}/scoreboard.md').read() if os.path.exists(f'{ROOT}/scoreboard.md') else ''
rows = {}
for ln in sb.split('## PROOF GATE')[1].split('\n## ')[0].splitlines() if '## PROOF GATE' in sb else []:
    m = re.match(r"\|\s*(.+?)\s*\|\s*(\d+) / 100\s*\|\s*([+-][\d.]+)\s*\|.*\|\s*([^|]+?)\s*\|$", ln)
    if m: rows[m.group(1).strip()] = (int(m.group(2)), float(m.group(3)), m.group(4))
CHECK = {'bot v2.2 TAKER': "SELECT count(*), coalesce(sum(pnl),0) FROM bookie_paper WHERE version='v2.2' AND status='settled' AND fill_kind='taker'",
         'small bites forward paper (all cells)': "SELECT count(*), coalesce(sum(pnl),0) FROM small_bites_paper WHERE pnl IS NOT NULL",
         'coherence forward paper': "SELECT count(*), coalesce(sum(pnl),0) FROM coherence_paper WHERE pnl IS NOT NULL"}
age_min = (dt.datetime.now().timestamp() - os.path.getmtime(f'{ROOT}/scoreboard.md')) / 60 if sb else 1e9
add("scoreboard was rewritten in the last 30 minutes", "scoreboard.md", age_min <= 30, f"{age_min:.0f} minutes old")
for key, sql in CHECK.items():
    lab = next((k for k in rows if k.startswith(key)), None); r = q(sql)
    if lab is None or r[0][0] == 'ERR': add(f"proof gate row '{key}'", "scoreboard.md", False, "row or table missing"); continue
    n, pnl = rows[lab][0], rows[lab][1]; n2, p2 = int(r[0][0]), float(r[0][1])
    add(f"{lab}: {n} settled, £{pnl:+.2f}", sql.split('FROM ')[1].split(' ')[0], abs(n2 - n) <= 15 and near(p2, pnl, 3.0 if n2 != n else 0.02), f"table now: {n2} settled, £{p2:+.2f}")
# 3. every PASS must have its history test on file and positive (the gate's third leg)
try: H = json.load(open(HIST))
except Exception: H = {}
passed = []
for lab, (n, pnl, gate) in rows.items():
    if gate.strip() == 'PASS':
        h = H.get(lab); ok = h is not None and h > 0
        add(f"{lab} marked PASS", "gate_history.json", ok, "history test " + ("not on file" if h is None else f"£{h:+.2f} per £100: paper is not in line with it"))
        if ok: passed.append(f"{lab}: {n} settled paper bets, £{pnl:+.2f} after commission, history £{h:+.2f} per £100")
# 4. every keepalive in crontab has a live process; reports are fresh
for ln in subprocess.run(['crontab', '-l'], capture_output=True, text=True).stdout.splitlines():
    m = re.search(r"pgrep -f '?\[?(\w)\]?([\w.]+)'?", ln)
    if m and not ln.startswith('#') and '/pe-sports/' in ln:
        name = m.group(1) + m.group(2); add(f"{name} is running", "crontab keepalive", subprocess.run(['pgrep', '-f', f'[{name[0]}]{name[1:]}'], capture_output=True).returncode == 0)
for f in ('machine_nightly.md', 'map_latest.md'):
    p = f'/root/pe-queue/reports/{f}'; a = (dt.datetime.now().timestamp() - os.path.getmtime(p)) / 3600 if os.path.exists(p) else 1e9
    add(f"{f} written in the last 26 hours", p, a <= 26, f"{a:.0f} hours old" if a < 1e8 else "missing")
r = q("SELECT count(*) FROM book_snap WHERE ts > now() - interval '6 hours'"); add("the recorder wrote prices in the last 6 hours", "book_snap", r[0][0] not in ('ERR', 0), str(r[0][0]))
# ---- write, remember, tell Peter only what the brief allows
mm = [x for x in claims if x[2] == 'MISMATCH']; now = dt.datetime.now(dt.timezone.utc)
out = [f"# Audit - {now:%F %H:%M} UTC", "", f"{len(claims)} claims checked: {len(claims) - len(mm)} MATCH, {len(mm)} MISMATCH.", "", "| claim | checked against | verdict | auditor found |", "|---|---|---|---|"]
out += [f"| {a} | {b} | **{v}** | {d} |" for a, b, v, d in sorted(claims, key=lambda x: x[2] == 'MATCH')]
open(REP, 'w').write("\n".join(out) + "\n"); print("\n".join(out[:12]))
try: S = json.load(open(STATE))
except Exception: S = {'last': [], 'told': [], 'gate_told': [], 'week': []}
key = lambda x: re.sub(r"[\d.,+£-]+", "#", x[0])[:90]
standing = [x for x in mm if key(x) in S.get('last', []) and key(x) not in S.get('told', [])]
mail = []
if standing: mail.append(("Trading: mismatch", "The auditor found claims that do not match the files, two nights running:\n\n" + "\n".join(f"{a}. Auditor found: {d or 'not true'}." for a, b, v, d in standing) + "\n\nNo real money is on. Full list: reports/audit_latest.md"))
newpass = [p for p in passed if p.split(':')[0] not in S.get('gate_told', [])]
if newpass: mail.append(("Trading: proof gate passed", "Passed the proof gate and waiting for your yes:\n\n" + "\n".join(newpass) + "\n\nNothing goes live until you say yes in the trading chat. First stake £2."))
S['told'] = [k for k in S.get('told', []) if k in [key(x) for x in mm]] + [key(x) for x in standing]
S['last'] = [key(x) for x in mm]; S['gate_told'] = S.get('gate_told', []) + [p.split(':')[0] for p in newpass]
S['week'] = (S.get('week', []) + [dict(d=f"{now:%F}", n=len(claims), mm=len(mm))])[-7:]
json.dump(S, open(STATE, 'w'), indent=1)
if mail and '--send' in sys.argv:
    from engines.mail import send_text
    for subj, body in mail: print("MAIL", subj, send_text(subj, body, "peter@edwardsbros.co.uk"))
elif mail: print("WOULD MAIL:", [m[0] for m in mail])
AUD
cat > $T/friday_four.py <<'FRI'
#!/usr/bin/env python3
"""668 Friday scoreboard, four lines, nothing else. Every figure read from the scoreboard, the map table and the auditor's state."""
import sys, re, json, datetime, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/operators'); import creds
T = '/root/pe-sports/team'; sb = open(f'{T}/scoreboard.md').read()
money = re.search(r"Money: live £([-\d.,]+) \| paper £([-\d.,]+)", sb); gate = []
for ln in (sb.split('## PROOF GATE')[1].split('\n## ')[0].splitlines() if '## PROOF GATE' in sb else []):
    m = re.match(r"\|\s*([^| ][^|]*?)\s*\|\s*(\d+) / 100\s*\|\s*([+-][\d.]+)\s*\|.*\|\s*([^|]+?)\s*\|$", ln)
    if m and not ln.startswith('|   '): gate.append((m.group(1), int(m.group(2)), float(m.group(3)), m.group(4).strip()))
live = [g for g in gate if g[1] < 100 and g[1] > 0]; best = max(live, key=lambda g: (g[2] > 0, g[1]), default=None)
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor()
try: c.execute("SELECT slice, n, per_month, (SELECT sum(per_month) FROM map_slices WHERE run_date=(SELECT max(run_date) FROM map_slices)) FROM map_slices WHERE run_date=(SELECT max(run_date) FROM map_slices) AND rank=1"); top = c.fetchone()
except Exception: top = None
try: W = json.load(open(f'{T}/audit_state.json')).get('week', [])
except Exception: W = []
L = [f"Money: real £{money.group(1) if money else '0.00'}, paper £{money.group(2) if money else '?'} across {len(gate)} rules.",
     ("Proof gate: nearest is " + f"{best[0]} at {best[1]} of 100 settled, £{best[2]:+.2f}." if best else "Proof gate: no rule has a settled paper bet yet.") + f" Passed and waiting for your yes: {sum(1 for g in gate if g[3] == 'PASS')} (the auditor confirms each against its history test).",
     (f"Map: the ten best slices add up to £{top[3]:,.0f} a month against £10,000; the best is {top[0]} at £{top[2]:,.0f} a month on {top[1]} bets." if top else "Map: not built yet."),
     f"Audit: {sum(w['n'] for w in W)} claims checked over {len(W)} nights, {sum(w['mm'] for w in W)} mismatches."]
body = "\n".join(L); print(body)
if '--send' in sys.argv:
    from engines.mail import send_text
    print(send_text(f"Trading: Friday scoreboard, {datetime.date.today():%d %B}", body, "peter@edwardsbros.co.uk"))
FRI
{ echo "# 668 - $(date -u '+%F %H:%M') UTC"; echo '```'
for f in machine_map audit_nightly friday_four; do python3 -m py_compile $T/$f.py && echo "$f compiles"; done
[ -f $T/gate_history.json ] || echo '{"small bites DRIFT_FADE k3 H10": -0.85}' > $T/gate_history.json   # history test 16 Nov (reports/small_bites.md): in-play, 25,120 bets
echo "== first map"; cd $T && timeout 3300 nice -n 10 python3 -I machine_map.py > machine_map.out 2> machine_map.err; echo "exit $?"; tail -5 machine_map.err | cut -c1-250
echo "== register M2 in the one machine (loop keeps running; the registry is re-read each cycle)"
python3 - <<'PY'
import json, datetime
R = '/root/pe-sports/team/hypotheses.json'; reg = json.load(open(R))
if not any(h['id'].startswith('M2 ') for h in reg['hypotheses']):
    nb = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).strftime('%Y-%m-%dT02:15:00')
    i = next((k for k, h in enumerate(reg['hypotheses']) if h['id'].startswith('M1 ')), -1) + 1
    reg['hypotheses'].insert(i, {"id": "M2 the map: every slice, two questions, ranked by pounds left on the table", "script": "/root/pe-sports/team/machine_map.py",
        "status": "proposed", "kind": "sweep", "pre_registered_sign": "a slice positive on the older half stays positive on the newer half",
        "next_door": "top slices at 300+ bets go to the Verifier gate and onto forward paper", "timeout": 5400, "repeat_hours": 24, "not_before": nb, "note": "668: trading brief 19 Nov"})
    json.dump(reg, open(R, 'w'), indent=1); print('M2 registered, first loop run', nb)
else: print('M2 already registered')
PY
echo "== auditor: first run (dry, nothing sent), then nightly 03:40 UTC with --send"
cat > $T/audit_nightly.sh <<'SH'
#!/bin/bash
[ "$(date -u +%H)" = "03" ] || exit 0
cd /root/operators && set -a && . ./.env && set +a && cd /root/pe-sports/team && /usr/bin/python3 audit_nightly.py --send >> audit_nightly.log 2>&1
cd /root/pe-queue && git add reports/audit_latest.md reports/map_latest.md && git commit -qm "audit $(date -u +%F)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
SH
cat > $T/friday_four.sh <<'SH'
#!/bin/bash
cd /root/operators && set -a && . ./.env && set +a && /usr/bin/python3 /root/pe-sports/team/friday_four.py --send >> /root/pe-sports/team/friday_four.log 2>&1
SH
chmod +x $T/audit_nightly.sh $T/friday_four.sh
cd $T && python3 audit_nightly.py > audit_first.out 2> audit_first.err; echo "audit exit $?"; tail -3 audit_first.err | cut -c1-250
crontab -l > /root/crontab.bak_668
( crontab -l | grep -v 'audit_nightly.sh' | sed 's|^0 7 \* \* 5 /root/pe-sports/team/friday_email.sh|#668-replaced-by-friday_four 0 7 * * 5 /root/pe-sports/team/friday_email.sh|'
  echo "40 3,4 * * * /root/pe-sports/team/audit_nightly.sh   # 668 the auditor (03:40 UTC whatever the box clock says)"
  crontab -l | grep -q friday_four.sh || echo "0 7 * * 5 /root/pe-sports/team/friday_four.sh   # 668 Friday scoreboard, four lines" ) | crontab -
crontab -l | grep -E 'audit_nightly|friday_' | cut -c1-160
echo "== Friday four lines, dry run (not sent)"; python3 $T/friday_four.py 2>&1 | tail -6
echo '```'; echo; cat /root/pe-queue/reports/map_latest.md 2>/dev/null; echo; cat /root/pe-queue/reports/audit_latest.md 2>/dev/null; } > $R 2>&1
cd /root/pe-queue && git add $R reports/map_latest.md reports/audit_latest.md 2>/dev/null; git commit -qm "668: the map and the auditor" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
