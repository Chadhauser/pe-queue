#!/bin/bash
# 618 (Mon 16 Nov 2026, 16:45). What the fair-price model is missing, and what we already hold to add it. Reads every candidate feature source
# and tests how many Betfair football markets each one joins to (by team names + date), so model v3 can use them:
#  bookmaker / Pinnacle odds and closing odds (football-data style tables), results/ratings/form, xG, API-Football fixtures/lineups/stats,
#  FTS data, goal timeline, racing and tennis extras. Writes reports/feature_sources.md.
set -o pipefail
R=/root/pe-queue/reports/feature_sources.md
python3 - > $R 2>&1 <<'PY'
import sys, psycopg2, re, datetime
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='900s'")
def q(s,a=()):
    try: c.execute(s,a); return c.fetchall()
    except Exception as e: c.connection.rollback(); return [("ERR",str(e)[:120])]
print(f"# Feature sources for the fair-price model — {datetime.datetime.utcnow():%F %H:%M} UTC\n")
c.execute("""SELECT t.table_name, pg_total_relation_size(quote_ident(t.table_name)) FROM information_schema.tables t WHERE t.table_schema='public' ORDER BY 2 DESC""")
tabs=c.fetchall()
pat=re.compile(r'fd_|match|fixture|result|elo|rating|xg|understat|fts|lineup|stat|odds|pinn|bookie|af_|goal|team|player|race|runner|horse|tennis|form|bsp',re.I)
for t,sz in tabs:
    if not pat.search(t) or t.startswith(('bf_hist_other','stream_ticks','liq_sample','ip_tape','xx_tape')): continue
    cols=[r[0] for r in q("select column_name from information_schema.columns where table_name=%s order by ordinal_position",(t,))]
    n=q(f"select count(*) from {t}")[0][0]
    print(f"- **{t}** ({sz/1e6:.0f} MB, {n} rows): {', '.join(cols[:40])}{' ...' if len(cols)>40 else ''}")
print("\n## Odds columns found (bookmaker / Pinnacle / closing)\n")
for t,sz in tabs:
    cols=[r[0] for r in q("select column_name from information_schema.columns where table_name=%s",(t,))]
    oc=[x for x in cols if re.match(r'^(ps|psc|b365|bw|iw|ws|vc|max|avg|bb|p)(c)?(h|d|a|>2\.5|<2\.5)',x,re.I) or 'pinn' in x.lower() or 'closing' in x.lower()]
    if oc: print(f"- {t}: {oc[:25]} ; dates {q(f'select min(date), max(date) from {t}') if 'date' in cols else '?'}")
print("\n## Join test: Betfair MATCH_ODDS markets (last 2 years) to fd_matches by date + team names\n")
c.execute("SELECT column_name FROM information_schema.columns WHERE table_name='fd_matches'"); fc=[r[0] for r in c.fetchall()]
print("fd_matches columns:", fc[:60])
ht=next((x for x in fc if x.lower() in ('hometeam','home_team','home')),None); at=next((x for x in fc if x.lower() in ('awayteam','away_team','away')),None); dt=next((x for x in fc if x.lower() in ('date','match_date','kickoff')),None)
if ht and at and dt:
    def norm(s): return re.sub(r'[^a-z]','',re.sub(r'\b(fc|afc|cf|sc|ac|utd|united|city|town|the)\b','',(s or '').lower()))
    c.execute(f"SELECT {dt}::date, {ht}, {at} FROM fd_matches WHERE {dt}::date>='2024-07-01'"); F={}
    for d,h,a in c.fetchall(): F[(d,norm(h),norm(a))]=1
    c.execute("SELECT DISTINCT market_id, market_time::date, event_name FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2024-07-01' LIMIT 60000")
    rows=c.fetchall(); hit=0
    for mid,d,ev in rows:
        if ' v ' not in (ev or ''): continue
        h,a=ev.split(' v ',1)
        if (d,norm(h),norm(a)) in F: hit+=1
    print(f"Betfair match-odds markets since Jul 2024 sampled: {len(rows)}; joined to fd_matches by date + normalised names: {hit}")
else: print("fd_matches: could not find home/away/date columns")
print("\n## Same-event cross-market coverage (for coherence features)\n")
print(q("""SELECT count(*) FROM (SELECT event_id FROM bf_hist_result WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25','CORRECT_SCORE','BOTH_TEAMS_TO_SCORE')
           GROUP BY event_id HAVING count(DISTINCT market_type)=4) x"""))
print("\n## Project data files on disk (racing/tennis/FTS)\n")
import glob, os
for pth in ['/root/pe-data','/root/pe-sports/data','/root/pe-brain/data','/root/data','/root/pe-hist']:
    if os.path.isdir(pth): print(pth, sorted(os.listdir(pth))[:30])
PY
cd /root/pe-queue && git add reports/feature_sources.md && git commit -qm "618: feature sources reading" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "618 done"
