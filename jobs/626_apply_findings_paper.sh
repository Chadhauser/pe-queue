#!/bin/bash
# 626 (Tue 17 Nov 2026, 06:50). Apply what the 16 Nov tests found, PAPER ONLY. Report: reports/apply_626.md
#  A. Pre-off bot (bookie_v2): only take when the price is at least 1% better than fair (613: the only method profitable in both
#     halves, 121 bets +£18.53). Version -> v2.1 so the forward record splits. Prune the cells that lost at a tradable price (612):
#     Soccer CORRECT_SCORE BACK, every HALF_TIME_FULL_TIME cell, DOUBLE_CHANCE LAY. Pruned rows are copied to fair_price_passed_pruned first.
#  B. Small bites forward paper (small_bites_live.py): the 7 in-and-out cells that passed both halves, on live stream_ticks, £2 paper,
#     with a keepalive cron line. Exits are stricter than the test (suspended markets kept, not dropped).
#  C. Why the verifier found 0 of 61 bot bets on the tape: are the bot's markets in stream_ticks at all?
R=/root/pe-queue/reports/apply_626.md
B=/root/pe-sports/bookie/bookie_v2.py
{
echo "# Apply 626 — $(date -u '+%F %H:%M') UTC"; echo
echo "## A. Bot value filter + prune"
cp $B $B.bak_626
python3 - "$B" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read(); n=0
for old,new in [("TAKE_WINDOW_S=120","TAKE_WINDOW_S=120; VALUE_M=0.01   # 626: take only 1%+ better than fair"),
                ("VERSION='v2'","VERSION='v2.1'"),
                ("if side=='BACK' and bb>fair: q=('BACK',bb)","if side=='BACK' and bb>=fair*(1+VALUE_M): q=('BACK',bb)"),
                ("elif side=='LAY' and bl<fair: q=('LAY',bl)","elif side=='LAY' and bl<=fair*(1-VALUE_M): q=('LAY',bl)")]:
    if new in s: n+=1; continue
    if s.count(old)==1: s=s.replace(old,new); n+=1
    else: print("NOT FOUND or not unique:",old)
if n==4: open(p,'w').write(s); print("bot patched (4/4)")
else: print(f"only {n}/4 matched - bot NOT changed")
PY
python3 -m py_compile $B && echo compiles || { cp $B.bak_626 $B; echo "compile failed - restored"; }
grep -nE "VALUE_M|VERSION=" $B | head -4
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
W="sport='Soccer' AND ((market_type='CORRECT_SCORE' AND side='BACK') OR market_type='HALF_TIME_FULL_TIME' OR (market_type='DOUBLE_CHANCE' AND side='LAY'))"
c.execute("CREATE TABLE IF NOT EXISTS fair_price_passed_pruned AS SELECT *, now() AS pruned_at FROM fair_price_passed WHERE false")
c.execute(f"INSERT INTO fair_price_passed_pruned SELECT *, now() FROM fair_price_passed WHERE {W}"); k=c.rowcount
c.execute(f"SELECT count(*) FROM fair_price_passed_pruned WHERE pruned_at > now()-interval '1 minute'"); chk=c.fetchone()[0]
if chk==k and k>0:
    c.execute(f"DELETE FROM fair_price_passed WHERE {W}"); print(f"pruned {c.rowcount} cells (copied {k} first)")
else: print(f"copy check failed ({chk} vs {k}) - nothing deleted")
con.commit()
c.execute("SELECT sport, market_type, band_lo, band_hi, side FROM fair_price_passed ORDER BY 1,2,3")
for r in c.fetchall(): print("  kept:", *r)
PY
cat /root/pe-sports/bookie/run_bookie_v2.sh
pkill -f 'python3 bookie_v2.py'; sleep 45
if ! pgrep -f 'python3 bookie_v2.py' >/dev/null && ! pgrep -f run_bookie_v2.sh >/dev/null; then cd /root/pe-sports/bookie && nohup setsid ./run_bookie_v2.sh >/dev/null 2>&1 < /dev/null & sleep 20; fi
echo "bot processes: $(pgrep -f 'python3 bookie_v2.py' | wc -l)"
tail -4 /root/pe-sports/bookie/*.log 2>/dev/null | tail -6
echo
echo "## B. Small bites forward paper"
cat > /root/pe-sports/team/small_bites_live.py <<'PY'
#!/usr/bin/env python3
"""Small bites, FORWARD paper (626). The cells that passed both halves on the tape (reports/small_bites.md, 16 Nov), traded forward on
live stream_ticks, £2 paper, 2% commission on winning greens. Nothing is sent to any exchange.
Entry rule (same as the test): at the close of minute m, the selection's mid moved >= k ticks against minute m-5, first minute of the move
(onset), market OPEN, spread <= 3 ticks, >= £2 both sides, lay price <= 50, same phase.
Exit (honest, stricter than the test): take the price at the first OPEN minute at or after m+H. The test dropped trades whose market was
suspended or closed at m+H; here they are kept: exit at the first open minute after, and if the market never reopens within 60 min the
trade is booked as STUCK at the worst case (back: -£2) until settled by hand."""
import sys, time, datetime as dt, collections
import psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); import creds
COMM = 0.02; ST = 2.0
T = []; p = 1.01
for hi, inc in [(2, .01), (3, .02), (4, .05), (6, .1), (10, .2), (20, .5), (30, 1), (50, 2), (100, 5), (1000, 10)]:
    while p < hi - 1e-9: T.append(round(p, 2)); p = round(p + inc, 2)
T.append(1000.0)
IDX = {v: i for i, v in enumerate(T)}
def tk(x):
    x = round(float(x), 2)
    if x in IDX: return IDX[x]
    lo, hi = 0, len(T) - 1
    while lo < hi:
        mid = (lo + hi) // 2
        if T[mid] < x - 1e-6: lo = mid + 1
        else: hi = mid
    return lo
def g_back_lay(b, l): return ST * (b / l - 1)
def g_lay_back(l, b): return ST * (1 - l / b)
def net(g): return g * (1 - COMM) if g > 0 else g
assert abs(g_back_lay(3.0, 2.5) - 0.4) < 1e-9 and tk(2.0) == 99 and T[tk(3.0) + 1] == 3.05
assert abs(net(g_back_lay(3.0, 2.5)) - 0.392) < 1e-9 and net(-1.0) == -1.0
def liq(tv):
    tv = float(tv or 0)
    return '<5k' if tv <= 5e3 else '5k-50k' if tv <= 5e4 else '50k-500k' if tv <= 5e5 else '500k+'
# (name, sport, mkt, phase, signal, side, k, H, liq buckets)
CELLS = [
    ('DRIFT_FADE k5 H10', 'football', 'MO', 'inplay', 'drift', 'back', 5, 10, {'<5k', '5k-50k', '50k-500k'}),
    ('DRIFT_FADE k3 H10', 'football', 'MO', 'inplay', 'drift', 'back', 3, 10, {'50k-500k'}),
    ('STEAM_FOLLOW k5 H10', 'football', 'OU25', 'inplay', 'steam', 'back', 5, 10, {'<5k', '5k-50k'}),
    ('STEAM_FOLLOW k3 H10', 'football', 'OU25', 'inplay', 'steam', 'back', 3, 10, {'<5k', '5k-50k'}),
    ('STEAM_FOLLOW k2 H10', 'football', 'OU25', 'inplay', 'steam', 'back', 2, 10, {'<5k', '5k-50k'}),
    ('STEAM_FOLLOW k2 H5', 'racing', 'WIN', 'pre', 'steam', 'back', 2, 5, {'<5k'}),
    ('STEAM_FOLLOW k3 H5', 'racing', 'WIN', 'pre', 'steam', 'back', 3, 5, {'<5k'}),
]
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor()
c.execute("SET statement_timeout='60s'")
c.execute("""CREATE TABLE IF NOT EXISTS small_bites_paper (id SERIAL PRIMARY KEY, cell TEXT, market_id TEXT, sel_id TEXT, sport TEXT, mkt TEXT,
  liq TEXT, side TEXT, k INT, h INT, entry_min TIMESTAMPTZ, entry_px NUMERIC, mv_ticks NUMERIC, exit_min TIMESTAMPTZ, exit_px NUMERIC,
  status TEXT DEFAULT 'open', pnl NUMERIC, created TIMESTAMPTZ DEFAULT now(), UNIQUE (cell, market_id, sel_id, entry_min))""")
c.execute("CREATE TABLE IF NOT EXISTS small_bites_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_trades INT, today INT, note TEXT)")
HIST = collections.defaultdict(dict)          # (market, sel) -> {minute: row}
def pull(since):
    c.execute("""SELECT DISTINCT ON (market_id, sel_id, date_trunc('minute', ts_recv)) date_trunc('minute', ts_recv), market_id, sel_id::text,
       sport, mkt, back_px, back_sz, lay_px, lay_sz, tv, inplay, status, secs_to_off FROM stream_ticks WHERE ts_recv >= %s
       ORDER BY market_id, sel_id, date_trunc('minute', ts_recv), ts_recv DESC""", (since,))
    for m, mid, sid, sp, mk, b, bs, l, ls, tv, ip, stt, sto in c.fetchall():
        HIST[(mid, sid)][m] = dict(sport=sp, mkt=mk, b=float(b or 0), bs=float(bs or 0), l=float(l or 0), ls=float(ls or 0), tv=tv,
                                   ip=str(ip).lower() in ('true', 't', '1'), open=str(stt).upper() in ('OPEN', 'ACTIVE', 'NONE', 'NAN'), sto=float(sto or 0))
def usable(r): return r and r['b'] > 1 and r['l'] > r['b'] and r['l'] <= 50
def mid_t(r): return (tk(r['b']) + tk(r['l'])) / 2
last_done = None
while True:
    now = dt.datetime.now(dt.timezone.utc); m = now.replace(second=0, microsecond=0) - dt.timedelta(minutes=1)   # last complete minute
    try:
        pull(m - dt.timedelta(minutes=7) if last_done is None else last_done - dt.timedelta(minutes=1))
        for key in list(HIST):                                          # keep 75 min of history
            for mm in [x for x in HIST[key] if x < now - dt.timedelta(minutes=75)]: del HIST[key][mm]
            if not HIST[key]: del HIST[key]
        if last_done != m:
            new = 0
            for (mid, sid), h in HIST.items():
                r = h.get(m); r5 = h.get(m - dt.timedelta(minutes=5)); r1 = h.get(m - dt.timedelta(minutes=1)); r6 = h.get(m - dt.timedelta(minutes=6))
                if not (usable(r) and usable(r5) and r['open']): continue
                spr = tk(r['l']) - tk(r['b'])
                if spr > 3 or r['bs'] < ST or r['ls'] < ST: continue
                mv = mid_t(r) - mid_t(r5)
                mv1 = (mid_t(r1) - mid_t(r6)) if usable(r1) and usable(r6) else 0
                phase = 'inplay' if r['ip'] else 'pre'
                for name, sp, mk, ph, sig, side, k, H, lq in CELLS:
                    if r['sport'] != sp or r['mkt'] != mk or phase != ph or liq(r['tv']) not in lq: continue
                    if phase == 'pre' and r['sto'] < H * 60 + 60: continue
                    on = (mv <= -k and not mv1 <= -k) if sig == 'steam' else (mv >= k and not mv1 >= k)
                    if not on: continue
                    px = r['b'] if side == 'back' else r['l']
                    c.execute("""INSERT INTO small_bites_paper (cell,market_id,sel_id,sport,mkt,liq,side,k,h,entry_min,entry_px,mv_ticks)
                                 VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING""",
                              (name, mid, sid, sp, mk, liq(r['tv']), side, k, H, m, px, mv)); new += c.rowcount
            # exits
            c.execute("SELECT id, market_id, sel_id, side, h, entry_min, entry_px FROM small_bites_paper WHERE status='open'")
            for i, mid, sid, side, H, em, epx in c.fetchall():
                due = em + dt.timedelta(minutes=H); h = HIST.get((mid, sid), {})
                if m < due: continue
                cand = sorted(x for x in h if x >= due and usable(h[x]) and h[x]['open'])
                if cand:
                    x = h[cand[0]]; epx = float(epx)
                    g = g_back_lay(epx, x['l']) if side == 'back' else g_lay_back(epx, x['b'])
                    c.execute("UPDATE small_bites_paper SET exit_min=%s, exit_px=%s, status='closed', pnl=%s WHERE id=%s",
                              (cand[0], x['l'] if side == 'back' else x['b'], round(net(g), 4), i))
                elif m >= due + dt.timedelta(minutes=60):
                    c.execute("UPDATE small_bites_paper SET status='stuck', pnl=%s WHERE id=%s", (-ST if side == 'back' else None, i))
            c.execute("SELECT count(*) FILTER (WHERE status='open'), count(*) FILTER (WHERE created::date=now()::date) FROM small_bites_paper")
            o, td = c.fetchone()
            c.execute("""INSERT INTO small_bites_heartbeat VALUES (1, now(), %s, %s, %s) ON CONFLICT (id) DO UPDATE SET last_seen=now(),
                         open_trades=EXCLUDED.open_trades, today=EXCLUDED.today, note=EXCLUDED.note""", (o, td, f'selections {len(HIST)} new {new}'))
            last_done = m
            print(f"{now:%F %H:%M} selections {len(HIST)} new {new} open {o} today {td}", flush=True)
    except Exception as e:
        print("loop", repr(e)[:200], flush=True)
        try: con.close()
        except Exception: pass
        time.sleep(10)
        con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor(); c.execute("SET statement_timeout='60s'")
    time.sleep(max(5, 62 - dt.datetime.now(dt.timezone.utc).second))
PY
python3 -m py_compile /root/pe-sports/team/small_bites_live.py && echo compiles
cat > /root/pe-sports/team/run_small_bites_live.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/team && while true; do python3 -u small_bites_live.py >> small_bites_live.log 2>&1; echo "$(date -u) exited $?" >> small_bites_live.log; sleep 20; done
SH
chmod +x /root/pe-sports/team/run_small_bites_live.sh
crontab -l | grep -q small_bites_live || { crontab -l; echo "*/5 * * * * pgrep -f small_bites_live.py >/dev/null || nohup /root/pe-sports/team/run_small_bites_live.sh >/dev/null 2>&1 &   # 626 small bites forward paper"; } | crontab -
pgrep -f small_bites_live.py >/dev/null || { nohup setsid /root/pe-sports/team/run_small_bites_live.sh >/dev/null 2>&1 < /dev/null & }
sleep 200
echo "processes: $(pgrep -f small_bites_live.py | wc -l)"; echo '```'; tail -5 /root/pe-sports/team/small_bites_live.log; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("SELECT cell, status, count(*) FROM small_bites_paper GROUP BY 1,2 ORDER BY 1"); print("paper rows:", c.fetchall())
c.execute("SELECT * FROM small_bites_heartbeat"); print("heartbeat:", c.fetchall())
PY
echo
echo "## C. Bot markets on the tape"
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='200s'")
c.execute("SELECT DISTINCT market_id, bf_market_id, mkt FROM bookie_paper WHERE ts>'2026-11-11' AND status IN ('settled','filled')"); bm=c.fetchall()
print("bot markets since 11 Nov:", len(bm), "sample:", bm[:3])
ids=list({str(b[1] or b[0]) for b in bm})
c.execute("SELECT count(DISTINCT market_id) FROM stream_ticks WHERE ts_recv>'2026-11-11' AND market_id = ANY(%s)", (ids,)); print("of those on stream_ticks:", c.fetchone()[0])
c.execute("SELECT market_id FROM stream_ticks WHERE ts_recv > now()-interval '10 minutes' LIMIT 3"); print("stream market_id format:", c.fetchall())
c.execute("SELECT mkt, count(DISTINCT market_id) FROM stream_ticks WHERE ts_recv > now()-interval '6 hours' GROUP BY 1 ORDER BY 2 DESC LIMIT 15"); print("stream markets by type, 6h:", c.fetchall())
c.execute("SELECT mkt, count(*) FROM bookie_paper WHERE ts>'2026-11-11' AND status IN ('settled','filled') GROUP BY 1 ORDER BY 2 DESC"); print("bot bets by type:", c.fetchall())
PY
} > "$R" 2>&1
cd /root/pe-queue && git add "$R" && git commit -qm "626: value filter + prune, small bites forward paper" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "626 done"
