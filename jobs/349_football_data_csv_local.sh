#!/bin/bash
# 349: FOOTBALL-DATA.CO.UK into the local Postgres: 20 seasons x 18 divisions of results with corners, shots, shots on
# target, cards and closing bookmaker odds (Pinnacle/B365, over-under, AH). Free, no login. Table fd_matches. Resumable
# (one row per file in fd_files). This is the training set for the corners/cards models and a 20-season results hold-out.
set -o pipefail
python3 - <<'PY'
import sys,io,csv,time,requests,psycopg2,psycopg2.extras,datetime
sys.path.insert(0,'/root/pe-queue/runner'); import creds
DB=creds.pg_local(); assert DB
con=psycopg2.connect(DB); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS fd_matches (div TEXT, season TEXT, date DATE, home TEXT, away TEXT, fthg INT, ftag INT, hthg INT, htag INT,
  hs INT, as_ INT, hst INT, ast INT, hc INT, ac INT, hy INT, ay INT, hr INT, ar INT, b365h NUMERIC, b365d NUMERIC, b365a NUMERIC, psh NUMERIC, psd NUMERIC, psa NUMERIC,
  psch NUMERIC, pscd NUMERIC, psca NUMERIC, b365o25 NUMERIC, b365u25 NUMERIC, p_o25 NUMERIC, p_u25 NUMERIC, ahh NUMERIC, b365ahh NUMERIC, b365aha NUMERIC, raw JSONB, PRIMARY KEY (div,date,home,away));
  CREATE TABLE IF NOT EXISTS fd_files (path TEXT PRIMARY KEY, rows INT, loaded_at TIMESTAMPTZ)""")
DIVS=['E0','E1','E2','E3','EC','SC0','SC1','D1','D2','I1','I2','SP1','SP2','F1','F2','N1','B1','P1','T1','G1']
SEASONS=[f"{y%100:02d}{(y+1)%100:02d}" for y in range(2006,2027)]
def num(x):
    try: return float(x) if x not in ('',None) else None
    except Exception: return None
def inum(x):
    try: return int(float(x)) if x not in ('',None) else None
    except Exception: return None
def dt(x):
    for f in ('%d/%m/%Y','%d/%m/%y'):
        try: return datetime.datetime.strptime(x,f).date()
        except Exception: pass
    return None
cur.execute("SELECT path FROM fd_files"); done={r[0] for r in cur.fetchall()}
t0=time.time(); n_files=0
for s in SEASONS:
    for d in DIVS:
        path=f"{s}/{d}.csv"
        if path in done: continue
        if time.time()-t0>2400: print("time budget; re-run"); sys.exit(75)
        try: r=requests.get(f"https://www.football-data.co.uk/mmz4281/{path}",timeout=60)
        except Exception as e: print(path,"ERR",e); continue
        if r.status_code!=200 or len(r.content)<500: cur.execute("INSERT INTO fd_files VALUES (%s,0,NOW()) ON CONFLICT DO NOTHING",(path,)); continue
        txt=r.content.decode('latin-1'); rows=[]
        for row in csv.DictReader(io.StringIO(txt)):
            g=lambda k: row.get(k)
            if not g('Date') or not g('HomeTeam'): continue
            rows.append((d,s,dt(g('Date')),g('HomeTeam'),g('AwayTeam'),inum(g('FTHG')),inum(g('FTAG')),inum(g('HTHG')),inum(g('HTAG')),
              inum(g('HS')),inum(g('AS')),inum(g('HST')),inum(g('AST')),inum(g('HC')),inum(g('AC')),inum(g('HY')),inum(g('AY')),inum(g('HR')),inum(g('AR')),
              num(g('B365H')),num(g('B365D')),num(g('B365A')),num(g('PSH') or g('PH')),num(g('PSD') or g('PD')),num(g('PSA') or g('PA')),
              num(g('PSCH')),num(g('PSCD')),num(g('PSCA')),num(g('B365>2.5')),num(g('B365<2.5')),num(g('P>2.5')),num(g('P<2.5')),num(g('AHh') or g('AHCh')),num(g('B365AHH')),num(g('B365AHA')),
              psycopg2.extras.Json({k:v for k,v in row.items() if v not in ('',None)})))
        rows=[x for x in rows if x[2] is not None]
        psycopg2.extras.execute_values(cur,"INSERT INTO fd_matches VALUES %s ON CONFLICT DO NOTHING",rows,page_size=500)
        cur.execute("INSERT INTO fd_files VALUES (%s,%s,NOW()) ON CONFLICT (path) DO UPDATE SET rows=EXCLUDED.rows, loaded_at=NOW()",(path,len(rows)))
        n_files+=1; print(f"{path}: {len(rows)} rows",flush=True); time.sleep(0.5)
cur.execute("SELECT count(*), min(date), max(date), count(distinct div) FROM fd_matches"); print("fd_matches:",cur.fetchone())
cur.execute("SELECT div, count(*) FILTER (WHERE hc IS NOT NULL) corners, count(*) FILTER (WHERE psch IS NOT NULL) closing FROM fd_matches GROUP BY 1 ORDER BY 1"); print(cur.fetchall())
PY
