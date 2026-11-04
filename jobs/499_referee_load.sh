#!/bin/bash
set -o pipefail
# 499_referee_load (Finder 2026-11-04, queue item 63): add af_fixtures.referee. af_fixtures stores no raw response, so re-pull /fixtures for the 29 leagues of jobs/348, seasons 2024-2026: one call per league-season, 87 at most. Only the referee column is written; a NULL from the API never overwrites a stored name. Stops at under 150 API calls remaining. Local Postgres only. Never prints the key. Re-runnable.
python3 - "$@" <<'PY' 2>&1
import sys,time,requests,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
LEAGUES=[39,40,41,42,140,141,135,136,78,79,61,62,88,94,144,179,203,197,218,207,103,113,119,71,128,253,98,2,3]; SEASONS=[2026,2025,2024]
BASE="https://v3.football.api-sports.io"; FLOOR=150
def clean(x):
    x=(x or '').strip()
    return x or None
def rows_of(res):
    """API response list -> (referee, fixture_id) for fixtures that name one."""
    out=[]
    for f in res or []:
        r=clean((f.get('fixture') or {}).get('referee')); i=(f.get('fixture') or {}).get('id')
        if r and i: out.append((r,i))
    return out
def low(rem): return rem is not None and rem<FLOOR
# known answers
assert clean(None) is None and clean('  ') is None and clean(' M. Oliver, England ')=='M. Oliver, England'
assert rows_of([{'fixture':{'id':1,'referee':'A'}},{'fixture':{'id':2,'referee':None}},{'fixture':{'id':3,'referee':' '}},{'fixture':{'referee':'B'}},{}])==[('A',1)] and rows_of(None)==[]
assert low(149) and not low(150) and not low(None)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
H={"x-apisports-key":creds.apifootball()}
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; k=con.cursor()
k.execute("SET lock_timeout='30s'; SET statement_timeout='600s'"); k.execute("ALTER TABLE af_fixtures ADD COLUMN IF NOT EXISTS referee TEXT")
calls=0; rem=None; upd=0; fails=[]; T0=time.time(); stop=False
for L in LEAGUES:
    for S in SEASONS:
        if stop or time.time()-T0>1500: stop=True; break
        try:
            r=requests.get(BASE+"/fixtures",params={"league":L,"season":S},headers=H,timeout=30); calls+=1
        except requests.RequestException as e:
            fails.append((L,S,type(e).__name__)); continue
        try: rem=int(r.headers.get('x-ratelimit-requests-remaining'))
        except (TypeError,ValueError): pass
        if r.status_code!=200: fails.append((L,S,r.status_code)); time.sleep(5 if r.status_code==429 else 1); continue
        j=r.json()
        if j.get('errors') and not j.get('response'): fails.append((L,S,'api error')); continue
        v=rows_of(j.get('response'))
        if v: k.executemany("UPDATE af_fixtures SET referee=%s WHERE fixture_id=%s",v); upd+=len(v)
        print(f"league {L} season {S}: fixtures {len(j.get('response') or [])}, named {len(v)} | remaining {rem}",flush=True)
        if low(rem): print("WAITING: API budget floor reached, stopping",flush=True); stop=True; break
        time.sleep(0.25)
print(f"calls {calls} | referee rows sent {upd} | failed {fails} | remaining {rem} | {time.time()-T0:.0f}s",flush=True)
k.execute("""SELECT season,count(*) FILTER (WHERE status='FT'),count(*) FILTER (WHERE status='FT' AND referee IS NOT NULL) FROM af_fixtures WHERE season>=2024 GROUP BY 1 ORDER BY 1""")
print("\n== fill rate, finished fixtures");
for s,a,b in k.fetchall(): print(f"  {s}: {b} of {a} = {b/max(a,1):.3f}")
k.execute("""SELECT league,count(*),count(referee) FROM af_fixtures WHERE season>=2024 AND status='FT' GROUP BY 1 ORDER BY count(referee)::float/count(*) LIMIT 8""")
print("lowest leagues:",[(a,b,c) for a,b,c in k.fetchall()])
k.execute("SELECT count(DISTINCT referee) FROM af_fixtures"); print("distinct referee strings:",k.fetchone()[0])
k.execute("SELECT referee,count(*) FROM af_fixtures WHERE referee IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 4"); print("first rows:",k.fetchall())
con.close()
PY
