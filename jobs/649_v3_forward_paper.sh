#!/bin/bash
# 649 (Tue 17 Nov 2026, 15:00). PAPER ONLY. Put the two v3 rules that passed both halves (reports/model_v3.md) onto forward paper:
#  R1 LAY home when Betfair's lay is 2%+ under Pinnacle's closing fair price; R2 BACK home when Betfair's back is 5%+ over it.
# We have no live Pinnacle feed, so: (1) v3_recorder.py records the real Betfair match-odds touch 1-3 min before every kick-off in the
# football-data countries (daemon + keepalive cron); (2) v3_settle.py runs daily 07:10 UTC, refreshes this season's football-data files
# (Pinnacle closing + results arrive there a few days after each match), applies the rules to the recorded prices and settles them.
# Every bet is on data the rules never saw. Report: reports/v3_paper.md (daily) and reports/v3_install_649.md (now).
R=/root/pe-queue/reports/v3_install_649.md; T=/root/pe-sports/team
cat > $T/v3_recorder.py <<'PY'
#!/usr/bin/env python3
"""649 v3 forward paper, part 1: record the Betfair match-odds touch about 2 minutes before every kick-off in the football-data divisions'
countries, with event name, start time and runner names. Nothing is sent to any exchange. One row per runner per market."""
import sys, time, datetime as dt, requests, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); import creds
APP, USER, PW = creds.betfair(); TOK = None
COUNTRIES = ['GB', 'DE', 'IT', 'ES', 'FR', 'NL', 'BE', 'PT', 'TR', 'GR']
def login():
    global TOK
    r0 = requests.post("https://identitysso.betfair.com/api/login", data={"username": USER, "password": PW},
                       headers={"X-Application": APP, "Accept": "application/json"}, timeout=20)
    try: r = r0.json()
    except ValueError: raise RuntimeError(f"login non-JSON HTTP {r0.status_code}: {r0.text[:100]!r}")
    if r.get('status') != 'SUCCESS': raise RuntimeError(f"login {r.get('error')}")
    TOK = r['token']
def api(ep, body):
    for attempt in (1, 2):
        if TOK is None: login()
        r = requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/", json=body,
                          headers={"X-Application": APP, "X-Authentication": TOK, "Content-Type": "application/json"}, timeout=25)
        try:
            j = r.json()
            if isinstance(j, dict) and ('faultcode' in j or 'detail' in j): raise ValueError(str(j)[:120])
            return j
        except ValueError:
            if attempt == 2: raise
            login()            # session expired or bad reply: log in again once
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor()
c.execute("""CREATE TABLE IF NOT EXISTS v3_snap (market_id TEXT, sel_id BIGINT, runner TEXT, event_name TEXT, country TEXT, competition TEXT,
  start_ts TIMESTAMPTZ, snap_ts TIMESTAMPTZ, secs_to_off INT, back_px NUMERIC, back_sz NUMERIC, lay_px NUMERIC, lay_sz NUMERIC, ltp NUMERIC,
  total_matched NUMERIC, PRIMARY KEY (market_id, sel_id))""")
