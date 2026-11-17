#!/bin/bash
# 654 (Tue 17 Nov 2026, 17:00). PAPER ONLY. 652 (cross-market coherence) showed very large edges, but on LAST TRADED prices, which in thin
# markets (correct score above all) are often hours old and not on offer - the figures are almost certainly inflated by that. The honest
# test is forward, on the real order book: coherence_paper.py reads live best back/lay (£2+ available) 2-5 min before each kick-off,
# fits the goal rates from match odds + over/under 2.5, and paper-bets a thin runner only at a price actually on offer that beats fair by
# the margin 652 chose (cells profitable on both halves only). Settles from Betfair. Daemon + keepalive; report daily 07:15 UTC.
T=/root/pe-sports/team
cat > $T/coherence_paper.py <<'PY'
#!/usr/bin/env python3
"""654 Coherence FORWARD paper on the REAL order book. 652 found big edges pricing thin markets from deep ones, but it used the last traded
price, which in thin markets can be hours old and not available. This bot only counts a bet at a price that is actually on offer:
2-5 min before the off it reads the live best back/lay (with £2+ available) of match odds, over/under 2.5 and the thin markets of the same
match, fits the Poisson goal rates from the deep markets' mid prices, and paper-bets a thin runner when its real price beats fair by the
margin 652 chose for that cell (only cells profitable on both halves). Settles from Betfair's own result. Nothing is sent to any exchange."""
import sys, re, time, datetime as dt, requests, psycopg2, csv
import numpy as np
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
        r = requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/", json=body, headers={"X-Application": APP, "X-Authentication": TOK, "Content-Type": "application/json"}, timeout=25)
        try:
            j = r.json()
            if isinstance(j, dict) and ('faultcode' in j or 'detail' in j): raise ValueError(str(j)[:120])
            return j
        except ValueError:
            if attempt == 2: raise
            login()
CELLS = {}
for r in csv.DictReader(open('/root/pe-sports/team/coherence_cells.csv')):
    if float(r['r1']) > 0 and float(r['r2']) > 0 and int(r['n2']) >= 150: CELLS[(r['grp'], r['side'])] = float(r['m'])
print("cells", len(CELLS), flush=True)
THIN = ['OVER_UNDER_15', 'OVER_UNDER_35', 'OVER_UNDER_45', 'BOTH_TEAMS_TO_SCORE', 'CORRECT_SCORE']
def grp_of(mt, key):
    g = mt.replace('OVER_UNDER_', 'OU') + ' ' + key
    return re.sub(r'(OU\d\d) (over|under)\d\.\d', r'\1 \2', g)
assert grp_of('OVER_UNDER_15', 'under1.5') == 'OU15 under' and grp_of('CORRECT_SCORE', 'cs1-2') == 'CORRECT_SCORE cs1-2'
def mid(rn):
    ex = rn.get('ex', {}); b = (ex.get('availableToBack') or [{}])[0].get('price'); l = (ex.get('availableToLay') or [{}])[0].get('price')
    return (b, l, (b + l) / 2 if b and l and l / b <= 1.05 else None)
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor()
c.execute("""CREATE TABLE IF NOT EXISTS coherence_paper (market_id TEXT, sel_id BIGINT, cell TEXT, side TEXT, event_name TEXT, start_ts TIMESTAMPTZ,
  placed_ts TIMESTAMPTZ DEFAULT now(), price NUMERIC, size_avail NUMERIC, fair NUMERIC, edge NUMERIC, rate_h NUMERIC, rate_a NUMERIC, status TEXT DEFAULT 'open',
  won BOOLEAN, pnl NUMERIC, PRIMARY KEY (market_id, sel_id, side))""")
