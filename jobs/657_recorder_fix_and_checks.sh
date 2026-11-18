#!/bin/bash
# 657 (Wed 18 Nov 2026, 06:50). Three things, report reports/morning_657.md:
#  1. The recorder (655) kept hitting Betfair's TOO_MUCH_DATA limit (ANGX-0001: catalogue weight MARKET_DESCRIPTION x maxResults > 200),
#     so it only caught some markets. Now: list the events, then their markets 8 events at a time (max 200), limited to the ~23 market
#     types the tests use. Restart and prove it covers every match.
#  2. Small bites went the wrong way forward (-£200 on 1,748 paper trades). What did the losing trades have in common? (read only)
#  3. International matches (Peter: "there must be emotional money traded on those"): are they in the recorder and in the history?
T=/root/pe-sports/team; R=/root/pe-queue/reports/morning_657.md
cat > $T/book_recorder.py <<'PY'
#!/usr/bin/env python3
"""655 THE recorder (one machine, step 1): the real Betfair order book for every football market from 3 h before the off to the end of
the match - best two back and lay prices with the money available, last trade, matched - once a minute in-play, every 2 minutes pre-off.
This replaces one-off recorders as the data every nightly test runs on. Read only: nothing is sent to any exchange."""
import sys, time, datetime as dt, requests, psycopg2, psycopg2.extras
sys.path.insert(0, '/root/pe-queue/runner'); import creds
APP, USER, PW = creds.betfair(); TOK = None
def login():
    global TOK
    r0 = requests.post("https://identitysso.betfair.com/api/login", data={"username": USER, "password": PW}, headers={"X-Application": APP, "Accept": "application/json"}, timeout=20)
    try: r = r0.json()
    except ValueError: raise RuntimeError(f"login non-JSON HTTP {r0.status_code}: {r0.text[:100]!r}")
    if r.get('status') != 'SUCCESS': raise RuntimeError(f"login {r.get('error')}")
    TOK = r['token']
def api(ep, body):
    for attempt in (1, 2):
        if TOK is None: login()
        r = requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/", json=body, headers={"X-Application": APP, "X-Authentication": TOK, "Content-Type": "application/json"}, timeout=30)
        try:
            j = r.json()
            if isinstance(j, dict) and ('faultcode' in j or 'detail' in j): raise ValueError(str(j)[:120])
            return j
        except ValueError:
            if attempt == 2: raise
            login()
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor()
c.execute("""CREATE TABLE IF NOT EXISTS book_snap (ts TIMESTAMPTZ, market_id TEXT, event_id TEXT, event_name TEXT, competition TEXT, country TEXT,
  market_type TEXT, start_ts TIMESTAMPTZ, inplay BOOLEAN, status TEXT, sel_id BIGINT, runner TEXT, back1 NUMERIC, back1_sz NUMERIC, back2 NUMERIC,
  lay1 NUMERIC, lay1_sz NUMERIC, lay2 NUMERIC, ltp NUMERIC, mkt_matched NUMERIC);
  CREATE INDEX IF NOT EXISTS book_snap_ts ON book_snap (ts); CREATE INDEX IF NOT EXISTS book_snap_mkt ON book_snap (market_id, ts)""")
c.execute("CREATE TABLE IF NOT EXISTS book_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, markets INT, rows_last INT, note TEXT)")
TYPES = ['MATCH_ODDS', 'OVER_UNDER_05', 'OVER_UNDER_15', 'OVER_UNDER_25', 'OVER_UNDER_35', 'OVER_UNDER_45', 'OVER_UNDER_55', 'BOTH_TEAMS_TO_SCORE',
         'CORRECT_SCORE', 'HALF_TIME', 'HALF_TIME_SCORE', 'HALF_TIME_FULL_TIME', 'FIRST_HALF_GOALS_05', 'FIRST_HALF_GOALS_15', 'FIRST_HALF_GOALS_25',
         'DOUBLE_CHANCE', 'DRAW_NO_BET', 'ASIAN_HANDICAP', 'NEXT_GOAL', 'FIRST_GOAL_SCORER', 'CLEAN_SHEET', 'TEAM_A_1', 'TEAM_B_1']
