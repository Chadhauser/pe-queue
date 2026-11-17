# 636 — 2026-11-17 07:06 UTC
```
/root/pe-brain/repo/brain/baseline_refresher.py:53:MONITORED_LEAGUES = {1: "World Cup", 2: "UEFA Champions League", 3: "UEFA Europa League",
/root/pe-brain/repo/brain/baseline_refresher.py:175:        return [f for f in items if f.get('league', {}).get('id') in MONITORED_LEAGUES]
/root/pe-brain/repo/brain/baseline_refresher.py:492:        return [f for f in items if f.get('league', {}).get('id') in MONITORED_LEAGUES
/root/pe-brain/repo/brain/cs_scanner.py:65:MONITORED_LEAGUES = {
/root/pe-brain/repo/brain/cs_scanner.py:119:    for league_id, league_name in MONITORED_LEAGUES.items():
/root/pe-brain/repo/brain/dry_run.py:28:    MONITORED_LEAGUES,
/root/pe-brain/repo/brain/dry_run.py:51:    print(f"\nMonitored leagues: {len(MONITORED_LEAGUES)}")
/root/pe-brain/repo/brain/dry_run.py:52:    print(f"League IDs: {sorted(MONITORED_LEAGUES.keys())}")
/root/pe-brain/repo/brain/generate_watchlist.py:50:MONITORED_LEAGUES = {
/root/pe-brain/repo/brain/generate_watchlist.py:170:            if league_id not in MONITORED_LEAGUES:
/root/pe-brain/repo/brain/monitor_ht.py:79:MONITORED_LEAGUES = {
/root/pe-brain/repo/brain/monitor_ht.py:665:        monitored = [f for f in all_fix if f.get('league', {}).get('id') in MONITORED_LEAGUES]
MONITORED_LEAGUES = {
    1: "World Cup", 2: "UEFA Champions League", 3: "UEFA Europa League",
    4: "Euro Championship", 13: "CONMEBOL Libertadores", 39: "Premier League",
    40: "EFL Championship", 61: "Ligue 1", 78: "Bundesliga", 79: "Bundesliga 2",
    88: "Eredivisie", 94: "Primeira Liga", 135: "Serie A", 140: "La Liga",
    179: "Scottish Premiership", 253: "MLS", 71: "Brasileirao", 98: "J1 League",
    113: "Allsvenskan", 103: "Eliteserien", 345: "Czech Liga",
    144: "Pro League Belgium", 203: "Turkish Super Lig",
}

TOURNAMENT_OPENER_LEAGUES: set = set()

HIGH_SCORE_LEAGUES = {1, 2, 3, 4, 78, 88, 135, 144, 203, 79, 103, 113}
DEFENSIVE_LEAGUES = {61, 140, 39, 179}
HOME_FAV_PRICE_MAX = 2.20
QUALIFYING_SCORES = {"0-0", "1-0", "0-1", "1-1", "2-0", "0-2", "2-1", "1-2", "3-0", "0-3"}

STRATEGY_PARAMS = {
    'S14_HT_1_1_HOME_FAV_O25': {'action': 'BACK Over 2.5 Goals', 'target_market': 'O2.5', 'target_price_min': 1.40, 'target_price_max': 1.75, 'green_up_target': 0.25, 'stop_loss_minute': 85, 'severity': 'HIGH'},
    'S14B_HT_1_1_HIGH_SCORE_LEAGUE': {'action': 'BACK Over 2.5 Goals', 'target_market': 'O2.5', 'target_price_min': 1.40, 'target_price_max': 1.75, 'green_up_target': 0.25, 'stop_loss_minute': 85, 'severity': 'HIGH'},
    'S19_HT_1_0_HOME_LEAD_O25': {'action': 'BACK Over 2.5 Goals', 'target_market': 'O2.5', 'target_price_min': 1.85, 'target_price_max': 2.30, 'green_up_target': 0.40, 'stop_loss_minute': 80, 'severity': 'MEDIUM'},
    'S6_HT_0_1_HOME_FAV_COMEBACK': {'action': 'BACK Over 2.5 Goals', 'target_market': 'O2.5', 'target_price_min': 1.85, 'target_price_max': 2.30, 'green_up_target': 0.40, 'stop_loss_minute': 80, 'severity': 'MEDIUM'},
    'S21_HT_GOALFEST_O35': {'action': 'BACK Over 3.5 Goals', 'target_market': 'O3.5', 'target_price_min': 1.40, 'target_price_max': 1.75, 'green_up_target': 0.25, 'stop_loss_minute': 85, 'severity': 'HIGH'},
    'S22_HT_4PLUS_NEXTGOAL': {'action': 'BACK Over [HT_TOTAL+0.5] Goals', 'target_market': 'O[ht+0.5]', 'target_price_min': 1.40, 'target_price_max': 1.75, 'green_up_target': 0.25, 'stop_loss_minute': 85, 'severity': 'HIGH'},
    'S23_HT_2_0_GOALHEAVY_O35': {'action': 'BACK Over 3.5 Goals', 'target_market': 'O3.5', 'target_price_min': 1.85, 'target_price_max': 2.30, 'green_up_target': 0.40, 'stop_loss_minute': 80, 'severity': 'MEDIUM'},
    'L2_HT_0_0_DEFENSIVE_U25': {'action': 'BACK Under 2.5 Goals', 'target_market': 'U2.5', 'target_price_min': 1.25, 'target_price_max': 1.55, 'green_up_target': 0.15, 'stop_loss_minute': 75, 'severity': 'MEDIUM'},
--- get_live_fixtures
def get_live_fixtures():
    global _last_api_error_telegram_ts, _last_api_diag
    try:
        r = requests.get(f"{API_BASE}/fixtures", params={'live': 'all'}, headers=HEADERS, timeout=20)
        status = r.status_code
        rl_remaining = r.headers.get('x-ratelimit-requests-remaining', '?')
        rl_limit = r.headers.get('x-ratelimit-requests-limit', '?')
        if status != 200:
            body = r.text[:300].replace('\n', ' ')
            _last_api_diag = f"HTTP {status} | rl={rl_remaining}/{rl_limit} | body={body}"
            if time.time() - _last_api_error_telegram_ts > 3600:
                send_telegram(f"⚠️ <b>Brain: API-Football error</b>\n{_last_api_diag[:500]}")
                _last_api_error_telegram_ts = time.time()
            return [], []
        try:
            data = r.json()
        except Exception as exc:
            _last_api_diag = f"HTTP 200 but JSON parse failed: {exc}"
            return [], []
        response_items = data.get('response', [])
        results_count = data.get('results', 0)
        items_count = len(response_items) if isinstance(response_items, list) else 0
        _last_api_diag = (f"HTTP 200 | results={results_count} | items={items_count} | "
                          f"rl={rl_remaining}/{rl_limit}")
        all_fix = response_items if isinstance(response_items, list) else []
        monitored = [f for f in all_fix if f.get('league', {}).get('id') in MONITORED_LEAGUES]
        return monitored, all_fix
    except Exception as exc:
        _last_api_diag = f"exception: {type(exc).__name__}: {str(exc)[:200]}"
--- af_daily.py head
import sys,time,requests,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
AF=creds.apifootball(); H={"x-apisports-key":AF}; BASE="https://v3.football.api-sports.io"
LEAGUES=[39,40,41,42,140,141,135,136,78,79,61,62,88,94,144,179,203,197,218,207,103,113,119,71,128,253,98,2,3]; S=2026
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); con.autocommit=True; k=con.cursor()
DEADLINE=time.time()+15*60; remaining=None
def get(path,params):
    global remaining
    for a in range(3):
        r=requests.get(BASE+path,params=params,headers=H,timeout=20); remaining=r.headers.get('x-ratelimit-requests-remaining',remaining)
        if r.status_code==429: time.sleep(10); continue
        if r.status_code!=200: time.sleep(2); continue
        j=r.json()
        if j.get('errors') and not j.get('response'): print("api error",params,j.get('errors')); return None
        time.sleep(0.25); return j.get('response')
    return None
upd=0
for L in LEAGUES:
    res=get("/fixtures",{"league":L,"season":S}) or []
    for f in res:
        fx=f['fixture']; t=f['teams']; g=f['goals']; ht=(f.get('score') or {}).get('halftime') or {}
        k.execute("""INSERT INTO af_fixtures (fixture_id,league_id,league,season,kickoff,home,away,hg,ag,ht_hg,ht_ag,status,events_done,stats_done) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,false,false)
                     ON CONFLICT (fixture_id) DO UPDATE SET hg=EXCLUDED.hg, ag=EXCLUDED.ag, ht_hg=EXCLUDED.ht_hg, ht_ag=EXCLUDED.ht_ag, status=EXCLUDED.status, kickoff=EXCLUDED.kickoff""",
                  (fx['id'],L,f['league']['name'],S,fx['date'],t['home']['name'],t['away']['name'],g['home'],g['away'],ht.get('home'),ht.get('away'),fx['status']['short'])); upd+=1
print("fixtures refreshed",upd,"| remaining",remaining,flush=True)
k.execute("SELECT fixture_id, home FROM af_fixtures WHERE season=%s AND status IN ('FT','AET','PEN') AND (NOT coalesce(events_done,false) OR NOT coalesce(stats_done,false)) ORDER BY kickoff DESC",(S,)); todo=k.fetchall(); print("needing events/stats:",len(todo)); done=0
for fid,home in todo:
    if time.time()>DEADLINE or (remaining is not None and int(remaining)<300): break
    ev=get("/fixtures/events",{"fixture":fid})
    if ev is not None:
        k.execute("DELETE FROM af_events WHERE fixture_id=%s",(fid,))
--- live league ids the API returns right now vs the set (from the log)
Loaded 22 league baselines
Loaded 22 league baselines
Loaded 22 league baselines
Loaded 22 league baselines
Loaded 22 league baselines
```
