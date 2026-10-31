#!/bin/bash
# 295 (re-run of 291 with two fixes — "AS minute" alias, pipefail so exit codes survive the grep): THE 29-LEAGUE HONEST SWEEP. (1) af_shots: API-Football goal events shaped like understat_shots (minute, side, result;
# xG blank — no shot-level xG in this feed); (2) af_price_map: af_fixtures joined to bf_hist_price games by date ±1 and team-name
# token similarity (same method as 168), match rate per league printed; (3) the stats sweep runs unchanged against those two
# tables into v4_af_results / v4_af_minute; (4) report: survivors by family/league group, LEVEL00 / LEAD1 / G2LATE / S13 / S14
# and the bias bands, with n, mean per £10, t, both halves. xG families are skipped (xg=0) — they stay on the Understat 5 leagues.
set -e -o pipefail
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,psycopg2,psycopg2.extras,pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
# (1) af_shots
cur.execute("""DROP TABLE IF EXISTS af_shots; CREATE TABLE af_shots AS
SELECT ('af'||e.fixture_id)::text understat_id, LEAST(GREATEST(coalesce(e.minute,0)-1,0),94)::int AS minute,
       CASE WHEN (e.is_home AND e.detail<>'Own Goal') OR ((NOT e.is_home) AND e.detail='Own Goal') THEN 'h' ELSE 'a' END team_side,
       0.0::float xg, CASE WHEN e.detail='Own Goal' THEN 'OwnGoal' ELSE 'Goal' END result
FROM af_events e WHERE e.type='Goal' AND e.detail IN ('Normal Goal','Penalty','Own Goal')""")
# understat minutes are 0-based and the sweep adds +1; API-Football 'elapsed' is 1-based -> minute-1 above keeps the same convention
cur.execute("SELECT count(*), count(DISTINCT understat_id) FROM af_shots"); print("af_shots goals, games with goals:",cur.fetchone())
# (2) map
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().replace('_',' ')
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|1899|1846|1904|04|05|96|98|women|w|u21|u23|ii|b)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
A=pd.read_sql("SELECT fixture_id, league, kickoff::date d, home, away FROM af_fixtures WHERE status IN ('FT','AET','PEN')",con)
B=pd.read_sql("SELECT event_id, event_name, country, min(m)::date d FROM bf_hist_price WHERE mkt='MO' GROUP BY 1,2,3",con)
B=B[B.event_name.str.contains(' v ')].copy(); B['h']=B.event_name.str.split(' v ').str[0]; B['a']=B.event_name.str.split(' v ').str[1]
B['d']=pd.to_datetime(B.d); A['d']=pd.to_datetime(A.d)
print("af fixtures",len(A),"| betfair games",len(B))
Bd={}
for r in B.itertuples(): Bd.setdefault(r.d.normalize(),[]).append(r)
rows=[]
for u in A.itertuples():
    cand=[]
    for dd in (-1,0,1): cand+=Bd.get((u.d+pd.Timedelta(days=dd)).normalize(),[])
    best=None; bs=0; b2=0
    for c in cand:
        sc=sim(u.home,c.h)+sim(u.away,c.a)
        if sc>bs: b2=bs; bs=sc; best=c.event_id
        elif sc>b2: b2=sc
    if best and bs>=1.0 and bs-b2>=0.3: rows.append(('af'+str(u.fixture_id),best,round(bs,2),u.league))
cur.execute("DROP TABLE IF EXISTS af_price_map; CREATE TABLE af_price_map (understat_id TEXT PRIMARY KEY, event_id TEXT, score NUMERIC, league TEXT)")
psycopg2.extras.execute_values(cur,"INSERT INTO af_price_map VALUES %s",rows)
m=pd.DataFrame(rows,columns=['u','e','s','league']); cov=m.groupby('league').size().to_frame('matched').join(A.groupby('league').size().to_frame('fixtures')); cov['pct']=(100*cov.matched/cov.fixtures).round(0)
print("matched games:",len(m)); print(cov.sort_values('matched',ascending=False).to_string())
PY
# (3) sweep copy on the af tables
sed -e 's/xg_price_map/af_price_map/g' -e 's/understat_shots/af_shots/g' -e 's/v4_stats_results/v4_af_results/g' -e 's/v4_stats_minute/v4_af_minute/g' /root/pe-factory/v4/stats_sweep.py > /root/pe-factory/v4/stats_sweep_af.py
python3 -m py_compile /root/pe-factory/v4/stats_sweep_af.py
cd /root/pe-factory/v4 && timeout 3300 python3 stats_sweep_af.py 2>&1 | grep -v -E "UserWarning|pd.read_sql| processed" | tail -15
# (4) report
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT fam, sel, dir, exit, band, n, mean, t, h1, h2 FROM v4_af_results WHERE run_date=(SELECT max(run_date) FROM v4_af_results) AND fam NOT LIKE '%%xg%%' AND n>=200 ORDER BY t DESC",c)
print("cells n>=200:",len(d)); print("\n== top 25 by t"); print(d.head(25).to_string(index=False))
print("\n== bottom 10 by t"); print(d.tail(10).to_string(index=False))
s=d[(d.t>=3.5)&(d.h1>0)&(d.h2>0)]; print("\n== SURVIVORS (t>=3.5, both halves >0):",len(s)); print(s.to_string(index=False))
PY
