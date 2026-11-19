#!/bin/bash
# 682 (Thu 19 Nov 2026, Peter 16:09: "add family 2, I want it all ready"). The full grid gains its second family, IN AND OUT: enter at
# one time point, exit at a later one (all 28 pairs of the eight points), back-then-lay and lay-then-back, by price band and price move.
# Same history, same rules (300+ bets, profit in both halves). The grid is stopped, the new version installed (known-answer test passed
# before this was pushed), the finished-list cleared so every market type gets both families, and the grid restarted in the background.
# The mechanic (installed by Peter at 16:07) watches it. Nothing outside the grid's own tables is touched.
T=/root/pe-sports/team; R=/root/pe-queue/reports/grid_682.md
{ echo "# 682 - $(date -u '+%F %H:%M') UTC"; echo '```'
pkill -f '[r]un_grid_history.sh'; pkill -f '[g]rid_history.py'; sleep 3
cp $T/grid_history.py $T/grid_history.py.bak_682
cat > $T/grid_history.py <<'GRID'
#!/usr/bin/env python3
"""679 THE FULL GRID, stage 1: the Betfair history files (every sport held, every market type), mechanically, no choosing.
Per runner: the last traded price at 24 h, 6 h, 1 h, 10 min and 2 min before the start, then in-play at the middle of each third.
Each price x 10 price bands x back and lay x price rising / falling / flat since the previous point. Held to the result, 2% commission.
Back = £1 staked. Lay = £1 at risk. The history files carry last traded prices only: no depth, so no thin/medium/deep split here and
every figure is at the traded price (the recorded-prices stage uses the real price on offer). ASIAN_HANDICAP is left out: the files
do not carry the handicap line, so its runners cannot be settled. Resumable: one (sport, market type) at a time, skipped once done."""
import sys, json, time, datetime as dt
import numpy as np, pandas as pd
COMM = 0.02
PRE = [('24 hours before', 86400), ('6 hours before', 21600), ('1 hour before', 3600), ('10 minutes before', 600), ('2 minutes before', 120)]
INP = [('in-play, first third', 1 / 6), ('in-play, middle third', 1 / 2), ('in-play, last third', 5 / 6)]
ORDER = [p for p, _ in PRE] + [p for p, _ in INP]
def points(df):
    """df: market_id, sel, market_time, ts, ltp, inplay, won (one row per price print). -> one row per runner x time point."""
    df = df[(df.ltp > 1) & (df.ltp <= 1000)].sort_values(['market_id', 'sel', 'ts'])
    if df.empty: return pd.DataFrame()
    secs = (df.market_time - df.ts).dt.total_seconds(); out = []
    pre = df[~df.inplay].assign(secs=secs[~df.inplay])
    for name, c in PRE:
        x = pre[(pre.secs >= c) & (pre.secs <= 4 * c)].groupby(['market_id', 'sel'], sort=False).tail(1)
        out.append(x[['market_id', 'sel', 'market_time', 'ltp', 'won']].assign(point=name))
    ip = df[df.inplay]
    if not ip.empty:
        g = ip.groupby('market_id').ts; t0 = g.transform('min'); t1 = g.transform('max'); span = (t1 - t0).dt.total_seconds()
        ip = ip.assign(frac=np.where(span > 0, (ip.ts - t0).dt.total_seconds() / span.replace(0, np.nan), np.nan)); ip = ip[span >= 300]
        for name, f in INP:
            x = ip[ip.frac <= f].groupby(['market_id', 'sel'], sort=False).tail(1)
            out.append(x[['market_id', 'sel', 'market_time', 'ltp', 'won']].assign(point=name))
    P = pd.concat(out, ignore_index=True)
    if P.empty: return P
    P['k'] = P.point.map({p: i for i, p in enumerate(ORDER)}); P = P.sort_values(['market_id', 'sel', 'k'])
    prev = P.groupby(['market_id', 'sel']).ltp.shift(1); r = P.ltp / prev - 1
    P['direction'] = np.where(prev.isna(), 'no earlier price', np.where(r >= 0.02, 'price rising', np.where(r <= -0.02, 'price falling', 'price flat')))
    P['band'] = np.minimum((1 / P.ltp * 10).astype(int), 9)
    P['back'] = np.where(P.won, (P.ltp - 1) * (1 - COMM), -1.0)
    P['lay'] = np.where(P.won, -1.0, (1 - COMM) / (P.ltp - 1))
    P['month'] = P.market_time.dt.strftime('%Y-%m')
    return P
def trades(P):
    """Family 2, in and out: enter at one time point, exit at a later one, same runner, both legs at the traded price. The exit stake is
    sized so the result of the event does not matter. 'back' column = back first then lay; 'lay' column = lay first then back.
    Per £1 of the first leg's stake, 2% commission on a profit."""
    if P.empty: return P
    idx = ['market_id', 'sel']; W = P.pivot(index=idx, columns='point', values='ltp'); D = P.pivot(index=idx, columns='point', values='direction')
    mon = P.groupby(idx).month.first(); out = []
    for i, a in enumerate(ORDER):
        if a not in W.columns: continue
        for b in ORDER[i + 1:]:
            if b not in W.columns: continue
            x = W[[a, b]].dropna()
            if x.empty: continue
            r = x[a] / x[b]; btl = r - 1; ltb = 1 - r
            out.append(pd.DataFrame({'point': f"in {a}, out {b}", 'band': np.minimum((1 / x[a] * 10).astype(int), 9).values, 'direction': D.loc[x.index, a].values,
                                     'month': mon.loc[x.index].values, 'back': np.where(btl > 0, btl * (1 - COMM), btl), 'lay': np.where(ltb > 0, ltb * (1 - COMM), ltb)}))
    return pd.concat(out, ignore_index=True) if out else pd.DataFrame()
def aggregate(P):
    rows = []
    for F, names in ((P, {'back': 'back', 'lay': 'lay'}), (trades(P), {'back': 'back then lay', 'lay': 'lay then back'})):
        if F is None or F.empty: continue
        for side, label in names.items():
            a = F.groupby(['point', 'band', 'direction', 'month'])[side].agg(['count', 'sum']).reset_index(); a['side'] = label; rows.append(a)
    return pd.concat(rows, ignore_index=True) if rows else pd.DataFrame()
def summarise(A):
    """A: sport, market_type, point, band, side, direction, month, n, s -> one row per slice with halves split at half the bets, by month."""
    out = []
    for key, g in A.groupby(['sport', 'market_type', 'point', 'band', 'side', 'direction']):
        g = g.sort_values('month'); n = int(g.n.sum())
        if n == 0: continue
        cum = g.n.cumsum(); first = cum <= n / 2
        if not first.any(): first.iloc[0] = True
        if first.all() and len(g) > 1: first.iloc[-1] = False
        n1 = int(g.n[first].sum()); n2 = n - n1; s1 = float(g.s[first].sum()); s2 = float(g.s[~first].sum())
        out.append(dict(zip(['sport', 'market_type', 'point', 'band', 'side', 'direction'], key), n=n, per100=(s1 + s2) / n * 100,
                        h1=(s1 / n1 * 100 if n1 else None), h2=(s2 / n2 * 100 if n2 else None), months=int((g.n > 0).sum()),
                        per_month_at_10=(s1 + s2) * 10 / max(int((g.n > 0).sum()), 1)))
    return pd.DataFrame(out)
def report(con, path):
    A = pd.read_sql("SELECT sport, market_type, point, band, side, direction, month, n, s FROM grid_agg WHERE source='history'", con)
    c = con.cursor(); c.execute("SELECT count(*) FROM grid_done WHERE source='history'"); done = c.fetchone()[0]
    c.execute("SELECT count(*) FROM (SELECT DISTINCT sport, market_type FROM bf_hist_result WHERE market_type <> 'ASIAN_HANDICAP') x"); total = c.fetchone()[0]
    S = summarise(A) if len(A) else pd.DataFrame(columns=['n', 'h1', 'h2'])
    big = S[S.n >= 300] if len(S) else S; win = big[(big.h1 > 0) & (big.h2 > 0)] if len(big) else big
    c.execute("INSERT INTO grid_count VALUES (now(), 'history', %s, %s, %s, %s, %s)", (len(S), len(big), len(win), done, total))
    band = lambda b: f"{b * 10}-{b * 10 + 10}% chance"
    L = [f"# The full grid, stage 1: Betfair history - {dt.datetime.now(dt.timezone.utc):%F %H:%M} UTC", "",
         f"Market types finished: {done} of {total}. Slices tested so far: {len(S):,}. With 300 or more bets: {len(big):,}. Profitable in both halves: {len(win):,}.",
         "At the last traded price, 2% commission. Two families: hold to the result (back is per £100 staked, lay per £100 at risk) and in-and-out (enter at one time, exit at a later one, per £100 of the first stake). £ a month is at £10 a bet. UNVERIFIED until the same slice holds at real offered prices.", "",
         "## Top 20 survivors by £ a month", "", "| # | sport | market | when | price band | side | price move | bets | £ per £100 | first half | second half | £ a month at £10 |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for i, r in enumerate((win.sort_values('per_month_at_10', ascending=False).head(20) if len(win) else win).itertuples(), 1):
        L.append(f"| {i} | {r.sport} | {r.market_type} | {r.point} | {band(r.band)} | {r.side} | {r.direction} | {r.n:,} | {r.per100:+.2f} | {r.h1:+.2f} | {r.h2:+.2f} | £{r.per_month_at_10:,.0f} |")
    if not len(win): L.append("| - | none yet | | | | | | | | | | |")
    open(path, 'w').write("\n".join(L) + "\n"); con.commit()
def main():
    import psycopg2; sys.path.insert(0, '/root/pe-queue/runner'); import creds
    REP = '/root/pe-queue/reports/grid_history.md'
    con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor()
    c.execute("""CREATE TABLE IF NOT EXISTS grid_agg (source TEXT, sport TEXT, market_type TEXT, point TEXT, band INT, side TEXT, direction TEXT, month TEXT, n BIGINT, s FLOAT8);
                 CREATE INDEX IF NOT EXISTS grid_agg_k ON grid_agg (source, sport, market_type);
                 CREATE TABLE IF NOT EXISTS grid_done (source TEXT, sport TEXT, market_type TEXT, finished TIMESTAMPTZ, markets BIGINT, PRIMARY KEY (source, sport, market_type));
                 CREATE TABLE IF NOT EXISTS grid_count (run_ts TIMESTAMPTZ, source TEXT, tested BIGINT, with300 BIGINT, survivors BIGINT, types_done INT, types_total INT)"""); con.commit()
    if '--report' in sys.argv: report(con, REP); return
    c.execute("SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_result WHERE market_type <> 'ASIAN_HANDICAP' GROUP BY 1, 2 ORDER BY 3")
    todo = c.fetchall(); c.execute("SELECT sport, market_type FROM grid_done WHERE source='history'"); done = set(c.fetchall())
    months = pd.period_range('2019-01', dt.date.today().strftime('%Y-%m'), freq='M')
    for sport, mt, nm in todo:                      # smallest first, so every sport reports early; football's big types last
        if (sport, mt) in done: continue
        parts = []; seen = 0
        for m in months:
            a = m.to_timestamp().tz_localize('UTC'); b = (m + 1).to_timestamp().tz_localize('UTC')
            df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
                                FROM bf_hist_other o JOIN bf_hist_result r ON r.market_id = o.market_id AND r.sel = o.sel
                                WHERE o.sport = %s AND o.market_type = %s AND o.market_time >= %s AND o.market_time < %s AND r.status IN ('WINNER', 'LOSER')""", con, params=(sport, mt, a, b))
            if df.empty: continue
            seen += df.market_id.nunique(); P = points(df)
            if len(P): parts.append(aggregate(P))
            time.sleep(0.2)
        c.execute("DELETE FROM grid_agg WHERE source='history' AND sport=%s AND market_type=%s", (sport, mt))
        if parts:
            A = pd.concat(parts).groupby(['point', 'band', 'side', 'direction', 'month'], as_index=False)[['count', 'sum']].sum()
            c.executemany("INSERT INTO grid_agg VALUES ('history',%s,%s,%s,%s,%s,%s,%s,%s,%s)", [(sport, mt, r.point, int(r.band), r.side, r.direction, r.month, int(r['count']), float(r['sum'])) for _, r in A.iterrows()])
        c.execute("INSERT INTO grid_done VALUES ('history',%s,%s,now(),%s) ON CONFLICT DO NOTHING", (sport, mt, seen)); con.commit()
        print(f"{dt.datetime.now():%H:%M} {sport} {mt}: {seen:,} markets", flush=True)
        try: report(con, REP)
        except Exception as e: con.rollback(); print('report error (grid carries on):', repr(e)[:200], flush=True)
    report(con, REP)
if __name__ == '__main__': main()
GRID
python3 -m py_compile $T/grid_history.py && echo "compiles" || { cp $T/grid_history.py.bak_682 $T/grid_history.py; echo "COMPILE FAILED - old version restored"; }
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
c.execute("DELETE FROM grid_done WHERE source='history'"); print("finished-list cleared:", c.rowcount, "market types will be redone with both families"); con.commit()
PY
: > $T/grid_history.log
nohup setsid $T/run_grid_history.sh > /dev/null 2>&1 < /dev/null &
sleep 90; echo "running: $(pgrep -fc '[g]rid_history.py')"; tail -5 $T/grid_history.log | cut -c1-200
echo '```'; echo; head -14 /root/pe-queue/reports/grid_history.md 2>&1; } > $R 2>&1
cd /root/pe-queue && git add $R reports/grid_history.md 2>/dev/null; git commit -qm "682: grid family 2 installed, restarted" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
