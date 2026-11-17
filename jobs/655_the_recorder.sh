#!/bin/bash
# 655 (Tue 17 Nov 2026, 16:45). ONE MACHINE, step 1 of 3 (Peter: "one and only", "I just want to make money"). The single recorder every
# nightly test will run on: real Betfair order book (best two back/lay with size, last trade, matched) for EVERY football market from 3 h
# before the off to the end of the match. Daemon + keepalive. Football first; other sports join it once it is proven. Read only.
T=/root/pe-sports/team
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
cat = {}; cat_t = 0; last = {}
while True:
    try:
        now = dt.datetime.now(dt.timezone.utc)
        if time.time() - cat_t > 600:
            cat = {}
            for k in range(-4, 6):                          # 30-minute slices from 2 h ago to 3 h ahead, so no slice hits the 1,000 cap
                a = now + dt.timedelta(minutes=30 * k); b = a + dt.timedelta(minutes=30)
                f = {"eventTypeIds": ["1"], "marketStartTime": {"from": a.strftime('%Y-%m-%dT%H:%M:%SZ'), "to": b.strftime('%Y-%m-%dT%H:%M:%SZ')}}
                for m in api('listMarketCatalogue', {"filter": f, "marketProjection": ["EVENT", "COMPETITION", "MARKET_START_TIME", "MARKET_DESCRIPTION", "RUNNER_DESCRIPTION"], "maxResults": 1000}):
                    cat[m['marketId']] = m
            cat_t = time.time()
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
cat > $T/run_book_recorder.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/team && while true; do python3 -u book_recorder.py >> book_recorder.log 2>&1; echo "$(date -u) exited $?" >> book_recorder.log; sleep 30; done
SH
chmod +x $T/run_book_recorder.sh
R=/root/pe-queue/reports/book_recorder_655.md
{ echo "# 655 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 -m py_compile $T/book_recorder.py && echo compiles
crontab -l | grep -q run_book_recorder || { crontab -l; echo "*/5 * * * * pgrep -f book_recorder.py >/dev/null || nohup /root/pe-sports/team/run_book_recorder.sh >/dev/null 2>&1 &   # 655 THE recorder"; } | crontab -
pgrep -f book_recorder.py >/dev/null || { nohup setsid $T/run_book_recorder.sh >/dev/null 2>&1 < /dev/null & }
sleep 300; echo "processes: $(pgrep -f book_recorder.py | wc -l)"; tail -3 $T/book_recorder.log
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("SELECT * FROM book_heartbeat"); print("heartbeat:", c.fetchall())
c.execute("SELECT count(*), count(DISTINCT market_id), count(DISTINCT market_type), count(DISTINCT event_id) FROM book_snap WHERE ts > now()-interval '5 minutes'"); print("last 5 min rows/markets/types/events:", c.fetchone())
c.execute("SELECT market_type, count(DISTINCT market_id) FROM book_snap WHERE ts > now()-interval '5 minutes' GROUP BY 1 ORDER BY 2 DESC LIMIT 12"); print(c.fetchall())
c.execute("SELECT pg_size_pretty(pg_total_relation_size('book_snap'))"); print("size:", c.fetchone())
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "655: the recorder" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