c.execute("CREATE TABLE IF NOT EXISTS v3_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, markets_watched INT, snapped_today INT, note TEXT)")
cat = {}; cat_t = 0
while True:
    try:
        now = dt.datetime.now(dt.timezone.utc)
        if time.time() - cat_t > 300:
            f = {"eventTypeIds": ["1"], "marketTypeCodes": ["MATCH_ODDS"], "marketCountries": COUNTRIES,
                 "marketStartTime": {"from": now.strftime('%Y-%m-%dT%H:%M:%SZ'), "to": (now + dt.timedelta(minutes=20)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
            cat = {m['marketId']: m for m in api('listMarketCatalogue', {"filter": f, "marketProjection": ["EVENT", "COMPETITION", "RUNNER_DESCRIPTION", "MARKET_START_TIME"], "maxResults": 200})}
            cat_t = time.time()
        due = []
        for mid, m in cat.items():
            sto = (dt.datetime.fromisoformat(m['marketStartTime'].replace('Z', '+00:00')) - now).total_seconds()
            if 60 < sto <= 180: due.append((mid, sto))
        c.execute("SELECT DISTINCT market_id FROM v3_snap WHERE start_ts > now() - interval '1 hour'"); have = {r[0] for r in c.fetchall()}
        due = [(mid, sto) for mid, sto in due if mid not in have]
        for i in range(0, len(due), 20):
            chunk = due[i:i + 20]
            for b in api('listMarketBook', {"marketIds": [x[0] for x in chunk], "priceProjection": {"priceData": ["EX_BEST_OFFERS"]}}):
                m = cat[b['marketId']]; sto = dict(chunk)[b['marketId']]
                names = {r['selectionId']: r['runnerName'] for r in m.get('runners', [])}
                for r in b.get('runners', []):
                    ex = r.get('ex', {}); bb = (ex.get('availableToBack') or [{}])[0]; bl = (ex.get('availableToLay') or [{}])[0]
                    c.execute("INSERT INTO v3_snap VALUES (%s,%s,%s,%s,%s,%s,%s,now(),%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                              (b['marketId'], r['selectionId'], names.get(r['selectionId']), m['event']['name'], m['event'].get('countryCode'),
                               (m.get('competition') or {}).get('name'), m['marketStartTime'], int(sto), bb.get('price'), bb.get('size'),
                               bl.get('price'), bl.get('size'), r.get('lastPriceTraded'), b.get('totalMatched')))
        c.execute("SELECT count(DISTINCT market_id) FROM v3_snap WHERE snap_ts::date = now()::date"); td = c.fetchone()[0]
        c.execute("""INSERT INTO v3_heartbeat VALUES (1, now(), %s, %s, %s) ON CONFLICT (id) DO UPDATE SET last_seen=now(),
                     markets_watched=EXCLUDED.markets_watched, snapped_today=EXCLUDED.snapped_today, note=EXCLUDED.note""", (len(cat), td, f"due {len(due)}"))
    except Exception as e:
        print(f"{dt.datetime.utcnow():%F %H:%M:%S} loop {e!r}"[:220], flush=True); time.sleep(30)
    time.sleep(20)
PY
cat > $T/v3_settle.py <<'PY'
#!/usr/bin/env python3
"""649 v3 forward paper, part 2 (daily). Refresh this season's football-data files (Pinnacle closing odds and results appear there a few days
after each match), then apply the two v3 rules that passed both halves to every Betfair price recorded since 17 Nov:
  R1 LAY the home team when Betfair's lay price is at least 2% under Pinnacle's closing fair price (newer half +3.3 per £100, 1,906 bets)
  R2 BACK the home team when Betfair's back price is at least 5% over Pinnacle's closing fair price (newer half +1.5 per £100, 705 bets)
The prices are the real Betfair touch recorded 1-3 minutes before the off; £2, 2% commission; settled on the full-time score."""
import sys, io, csv, re, unicodedata, datetime as dt, requests, psycopg2, psycopg2.extras
sys.path.insert(0, '/root/pe-queue/runner'); import creds
COMM = 0.02; ST = 2.0
STOP = {'fc', 'cf', 'sc', 'afc', 'ac', 'fk', 'sk', 'if', 'bk', 'cd', 'ud', 'sd', 'de', 'the', 'club', 'calcio', 'ssc', 'as', 'us', 'rc', 'vfb', 'vfl', 'tsg', 'sv', 'fsv', 'real', 'town', 'city', 'united', 'utd', 'athletic', 'sporting'}
ALIAS = {'wolves': 'wolverhampton', 'spurs': 'tottenham', 'man': 'manchester', 'nottm': 'nottingham', 'sheff': 'sheffield', 'psg': 'paris',
         'inter': 'internazionale', 'mgladbach': 'monchengladbach', 'munchen': 'munich', 'muenchen': 'munich', 'qpr': 'queens'}
def toks(s):
    s = unicodedata.normalize('NFKD', str(s or '')).encode('ascii', 'ignore').decode().lower()
    return {ALIAS.get(w, w) for w in re.findall(r'[a-z0-9]+', s) if w not in STOP and len(w) > 2}
def same(a, b): return bool(toks(a) & toks(b))
def devig(*o):
    inv = [1 / x for x in o]; s = sum(inv); return [x / s for x in inv]
def settle(side, px, won):
    g = ((px - 1) * ST if won else -ST) if side == 'BACK' else (-(px - 1) * ST if won else ST)
    return g * (1 - COMM) if g > 0 else g
assert settle('LAY', 2.5, False) == 1.96 and settle('LAY', 2.5, True) == -3.0 and settle('BACK', 2.0, True) == 1.96
RULES = [('R1 home LAY 2%', 'LAY', 0.02), ('R2 home BACK 5%', 'BACK', 0.05)]
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor()
# 1. refresh this season's football-data files (results + Pinnacle closing), upserting the fields we use
DIVS = ['E0', 'E1', 'E2', 'E3', 'EC', 'SC0', 'SC1', 'D1', 'D2', 'I1', 'I2', 'SP1', 'SP2', 'F1', 'F2', 'N1', 'B1', 'P1', 'T1', 'G1']
def num(x):
    try: return float(x) if x not in ('', None) else None
    except Exception: return None
def day(x):
    for f in ('%d/%m/%Y', '%d/%m/%y'):
        try: return dt.datetime.strptime(x, f).date()
        except Exception: pass
up = 0
for d in DIVS:
    try: r = requests.get(f"https://www.football-data.co.uk/mmz4281/2627/{d}.csv", timeout=60)
    except Exception as e: print(d, "download failed", e); continue
    if r.status_code != 200 or len(r.content) < 500: continue
    rows = []
    for row in csv.DictReader(io.StringIO(r.content.decode('latin-1'))):
        g = row.get
        if not g('Date') or not g('HomeTeam') or day(g('Date')) is None: continue
        rows.append((d, '2627', day(g('Date')), g('HomeTeam'), g('AwayTeam'), num(g('FTHG')), num(g('FTAG')), num(g('PSH') or g('PH')), num(g('PSD') or g('PD')),
                     num(g('PSA') or g('PA')), num(g('PSCH')), num(g('PSCD')), num(g('PSCA'))))
    psycopg2.extras.execute_values(c, """INSERT INTO fd_matches (div, season, date, home, away, fthg, ftag, psh, psd, psa, psch, pscd, psca) VALUES %s
        ON CONFLICT (div, date, home, away) DO UPDATE SET fthg=EXCLUDED.fthg, ftag=EXCLUDED.ftag, psh=EXCLUDED.psh, psd=EXCLUDED.psd, psa=EXCLUDED.psa,
        psch=EXCLUDED.psch, pscd=EXCLUDED.pscd, psca=EXCLUDED.psca""", rows, page_size=500); up += len(rows)
c.execute("SELECT max(date) FILTER (WHERE psch IS NOT NULL) FROM fd_matches"); last_fd = c.fetchone()[0]
# 2. apply the rules to the recorded Betfair prices
c.execute("""CREATE TABLE IF NOT EXISTS v3_paper (market_id TEXT, rule TEXT, event_name TEXT, start_ts TIMESTAMPTZ, side TEXT, price NUMERIC,
  fair NUMERIC, edge NUMERIC, home_goals INT, away_goals INT, won BOOLEAN, pnl NUMERIC, settled_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (market_id, rule))""")
c.execute("SELECT market_id, sel_id, runner, event_name, start_ts, back_px, back_sz, lay_px, lay_sz FROM v3_snap WHERE start_ts >= '2026-11-17' ORDER BY market_id")
S = {}
for row in c.fetchall(): S.setdefault(row[0], []).append(row)
c.execute("SELECT DISTINCT market_id FROM v3_paper"); done = {r[0] for r in c.fetchall()}
c.execute("SELECT date, home, away, fthg, ftag, psch, pscd, psca FROM fd_matches WHERE date >= '2026-11-16' AND psch > 1 AND fthg IS NOT NULL")
FD = {}
for r in c.fetchall(): FD.setdefault(r[0], []).append(r)
matched = 0; new = 0
for mid, rs in S.items():
    if mid in done: continue
    ev = str(rs[0][3]); st = rs[0][4]
    if ' v ' not in ev: continue
    h, a = ev.split(' v ', 1)
    cand = [r for d in (st.date(), st.date() - dt.timedelta(days=1)) for r in FD.get(d, []) if same(r[1], h) and same(r[2], a)]
    if len(cand) != 1: continue
    matched += 1; _, fh, fa, hg, ag, ch, cd_, ca = cand[0]
    home = [x for x in rs if same(x[2], h) and not same(x[2], a) and 'draw' not in str(x[2]).lower()]
    if len(home) != 1: continue
    _, _, _, _, _, bb, bs, bl, ls = home[0]
    p = devig(float(ch), float(cd_), float(ca))[0]; won = int(hg) > int(ag)
    for name, side, m in RULES:
        px, sz = (bl, ls) if side == 'LAY' else (bb, bs)
        if not px or not sz or float(sz) < ST: continue
        px = float(px); edge = (1 - p * px) if side == 'LAY' else (p * px - 1)
        if edge < m: continue
        c.execute("INSERT INTO v3_paper (market_id, rule, event_name, start_ts, side, price, fair, edge, home_goals, away_goals, won, pnl) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                  (mid, name, ev, st, side, px, round(1 / p, 3), round(edge, 4), int(hg), int(ag), won, round(settle(side, px, won), 2))); new += c.rowcount
# 3. report
c.execute("SELECT count(DISTINCT market_id), min(start_ts), max(start_ts) FROM v3_snap"); ns = c.fetchone()
out = [f"# v3 forward paper (Pinnacle fair, Betfair price) — {dt.datetime.utcnow():%F %H:%M} UTC", "",
       f"Betfair markets recorded 1-3 min before the off: {ns[0]} ({ns[1]} to {ns[2]}). football-data rows refreshed: {up}; Pinnacle closing available up to {last_fd}.",
       f"Matched to a Pinnacle closing price this run: {matched}; new paper bets: {new}.", "",
       "| rule | settled | won | £ at £2 | per £100 | first half £ | second half £ | towards 100 |", "|---|---|---|---|---|---|---|---|"]
for name, side, m in RULES:
    c.execute("SELECT pnl, won FROM v3_paper WHERE rule=%s ORDER BY start_ts", (name,)); P = c.fetchall(); n = len(P)
    pn = [float(x[0]) for x in P]; h = n // 2
    out.append(f"| {name} | {n} | {sum(1 for x in P if x[1] == (side == 'BACK'))} | £{sum(pn):+.2f} | £{(sum(pn) / (n * ST) * 100 if n else 0):+.1f} | £{sum(pn[:h]):+.2f} | £{sum(pn[h:]):+.2f} | {n} of 100 |")
open('/root/pe-queue/reports/v3_paper.md', 'w').write("\n".join(out) + "\n"); print("\n".join(out))
PY
cat > $T/run_v3_recorder.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/team && while true; do python3 -u v3_recorder.py >> v3_recorder.log 2>&1; echo "$(date -u) exited $?" >> v3_recorder.log; sleep 30; done
SH
cat > $T/run_v3_settle.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/team && timeout 1800 python3 v3_settle.py >> v3_settle.log 2>&1
cd /root/pe-queue && git add reports/v3_paper.md && git commit -qm "v3 forward paper (daily)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
SH
chmod +x $T/run_v3_recorder.sh $T/run_v3_settle.sh
{ echo "# 649 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 -m py_compile $T/v3_recorder.py $T/v3_settle.py && echo compiles
crontab -l | grep -q run_v3_recorder || { crontab -l; echo "*/5 * * * * pgrep -f v3_recorder.py >/dev/null || nohup /root/pe-sports/team/run_v3_recorder.sh >/dev/null 2>&1 &   # 649 v3 forward paper recorder"; echo "10 7 * * * /root/pe-sports/team/run_v3_settle.sh   # 649 v3 forward paper settle"; } | crontab -
crontab -l | grep -n "649"
pgrep -f v3_recorder.py >/dev/null || { nohup setsid $T/run_v3_recorder.sh >/dev/null 2>&1 < /dev/null & }
sleep 150; echo "recorder processes: $(pgrep -f v3_recorder.py | wc -l)"; tail -3 $T/v3_recorder.log
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("SELECT * FROM v3_heartbeat"); print("heartbeat:", c.fetchall())
c.execute("SELECT count(*), count(DISTINCT market_id) FROM v3_snap"); print("snap rows/markets:", c.fetchone())
PY
echo "--- first settle run (backfills football-data; no bets expected before Pinnacle closing for 17 Nov+ is published)"
timeout 1200 python3 $T/v3_settle.py 2>&1 | tail -8
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R reports/v3_paper.md 2>/dev/null; git commit -qm "649: v3 forward paper installed" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "649 done"
