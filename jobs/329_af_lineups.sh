#!/bin/bash
set -o pipefail
# 329: LOAD LINE-UPS from API-Football for the last 21 days of finished fixtures (one call per fixture, budget printed), into
# af_lineups (fixture_id, team, is_home, formation, player_id, player, pos, grid, starter). Unblocks the team-sheet lag test (Finder 0d)
# and the line-up fair-price model. Resumable: fixtures already loaded are skipped; stops at 15 minutes and re-polls (75) until done.
python3 - <<'PY'
import sys,time,requests,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB; sys.path.insert(0,'/root/pe-queue/runner'); import creds
H={"x-apisports-key":creds.apifootball()}; BASE="https://v3.football.api-sports.io"
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; k=con.cursor()
k.execute("""CREATE TABLE IF NOT EXISTS af_lineups (fixture_id BIGINT, team TEXT, is_home BOOLEAN, formation TEXT, player_id BIGINT, player TEXT, pos TEXT, grid TEXT, starter BOOLEAN);
CREATE INDEX IF NOT EXISTS af_lineups_fx ON af_lineups(fixture_id); CREATE TABLE IF NOT EXISTS af_lineups_done (fixture_id BIGINT PRIMARY KEY, n INT, loaded_at TIMESTAMPTZ DEFAULT now())""")
k.execute("""SELECT fixture_id, home FROM af_fixtures WHERE status='FT' AND kickoff>now()-interval '21 days' AND fixture_id NOT IN (SELECT fixture_id FROM af_lineups_done) ORDER BY kickoff DESC""")
todo=k.fetchall(); print("fixtures needing lineups:",len(todo),flush=True)
deadline=time.time()+15*60; calls=0; remaining=None; loaded=0
for fid,home in todo:
    if time.time()>deadline: break
    r=requests.get(BASE+"/fixtures/lineups",params={"fixture":fid},headers=H,timeout=20); calls+=1; remaining=r.headers.get('x-ratelimit-requests-remaining',remaining)
    if r.status_code==429: time.sleep(15); continue
    j=r.json() if r.status_code==200 else {}
    rows=[]
    for t in j.get('response',[]) or []:
        tn=t.get('team',{}).get('name'); isH=(tn==home)
        for grp,st in (('startXI',True),('substitutes',False)):
            for p in t.get(grp,[]) or []:
                pl=p.get('player',{}); rows.append((fid,tn,isH,t.get('formation'),pl.get('id'),pl.get('name'),pl.get('pos'),pl.get('grid'),st))
    if rows: k.executemany("INSERT INTO af_lineups VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",rows)
    k.execute("INSERT INTO af_lineups_done (fixture_id,n) VALUES (%s,%s) ON CONFLICT DO NOTHING",(fid,len(rows))); loaded+=1
    time.sleep(0.3)
k.execute("SELECT count(DISTINCT fixture_id), count(*) FILTER (WHERE starter) FROM af_lineups"); print("lineups: fixtures",k.fetchone(),"| this run",loaded,"| calls",calls,"| API remaining",remaining)
if loaded<len(todo): print("more to load — re-polling"); sys.exit(75)
print("LINEUPS COMPLETE")
PY
