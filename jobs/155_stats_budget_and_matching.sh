#!/bin/bash
# 155: STATS FEED — THE BUDGET IS SPENT BEFORE EUROPE KICKS OFF. ip_stats by hour shows the recorder polling from 00:00 UTC (Americas /
# Asia overnight) and going silent at ~10:00 UTC every day: API-Football's daily quota is gone before any European game we actually
# trade. That is why 0% of late-CS legs and 3% of M1 pushes have stats. Fixes: (1) fixtures?live=all every 2 min not 1; (2) poll ONLY
# fixtures matched to a Betfair market (unmatched never polled); (3) pace the quota across the day: per-cycle cap = remaining /
# hours-to-midnight / cycles-per-hour, doubled 11:00-22:00 UTC; (4) matched markets ordered by Betfair volume so the biggest games
# are polled first; (5) matcher: alias map (utd/united, man/manchester, ...) and a 6-hour market window (markets appear in liq_sample
# only when the recorder picks them up, which is why the same game was matched in one cycle and not the next).
python3 - <<'PY'
p='/root/pe-stats/stats_recorder.py'; s=open(p).read(); n=0
def rep(old,new):
    global s,n
    assert old in s, old[:60]; s=s.replace(old,new,1); n+=1
rep('''def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()''','''ALIAS={'utd':'united','man':'manchester','intl':'international','st':'saint','wolves':'wolverhampton','spurs':'tottenham','psg':'paris','inter':'internazionale','olympique':'','borussia':'','dynamo':'dinamo','dynamo':'dinamo','sporting':'','deportivo':'','atl':'atletico'}
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=' '.join(ALIAS.get(w,w) for w in re.sub(r"[^a-z0-9 ]"," ",s).split())''')
rep('''    cur.execute("SELECT DISTINCT market_id, event_name FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '3 hours'"); mkt_cache=cur.fetchall(); last_mkt=time.time(); return mkt_cache''',
    '''    cur.execute("SELECT market_id, max(event_name), max(total_matched) FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '6 hours' GROUP BY market_id"); mkt_cache=cur.fetchall(); last_mkt=time.time(); return mkt_cache''')
rep('''            mid=None; bs=0
            for m,en in bf_markets():
                if ' v ' not in en: continue
                h2,a2=en.split(' v ',1); sc=sim(home,h2)+sim(away,a2)
                if sc>bs: bs=sc; mid=m
            if bs<1.0: mid=None
            gap=180 if mid else 360
            if fid in last_poll and time.time()-last_poll[fid]<gap: continue
            todo.append((0 if mid else 1,fid,f,mid,minute,home,away))
        todo.sort(key=lambda x: x[0])
        if remaining is not None and remaining<300: todo=[t for t in todo if t[3]]   # budget: matched games only
        for _,fid,f,mid,minute,home,away in todo[:40]:''',
    '''            mid=None; bs=0; b2=0; vol=0
            for m,en,tm in bf_markets():
                if not en or ' v ' not in en: continue
                h2,a2=en.split(' v ',1); sc=sim(home,h2)+sim(away,a2)
                if sc>bs: b2=bs; bs=sc; mid=m; vol=float(tm or 0)
                elif sc>b2: b2=sc
            if bs<0.8 or bs-b2<0.25: mid=None
            if not mid: continue                                   # unmatched games are never polled (budget)
            if fid in last_poll and time.time()-last_poll[fid]<180: continue
            todo.append((-vol,fid,f,mid,minute,home,away))
        todo.sort(key=lambda x: x[0])                              # biggest Betfair markets first
        hr=datetime.datetime.now(datetime.timezone.utc).hour; hours_left=max(1,24-hr)
        cap=int((remaining or 0)/hours_left/30); cap=max(2,cap*(2 if 11<=hr<=22 else 1)); cap=min(cap,40)
        for _,fid,f,mid,minute,home,away in todo[:cap]:''')
rep("        time.sleep(60)\n    except Exception as ex:","        time.sleep(120)\n    except Exception as ex:")
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile /root/pe-stats/stats_recorder.py || exit 1
grep -n "^import\|^from" /root/pe-stats/stats_recorder.py | head -3
python3 - <<'PY'
import re,unicodedata
src=open('/root/pe-stats/stats_recorder.py').read()
start=src.index('ALIAS='); end=src.index('def sim(')+src[src.index('def sim('):].index('\n')+1
ns={'re':re,'unicodedata':unicodedata}; exec(src[start:end],ns); sim=ns['sim']
tests=[("Atlanta United FC","Chicago Fire","Atlanta Utd v Chicago Fire"),("Kashima","Kashiwa Reysol","Kashima Antlers v Kashiwa Reysol"),("Urawa","V-varen Nagasaki","Urawa Red Diamonds v V-Varen Nagasaki"),("Tigre","Atletico Tucuman","Tigre v Atl Tucuman"),("Manchester United","Brighton","Man Utd v Brighton")]
for h,a,en in tests:
    h2,a2=en.split(' v ',1); print(f"{h} v {a}  ~  {en}: {sim(h,h2)+sim(a,a2):.2f}")
print("wrong pair:",round(sim("Tigre","Arsenal")+sim("Atletico Tucuman","Everton"),2))
PY
pkill -f stats_recorder.py; sleep 3; /root/pe-stats/keepalive.sh 2>/dev/null; sleep 20; pgrep -af stats_recorder.py | head -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM stats_heartbeat"); print("stats heartbeat (live, matched, remaining):",c.fetchall())
PY
