#!/bin/bash
set -o pipefail
# 499_player_stats_load (Finder 2026-11-04, queue item 62): /fixtures/players for finished fixtures since season 2024, newest first, into af_player_stats on the LOCAL database. One call per fixture, resumable through af_player_stats_done. Args: max fixtures, max seconds (default 20000, 2400). Stops at under 150 API calls remaining. Each fixture's rows and its done mark commit together, so a stop cannot leave a half-loaded game. A fixture only counts as done on a clean 200; an empty answer is marked done with n=0 and reported. Never prints the key. Nothing schedules this; re-run it to continue.
python3 - "$@" <<'PY' 2>&1
import sys,time,requests,psycopg2
from psycopg2.extras import execute_values
sys.path.insert(0,'/root/pe-queue/runner'); import creds
BASE="https://v3.football.api-sports.io"; FLOOR=150
def to_num(x):
    try: return float(x)
    except (TypeError,ValueError): return None
def to_int(x):
    v=to_num(x); return None if v is None else int(v)
def rows_of(fid,res):
    """API /fixtures/players response -> one tuple per player per team. Players with no id are dropped."""
    out=[]
    for t in res or []:
        team=(t.get('team') or {}).get('name') or 'unknown'   # team is in the primary key, a null would stop the load
        for p in t.get('players') or []:
            pl=p.get('player') or {}; s=(p.get('statistics') or [{}])[0] or {}
            g=s.get('games') or {}; sh=s.get('shots') or {}; go=s.get('goals') or {}
            if pl.get('id') is None: continue
            out.append((fid,team,pl['id'],pl.get('name'),to_int(g.get('minutes')),to_int(sh.get('total')),to_int(sh.get('on')),to_int(go.get('total')),to_int(go.get('assists')),g.get('position'),to_num(g.get('rating'))))
    return out
def low(rem): return rem is not None and rem<FLOOR
# known answers
S_=[{'team':{'name':'A'},'players':[{'player':{'id':7,'name':'X'},'statistics':[{'games':{'minutes':90,'position':'F','rating':'7.4'},'shots':{'total':3,'on':2},'goals':{'total':1,'assists':None}}]},{'player':{'id':8,'name':'Y'},'statistics':[{'games':{'minutes':None,'rating':None},'shots':{},'goals':{}}]},{'player':{'name':'no id'},'statistics':[{}]}]}]
assert rows_of(1,S_)==[(1,'A',7,'X',90,3,2,1,None,'F',7.4),(1,'A',8,'Y',None,None,None,None,None,None,None)]
assert rows_of(1,None)==[] and rows_of(1,[{'team':{'name':'A'},'players':[{'player':{'id':9,'name':'Z'},'statistics':[]}]}])==[(1,'A',9,'Z',None,None,None,None,None,None,None)]
assert rows_of(1,[{'team':None,'players':[{'player':{'id':9,'name':'Z'},'statistics':[]}]}])[0][1]=='unknown'
assert to_num('') is None and to_int('7')==7 and low(149) and not low(150) and not low(None)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
MAXF=int(sys.argv[1]) if len(sys.argv)>1 else 20000; MAXS=int(sys.argv[2]) if len(sys.argv)>2 else 2400
H={"x-apisports-key":creds.apifootball()}; assert H["x-apisports-key"],"no API key"
con=psycopg2.connect(creds.pg_local()); k=con.cursor(); k.execute("SET lock_timeout='30s'; SET statement_timeout='600s'")
k.execute("""CREATE TABLE IF NOT EXISTS af_player_stats (fixture_id BIGINT, team TEXT, player_id BIGINT, player TEXT, minutes INT, shots INT, shots_on INT, goals INT, assists INT, position TEXT, rating NUMERIC, PRIMARY KEY (fixture_id,team,player_id));
CREATE TABLE IF NOT EXISTS af_player_stats_done (fixture_id BIGINT PRIMARY KEY, n INT, fetched_at TIMESTAMPTZ DEFAULT now())"""); con.commit()
k.execute("""SELECT f.fixture_id FROM af_fixtures f LEFT JOIN af_player_stats_done d USING (fixture_id) WHERE f.season>=2024 AND f.status='FT' AND d.fixture_id IS NULL ORDER BY f.kickoff DESC LIMIT %s""",(MAXF,)); todo=[r[0] for r in k.fetchall()]; con.commit()
print(f"to fetch this run {len(todo)}",flush=True)
calls=0; done=0; empty=0; rem=None; fails={}; T0=time.time(); why='list finished'; total=0
for fid in todo:
    if time.time()-T0>MAXS: why='time cap'; break
    if low(rem): why=f'API budget floor, remaining {rem}'; break
    try:
        r=requests.get(BASE+"/fixtures/players",params={"fixture":fid},headers=H,timeout=30); calls+=1
    except requests.RequestException as e:
        fails[type(e).__name__]=fails.get(type(e).__name__,0)+1; time.sleep(2); continue
    try: rem=int(r.headers.get('x-ratelimit-requests-remaining'))
    except (TypeError,ValueError): pass
    if r.status_code!=200:
        fails[r.status_code]=fails.get(r.status_code,0)+1; time.sleep(10 if r.status_code==429 else 1)
        if sum(fails.values())>=25: why='25 failures, stopping'; break
        continue
    j=r.json()
    if j.get('errors') and not j.get('response'):
        fails['api error']=fails.get('api error',0)+1
        if fails['api error']>=5: why='5 API errors, stopping'; print("last API error keys:",list(j['errors']) if isinstance(j['errors'],dict) else 'list',flush=True); break
        continue
    v=rows_of(fid,j.get('response')); total+=len(v); empty+=not v
    if v: execute_values(k,"INSERT INTO af_player_stats VALUES %s ON CONFLICT DO NOTHING",v)
    k.execute("INSERT INTO af_player_stats_done (fixture_id,n) VALUES (%s,%s) ON CONFLICT DO NOTHING",(fid,len(v))); con.commit(); done+=1
    if done%500==0: print(f"  {done} fixtures, {total} rows, remaining {rem}, {time.time()-T0:.0f}s",flush=True)
    time.sleep(0.25)
el=time.time()-T0
print(f"stopped: {why} | calls {calls} | fixtures done {done}, empty {empty} | player rows {total} | failed {fails} | remaining {rem} | {el:.0f}s, {done/max(el,1)*60:.0f} fixtures/min",flush=True)
k.execute("""SELECT f.season,count(*),count(d.fixture_id),count(d.fixture_id) FILTER (WHERE d.n>0) FROM af_fixtures f LEFT JOIN af_player_stats_done d USING (fixture_id) WHERE f.season>=2024 AND f.status='FT' GROUP BY 1 ORDER BY 1""")
print("\n== coverage, season: finished, fetched, with rows"); [print(" ",*r) for r in k.fetchall()]
k.execute("SELECT min(f.kickoff)::date,max(f.kickoff)::date FROM af_player_stats_done d JOIN af_fixtures f USING (fixture_id) WHERE d.n>0"); print("kick-off span loaded:",k.fetchone())
k.execute("SELECT count(*),count(minutes),count(shots),count(goals),count(rating) FROM af_player_stats"); print("rows, and non-null minutes, shots, goals, rating:",k.fetchone())
k.execute("SELECT * FROM af_player_stats WHERE minutes>0 ORDER BY fixture_id DESC,goals DESC NULLS LAST LIMIT 3"); print("first rows:",k.fetchall())
con.close()
print("\n== SURVIVORS\nnot applicable: loader, no P&L")
PY
