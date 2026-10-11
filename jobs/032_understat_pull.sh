#!/bin/bash
# 032: fill the (existing, empty) understat_matches / understat_shots tables: every shot with minute and xG, top-5 leagues,
# seasons 2024 and 2025 (= 2024/25, 2025/26). ~3,600 matches, one request each, 1s apart (~1 hour). Resumable: skips matches
# already loaded. Gives a minute-by-minute xG timeline for the SAME matches we hold Betfair minute prices for -> job 033.
cd /root/pe-scan && cat > understat_pull.py <<'PYFILE'
import re, json, sys, time, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
H={"User-Agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36","Accept-Language":"en-GB,en;q=0.9"}
def jsvar(html,name):
    m=re.search(name+r"\s*=\s*JSON\.parse\('((?:\\.|[^'])*)'\)",html)
    if not m: return None
    s=m.group(1).encode('utf-8').decode('unicode_escape')
    return json.loads(s)
cur.execute("SELECT understat_id FROM understat_matches"); have={r[0] for r in cur.fetchall()}
cur.execute("SELECT DISTINCT understat_id FROM understat_shots"); have_shots={r[0] for r in cur.fetchall()}
print("already loaded: matches",len(have),"with shots",len(have_shots),flush=True)
todo=[]
for lg in ('EPL','La_liga','Bundesliga','Serie_A','Ligue_1'):
    for season in (2024,2025):
        for attempt in range(3):
            try:
                r=requests.get(f"https://understat.com/league/{lg}/{season}",headers=H,timeout=30); r.raise_for_status(); break
            except Exception as e:
                print("league fetch retry",lg,season,repr(e)[:80],flush=True); time.sleep(10)
        else: continue
        dates=jsvar(r.text,'datesData') or []
        n=0
        for m in dates:
            if not m.get('isResult'): continue
            uid=str(m['id'])
            if uid not in have:
                cur.execute("""INSERT INTO understat_matches (understat_id,league,season,match_date,home_team,away_team,home_goals,away_goals,home_xg,away_xg,forecast_w,forecast_d,forecast_l,collected_at)
                               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW()) ON CONFLICT DO NOTHING""",
                            (uid,lg,str(season),m['datetime'][:10],m['h']['title'],m['a']['title'],int(m['goals']['h']),int(m['goals']['a']),float(m['xG']['h']),float(m['xG']['a']),
                             float((m.get('forecast') or {}).get('w') or 0),float((m.get('forecast') or {}).get('d') or 0),float((m.get('forecast') or {}).get('l') or 0)))
                have.add(uid)
            if uid not in have_shots: todo.append(uid)
            n+=1
        print(lg,season,"results",n,flush=True); time.sleep(1.5)
print("matches needing shots:",len(todo),flush=True)
done=0
for uid in todo:
    try:
        r=requests.get(f"https://understat.com/match/{uid}",headers=H,timeout=30)
        if r.status_code!=200: print("match",uid,"HTTP",r.status_code,flush=True); time.sleep(5); continue
        sd=jsvar(r.text,'shotsData') or {}
        rows=[]
        for side in ('h','a'):
            for s in sd.get(side,[]):
                rows.append((uid,str(s['id']),int(s['minute']),'H' if side=='h' else 'A',s.get('player'),float(s['xG']),s.get('result'),s.get('situation'),s.get('shotType')))
        if rows:
            psycopg2.extras.execute_values(cur,"INSERT INTO understat_shots (understat_id,shot_id,minute,team_side,player,xg,result,situation,shot_type) VALUES %s ON CONFLICT DO NOTHING",rows)
        done+=1
        if done%100==0: print("shots loaded for",done,"matches",flush=True)
        time.sleep(1.0)
    except Exception as e:
        print("match",uid,"error",repr(e)[:100],flush=True); time.sleep(5)
cur.execute("SELECT count(*), count(DISTINCT understat_id) FROM understat_shots"); print("understat_shots total rows, matches:",cur.fetchone())
cur.execute("SELECT league, season, count(*) FROM understat_matches GROUP BY 1,2 ORDER BY 1,2"); print(cur.fetchall())
PYFILE
python3 understat_pull.py