cat = {}; cat_t = 0; last = {}
while True:
    try:
        now = dt.datetime.now(dt.timezone.utc)
        if time.time() - cat_t > 600:
            # 657: Betfair caps catalogue weight (MARKET_DESCRIPTION x maxResults <= 200), so: list the events first, then their markets
            # 8 events at a time, limited to the market types the tests use (~15 per match)
            a = (now - dt.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'); b = (now + dt.timedelta(hours=3)).strftime('%Y-%m-%dT%H:%M:%SZ')
            evs = [e['event']['id'] for e in api('listEvents', {"filter": {"eventTypeIds": ["1"], "marketStartTime": {"from": a, "to": b}}})]
            new_cat = {}
            for i in range(0, len(evs), 8):
                f = {"eventIds": evs[i:i + 8], "marketTypeCodes": TYPES}
                try:
                    for m in api('listMarketCatalogue', {"filter": f, "marketProjection": ["EVENT", "COMPETITION", "MARKET_START_TIME", "MARKET_DESCRIPTION", "RUNNER_DESCRIPTION"], "maxResults": 200}):
                        new_cat[m['marketId']] = m
                except Exception as e: print(f"{dt.datetime.utcnow():%F %H:%M:%S} catalogue batch {i}: {e!r}"[:200], flush=True)
            if new_cat: cat = new_cat
            cat_t = time.time(); print(f"{dt.datetime.utcnow():%F %H:%M:%S} events {len(evs)} markets {len(cat)}", flush=True)
        due = []
        for mid, m in cat.items():
            st = dt.datetime.fromisoformat(m['marketStartTime'].replace('Z', '+00:00')); age = (now - st).total_seconds()
            every = 60 if age > 0 else (120 if age > -3600 else 300)   # in-play 1 min, last hour 2 min, earlier 5 min
            if -3 * 3600 <= age <= 3 * 3600 and time.time() - last.get(mid, 0) >= every: due.append(mid)
        rows = []
        for i in range(0, len(due), 40):
            for b in api('listMarketBook', {"marketIds": due[i:i + 40], "priceProjection": {"priceData": ["EX_BEST_OFFERS"], "exBestOffersOverrides": {"bestPricesDepth": 2}}}):
                m = cat.get(b['marketId']); last[b['marketId']] = time.time()
                if not m: continue
                if b.get('status') == 'CLOSED': cat.pop(b['marketId'], None); continue
                names = {r['selectionId']: r['runnerName'] for r in m.get('runners', [])}; ts = dt.datetime.now(dt.timezone.utc)
                for r in b.get('runners', []):
                    ex = r.get('ex', {}); bk = ex.get('availableToBack') or []; ly = ex.get('availableToLay') or []
                    g = lambda L, i, k: L[i].get(k) if len(L) > i else None
                    rows.append((ts, b['marketId'], m['event']['id'], m['event']['name'], (m.get('competition') or {}).get('name'), m['event'].get('countryCode'),
                                 (m.get('description') or {}).get('marketType'), m['marketStartTime'], b.get('inplay'), b.get('status'), r['selectionId'],
                                 names.get(r['selectionId']), g(bk, 0, 'price'), g(bk, 0, 'size'), g(bk, 1, 'price'), g(ly, 0, 'price'), g(ly, 0, 'size'),
                                 g(ly, 1, 'price'), r.get('lastPriceTraded'), b.get('totalMatched')))
        if rows: psycopg2.extras.execute_values(c, "INSERT INTO book_snap VALUES %s", rows, page_size=2000)
        c.execute("""INSERT INTO book_heartbeat VALUES (1, now(), %s, %s, %s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), markets=EXCLUDED.markets,
                     rows_last=EXCLUDED.rows_last, note=EXCLUDED.note""", (len(cat), len(rows), f"due {len(due)}"))
    except Exception as e:
        print(f"{dt.datetime.utcnow():%F %H:%M:%S} loop {e!r}"[:220], flush=True); time.sleep(20)
    time.sleep(10)
PY
{ echo "# 657 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 -m py_compile $T/book_recorder.py && echo compiles
pkill -f book_recorder.py; sleep 150
echo "recorder processes: $(pgrep -f book_recorder.py | wc -l)"; tail -4 $T/book_recorder.log | cut -c1-200
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='300s'")
c.execute("SELECT * FROM book_heartbeat"); print("book heartbeat:", c.fetchall())
c.execute("SELECT count(DISTINCT market_id), count(DISTINCT event_id) FROM book_snap WHERE ts > now()-interval '3 minutes'"); print("last 3 min markets/events:", c.fetchone())
print("\n== small bites forward: what the losers share")
for col in ("status", "liq", "cell", "CASE WHEN entry_px < 2 THEN 'a <2' WHEN entry_px < 3 THEN 'b 2-3' WHEN entry_px < 5 THEN 'c 3-5' WHEN entry_px < 10 THEN 'd 5-10' ELSE 'e 10+' END",
            "CASE WHEN exit_min - entry_min > interval '12 minutes' THEN 'exit late (suspended)' ELSE 'exit on time' END", "extract(hour from entry_min)::int"):
    c.execute(f"SELECT {col}, count(*), round(sum(pnl),2), round(avg(pnl),3) FROM small_bites_paper WHERE pnl IS NOT NULL GROUP BY 1 ORDER BY 3")
    print(col[:40], c.fetchall())
c.execute("""SELECT round(avg(abs(exit_px-entry_px)/entry_px)*100,2), round(avg(pnl) FILTER (WHERE pnl>0),3), round(avg(pnl) FILTER (WHERE pnl<0),3),
             count(*) FILTER (WHERE pnl>0), count(*) FILTER (WHERE pnl<0) FROM small_bites_paper WHERE pnl IS NOT NULL"""); print("avg move %, avg win, avg loss, wins, losses:", c.fetchone())
print("\n== internationals")
c.execute("""SELECT competition, count(DISTINCT event_id) FROM book_snap WHERE competition ~* 'international|qualif|nations|friendl|world cup|euro' GROUP BY 1 ORDER BY 2 DESC LIMIT 10"""); print("recorder:", c.fetchall())
c.execute("""SELECT count(DISTINCT market_id), min(market_time), max(market_time) FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS'
             AND event_name ~* '^(England|Scotland|Wales|Germany|France|Spain|Italy|Portugal|Netherlands|Brazil|Argentina|Belgium|Croatia|Denmark|Poland|USA|Mexico|Ireland|Northern Ireland|Norway|Sweden|Switzerland|Austria|Turkey|Japan) v (England|Scotland|Wales|Germany|France|Spain|Italy|Portugal|Netherlands|Brazil|Argentina|Belgium|Croatia|Denmark|Poland|USA|Mexico|Ireland|Northern Ireland|Norway|Sweden|Switzerland|Austria|Turkey|Japan|[A-Z][a-z]+)$'
             AND market_time > '2019-01-01'"""); print("history, international-looking match-odds markets:", c.fetchone())
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "657: recorder fix, small bites losers, internationals" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