c.execute("CREATE TABLE IF NOT EXISTS coherence_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, events INT, bets_today INT, note TEXT)")
done_ev = set(); ev_cat = {}; cat_t = 0
while True:
    try:
        now = dt.datetime.now(dt.timezone.utc)
        if time.time() - cat_t > 240:
            f = {"eventTypeIds": ["1"], "marketTypeCodes": ['MATCH_ODDS', 'OVER_UNDER_25'] + THIN,
                 "marketStartTime": {"from": now.strftime('%Y-%m-%dT%H:%M:%SZ'), "to": (now + dt.timedelta(minutes=15)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
            ev_cat = {}
            for m in api('listMarketCatalogue', {"filter": f, "marketProjection": ["EVENT", "MARKET_START_TIME", "MARKET_DESCRIPTION", "RUNNER_DESCRIPTION"], "maxResults": 1000}):
                ev_cat.setdefault(m['event']['id'], []).append(m)
            cat_t = time.time()
        for eid, ms in ev_cat.items():
            if eid in done_ev: continue
            st = dt.datetime.fromisoformat(ms[0]['marketStartTime'].replace('Z', '+00:00')); sto = (st - now).total_seconds()
            if not (120 < sto <= 300): continue
            types = {m['description']['marketType']: m for m in ms}
            if 'MATCH_ODDS' not in types or 'OVER_UNDER_25' not in types: done_ev.add(eid); continue
            books = {b['marketId']: b for b in api('listMarketBook', {"marketIds": [m['marketId'] for m in ms], "priceProjection": {"priceData": ["EX_BEST_OFFERS"]}})}
            done_ev.add(eid)
            ev = ms[0]['event']['name']; h, _, a = ev.partition(' v ')
            mo = types['MATCH_ODDS']; names = {r['selectionId']: r['runnerName'] for r in mo['runners']}
            mp = {}
            for rn in books.get(mo['marketId'], {}).get('runners', []):
                nm = names.get(rn['selectionId'], ''); leg = 'draw' if 'draw' in nm.lower() else ('home' if nm == h.strip() else ('away' if nm == a.strip() else None))
                if leg: mp[leg] = mid(rn)[2]
            ou = types['OVER_UNDER_25']; on = {r['selectionId']: r['runnerName'].lower() for r in ou['runners']}; op = {}
            for rn in books.get(ou['marketId'], {}).get('runners', []): op['o' if 'over' in on.get(rn['selectionId'], '') else 'u'] = mid(rn)[2]
            if any(mp.get(k) is None for k in ('home', 'draw', 'away')) or any(op.get(k) is None for k in ('o', 'u')): continue
            inv = np.array([1 / mp['home'], 1 / mp['draw'], 1 / mp['away']]); inv /= inv.sum(); o = (1 / op['o']) / (1 / op['o'] + 1 / op['u'])
            obs = np.array([[inv[0], inv[1], inv[2], o]]); i = int(fit(obs)[0])
            if np.sqrt(((obs - TARGET[i]) ** 2).mean()) >= 0.02: continue
            for mt in THIN:
                m = types.get(mt)
                if not m: continue
                rnames = {r['selectionId']: r['runnerName'] for r in m['runners']}
                for rn in books.get(m['marketId'], {}).get('runners', []):
                    key = sel_key(mt, rnames.get(rn['selectionId'], ''))
                    if not key: continue
                    fp = float(fair_p(key, i)); g = grp_of(mt, key); ex = rn.get('ex', {})
                    for side, lst in (('BACK', 'availableToBack'), ('LAY', 'availableToLay')):
                        mm = CELLS.get((g, side))
                        if mm is None: continue
                        top = (ex.get(lst) or [{}])[0]; px = top.get('price'); sz = top.get('size', 0)
                        if not px or sz < ST: continue
                        edge = fp * px - 1 if side == 'BACK' else 1 - fp * px
                        if edge < mm: continue
                        c.execute("""INSERT INTO coherence_paper (market_id, sel_id, cell, side, event_name, start_ts, price, size_avail, fair, edge, rate_h, rate_a)
                                     VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING""",
                                  (m['marketId'], rn['selectionId'], g, side, ev, st, px, sz, round(1 / max(fp, 1e-6), 3), round(edge, 4), float(G[LH[i]]), float(G[LA[i]])))
        # settle bets whose match started 2.5 h+ ago
        c.execute("SELECT DISTINCT market_id FROM coherence_paper WHERE status='open' AND start_ts < now() - interval '150 minutes' LIMIT 40")
        mids = [r[0] for r in c.fetchall()]
        if mids:
            for b in api('listMarketBook', {"marketIds": mids}):
                if b.get('status') != 'CLOSED': continue
                for rn in b.get('runners', []):
                    if rn.get('status') not in ('WINNER', 'LOSER'): continue
                    won = rn['status'] == 'WINNER'
                    c.execute("SELECT side, price FROM coherence_paper WHERE market_id=%s AND sel_id=%s AND status='open'", (b['marketId'], rn['selectionId']))
                    for side, px in c.fetchall():
                        c.execute("UPDATE coherence_paper SET status='settled', won=%s, pnl=%s WHERE market_id=%s AND sel_id=%s AND side=%s",
                                  (won, round(settle(side, float(px), won), 2), b['marketId'], rn['selectionId'], side))
        c.execute("SELECT count(*) FROM coherence_paper WHERE placed_ts::date = now()::date"); td = c.fetchone()[0]
        c.execute("""INSERT INTO coherence_heartbeat VALUES (1, now(), %s, %s, %s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), events=EXCLUDED.events,
                     bets_today=EXCLUDED.bets_today, note=EXCLUDED.note""", (len(ev_cat), td, f"cells {len(CELLS)}"))
    except Exception as e:
        print(f"{dt.datetime.utcnow():%F %H:%M:%S} loop {e!r}"[:220], flush=True); time.sleep(30)
    time.sleep(20)
PY
cat > $T/run_coherence_paper.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/team && while true; do python3 -u coherence_paper.py >> coherence_paper.log 2>&1; echo "$(date -u) exited $?" >> coherence_paper.log; sleep 30; done
SH
cat > $T/coherence_report.sh <<'SH'
#!/bin/bash
python3 - <<'PY' > /root/pe-queue/reports/coherence_paper.md 2>&1
import sys, datetime as dt; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
print(f"# Coherence forward paper (real order book) — {dt.datetime.utcnow():%F %H:%M} UTC\n")
c.execute("SELECT count(*), count(*) FILTER (WHERE status='settled'), round(coalesce(sum(pnl),0),2) FROM coherence_paper"); n,s,p=c.fetchone()
print(f"Bets {n}, settled {s}, £{p} at £2.\n\n| cell | side | bets | settled | won | £ | per £100 |\n|---|---|---|---|---|---|---|")
c.execute("""SELECT cell, side, count(*), count(*) FILTER (WHERE status='settled'), count(*) FILTER (WHERE won AND side='BACK' OR NOT won AND side='LAY'),
             round(coalesce(sum(pnl),0),2), round(coalesce(sum(pnl),0)/greatest(1,count(*) FILTER (WHERE status='settled'))/2*100,1) FROM coherence_paper GROUP BY 1,2 ORDER BY 6 DESC""")
for r in c.fetchall(): print("| "+" | ".join(str(x) for x in r)+" |")
PY
cd /root/pe-queue && git add reports/coherence_paper.md && git commit -qm "coherence forward paper (daily)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
SH
chmod +x $T/run_coherence_paper.sh $T/coherence_report.sh
R=/root/pe-queue/reports/coherence_install_654.md
{ echo "# 654 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 -m py_compile $T/coherence_paper.py && echo compiles
crontab -l | grep -q run_coherence_paper || { crontab -l; echo "*/5 * * * * pgrep -f coherence_paper.py >/dev/null || nohup /root/pe-sports/team/run_coherence_paper.sh >/dev/null 2>&1 &   # 654 coherence forward paper"; echo "15 7 * * * /root/pe-sports/team/coherence_report.sh   # 654 coherence paper report"; } | crontab -
crontab -l | grep -n 654
pgrep -f coherence_paper.py >/dev/null || { nohup setsid $T/run_coherence_paper.sh >/dev/null 2>&1 < /dev/null & }
sleep 240; echo "processes: $(pgrep -f coherence_paper.py | wc -l)"; tail -4 $T/coherence_paper.log
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("SELECT * FROM coherence_heartbeat"); print("heartbeat:", c.fetchall())
c.execute("SELECT cell, side, price, fair, edge, event_name FROM coherence_paper ORDER BY placed_ts DESC LIMIT 8"); [print("  ",r) for r in c.fetchall()]
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "654: coherence forward paper installed" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
