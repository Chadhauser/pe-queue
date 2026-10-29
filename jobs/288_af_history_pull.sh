#!/bin/bash
# 288: API-FOOTBALL HISTORY PULL — fixtures + events (goal/red-card minutes) + match statistics for 29 leagues, seasons 2024 and
# 2025, into af_fixtures / af_events / af_stats. Resumable: fixtures first (1 call per league-season), then events+stats per
# finished fixture not yet stored (2 calls each), rate-limited, stops cleanly at 18 min and exits 75 until complete. Budget shown
# from the API's own headers every run. This is the data the upgrade was for: true goal minutes for 20k+ games, not 3,440.
python3 - <<'PY'
import sys,time,requests,psycopg2,json,datetime; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB; sys.path.insert(0,'/root/pe-queue/runner'); import creds
AF=creds.apifootball(); H={"x-apisports-key":AF}; BASE="https://v3.football.api-sports.io"
LEAGUES=[39,40,41,42,140,141,135,136,78,79,61,62,88,94,144,179,203,197,218,207,103,113,119,71,128,253,98,2,3]; SEASONS=[2024,2025]
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; k=con.cursor()
k.execute("""CREATE TABLE IF NOT EXISTS af_fixtures (fixture_id BIGINT PRIMARY KEY, league_id INT, league TEXT, season INT, kickoff TIMESTAMPTZ, home TEXT, away TEXT, hg INT, ag INT, ht_hg INT, ht_ag INT, status TEXT, events_done BOOLEAN DEFAULT false, stats_done BOOLEAN DEFAULT false);
CREATE TABLE IF NOT EXISTS af_events (fixture_id BIGINT, minute INT, extra INT, team TEXT, is_home BOOLEAN, type TEXT, detail TEXT, player TEXT);
CREATE INDEX IF NOT EXISTS af_events_fx ON af_events(fixture_id);
CREATE TABLE IF NOT EXISTS af_stats (fixture_id BIGINT, is_home BOOLEAN, team TEXT, shots INT, sot INT, poss NUMERIC, corners INT, xg NUMERIC, raw JSONB);
CREATE TABLE IF NOT EXISTS af_pull_log (ts TIMESTAMPTZ DEFAULT now(), note TEXT)""")
DEADLINE=time.time()+18*60; calls=0; remaining=None
def get(path,params):
    global calls,remaining
    for a in range(3):
        r=requests.get(BASE+path,params=params,headers=H,timeout=20); calls+=1
        remaining=r.headers.get('x-ratelimit-requests-remaining',remaining)
        if r.status_code==429: time.sleep(10); continue
        if r.status_code!=200: time.sleep(2); continue
        j=r.json()
        if j.get('errors') and not j.get('response'): print("api error",params,j.get('errors')); return None
        time.sleep(0.25); return j.get('response')
    return None
# 1. fixtures per league-season (skip pairs already loaded with >50 fixtures)
for L in LEAGUES:
    for S in SEASONS:
        if time.time()>DEADLINE: break
        k.execute("SELECT count(*) FROM af_fixtures WHERE league_id=%s AND season=%s",(L,S))
        if k.fetchone()[0]>50: continue
        res=get("/fixtures",{"league":L,"season":S}) or []
        rows=[]
        for f in res:
            fx=f['fixture']; t=f['teams']; g=f['goals']; ht=(f.get('score') or {}).get('halftime') or {}
            rows.append((fx['id'],L,f['league']['name'],S,fx['date'],t['home']['name'],t['away']['name'],g['home'],g['away'],ht.get('home'),ht.get('away'),fx['status']['short']))
        if rows:
            k.executemany("INSERT INTO af_fixtures (fixture_id,league_id,league,season,kickoff,home,away,hg,ag,ht_hg,ht_ag,status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (fixture_id) DO UPDATE SET hg=EXCLUDED.hg, ag=EXCLUDED.ag, status=EXCLUDED.status",rows)
        print(f"league {L} season {S}: {len(rows)} fixtures | remaining {remaining}",flush=True)
# 2. events + stats for finished fixtures
k.execute("SELECT fixture_id FROM af_fixtures WHERE status IN ('FT','AET','PEN') AND (NOT events_done OR NOT stats_done) ORDER BY kickoff DESC"); todo=[r[0] for r in k.fetchall()]
print("fixtures needing events/stats:",len(todo),flush=True); done=0
for fid in todo:
    if time.time()>DEADLINE: break
    if remaining is not None and int(remaining)<300: print("budget guard: remaining",remaining); break
    ev=get("/fixtures/events",{"fixture":fid})
    if ev is not None:
        k.execute("DELETE FROM af_events WHERE fixture_id=%s",(fid,))
        k.execute("SELECT home FROM af_fixtures WHERE fixture_id=%s",(fid,)); home=k.fetchone()[0]
        k.executemany("INSERT INTO af_events VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",[(fid,(e.get('time') or {}).get('elapsed'),(e.get('time') or {}).get('extra'),(e.get('team') or {}).get('name'),(e.get('team') or {}).get('name')==home,e.get('type'),e.get('detail'),(e.get('player') or {}).get('name')) for e in ev])
        k.execute("UPDATE af_fixtures SET events_done=true WHERE fixture_id=%s",(fid,))
    st=get("/fixtures/statistics",{"fixture":fid})
    if st is not None:
        k.execute("DELETE FROM af_stats WHERE fixture_id=%s",(fid,))
        for t in st:
            d={x['type']:x['value'] for x in t.get('statistics',[])}
            def num(v):
                try: return float(str(v).replace('%','')) if v is not None else None
                except Exception: return None
            k.execute("INSERT INTO af_stats VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",(fid,t['team']['name']==home,t['team']['name'],num(d.get('Total Shots')),num(d.get('Shots on Goal')),num(d.get('Ball Possession')),num(d.get('Corner Kicks')),num(d.get('expected_goals')),json.dumps(d)))
        k.execute("UPDATE af_fixtures SET stats_done=true WHERE fixture_id=%s",(fid,))
    done+=1
    if done%200==0: print(f"  {done} fixtures done | calls {calls} | remaining {remaining}",flush=True)
k.execute("SELECT count(*), count(*) FILTER (WHERE events_done AND stats_done), count(*) FILTER (WHERE status IN ('FT','AET','PEN')) FROM af_fixtures"); tot,fin,ft=k.fetchone()
k.execute("INSERT INTO af_pull_log(note) VALUES (%s)",(f"run: calls {calls}, remaining {remaining}, fixtures {tot}, finished {ft}, complete {fin}",))
print(f"fixtures {tot} | finished {ft} | with events+stats {fin} | calls this run {calls} | API remaining {remaining}")
if fin<ft: print("more to pull — re-polling"); sys.exit(75)
print("HISTORY PULL COMPLETE")
PY
