#!/bin/bash
# 137: (a) liq_recorder never stored CORRECT_SCORE rows (133 saw only BTTS/MO/OU15/OU25/OU35): the catalogue filter got the code
#     (109) but the market-type -> label mapping drops anything unmapped. Add CORRECT_SCORE -> 'CS' wherever the mapping lives.
#     (b) SofaScore returns 403 from this server (135). Stats recorder rewritten on API-Football: /fixtures?live=all (score, minute)
#     + /fixtures/statistics?fixture=id (shots, SoT, possession, xG, corners) every 3 min per live game, matched games first,
#     daily budget guard from the x-ratelimit headers. Same ip_stats / s6_paper tables so 136 keeps working unchanged.
echo "== (a) liq_recorder mapping"; grep -n -E "MATCH_ODDS|OU15|OVER_UNDER_15|BOTH_TEAMS|CORRECT" /root/pe-liq/liq_recorder.py | head -20
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read(); orig=s
if "'CORRECT_SCORE':'CS'" in s or '"CORRECT_SCORE":"CS"' in s: print("mapping already has CS")
else:
    # add to any dict that maps MATCH_ODDS -> MO
    s2=re.sub(r"(['\"]MATCH_ODDS['\"]\s*:\s*['\"]MO['\"])", r"\1, 'CORRECT_SCORE':'CS'", s, count=1)
    if s2!=s: s=s2; print("added CORRECT_SCORE:'CS' to the market map")
    else:
        # maybe a function/if-chain: show it
        print("no dict mapping found; lines with 'MO':"); print("\n".join(l for l in s.splitlines() if "'MO'" in l or '"MO"' in l))
    # make sure the catalogue filter includes it
    if 'CORRECT_SCORE' not in s: s=re.sub(r"(marketTypeCodes\"\s*:\s*\[)([^\]]*)\]", lambda m: m.group(1)+m.group(2)+(",\"CORRECT_SCORE\"" if m.group(2).strip() else "\"CORRECT_SCORE\"")+"]", s, count=1); print("catalogue filter: CORRECT_SCORE added")
    if s!=orig: open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py && pkill -f liq_recorder.py; echo "liq recorder restarts via keepalive"
grep -n -E "CORRECT_SCORE|'CS'" /root/pe-liq/liq_recorder.py | head
echo "== (b) stats recorder on API-Football"
cat > /root/pe-stats/stats_recorder.py <<'PYFILE'
import os, re, sys, time, datetime, unicodedata, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
AF=None
for p in ('/root/pe-logger/.env','/root/pe-bot/.env'):
    if os.path.exists(p):
        m=re.search(r'^(?:API_?FOOTBALL_KEY|APIFOOTBALL_KEY|RAPIDAPI_KEY)=(.+)$',open(p).read(),re.M)
        if m: AF=m.group(1).strip().strip('"\''); break
if not AF: sys.exit("no API-Football key")
AFH={"x-apisports-key":AF}; BASE="https://v3.football.api-sports.io"
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS ip_stats (ts TIMESTAMPTZ DEFAULT now(), sofa_id BIGINT, event_name TEXT, league TEXT, market_id TEXT, minute INT, hs INT, "as" INT,
  h_xg NUMERIC, a_xg NUMERIC, h_shots INT, a_shots INT, h_sot INT, a_sot INT, h_poss NUMERIC, a_poss NUMERIC, h_dang INT, a_dang INT, h_corn INT, a_corn INT);
CREATE INDEX IF NOT EXISTS ip_stats_ev ON ip_stats (sofa_id, ts);
CREATE TABLE IF NOT EXISTS s6_paper (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now(), sofa_id BIGINT, market_id TEXT, event_name TEXT, league TEXT, entry_min INT, dominant TEXT,
  h_xg NUMERIC, a_xg NUMERIC, h_sot INT, a_sot INT, draw_lay NUMERIC, exit_min INT, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC, UNIQUE (sofa_id));
CREATE TABLE IF NOT EXISTS stats_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, live INT, matched INT, http_status INT)""")
remaining=None
def get(path,params):
    global remaining
    r=requests.get(BASE+path,params=params,headers=AFH,timeout=20)
    try: remaining=int(r.headers.get('x-ratelimit-requests-remaining') or remaining or 0)
    except Exception: pass
    return r.status_code,(r.json() if r.status_code==200 else None)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|nk|sk|bk|if|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|u21|u19|u23|women|ii)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
def parse(stat_resp):
    out={}
    for team in stat_resp:
        side='h' if team is stat_resp[0] else 'a'
        d={s['type'].lower():s['value'] for s in team.get('statistics',[])}
        def f(k):
            v=d.get(k);
            if v is None: return None
            try: return float(str(v).replace('%',''))
            except Exception: return None
        out[side]=dict(xg=f('expected_goals'),shots=f('total shots') or 0,sot=f('shots on goal') or 0,poss=f('ball possession'),corn=f('corner kicks') or 0)
    return out
last_poll={}; mkt_cache=[]; last_mkt=0; open_tr={}
def bf_markets():
    global mkt_cache,last_mkt
    if time.time()-last_mkt<120: return mkt_cache
    cur.execute("SELECT DISTINCT market_id, event_name FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '3 hours'"); mkt_cache=cur.fetchall(); last_mkt=time.time(); return mkt_cache
def draw_px(mid,col='lay_px'):
    cur.execute(f"SELECT {col} FROM liq_sample WHERE market_id=%s AND mkt='MO' AND upper(sel) IN ('THE DRAW','DRAW') AND {col} IS NOT NULL ORDER BY ts DESC LIMIT 1",(mid,)); r=cur.fetchone(); return float(r[0]) if r else None
while True:
    try:
        st,data=get("/fixtures",{"live":"all"}); live=(data or {}).get('response',[]); matched=0
        # match each live fixture to a Betfair market; poll matched ones every 3 min, others every 6 min; budget guard
        todo=[]
        for f in live:
            fid=f['fixture']['id']; minute=(f['fixture'].get('status') or {}).get('elapsed')
            if minute is None: continue
            home=f['teams']['home']['name']; away=f['teams']['away']['name']
            mid=None; bs=0
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
        for _,fid,f,mid,minute,home,away in todo[:40]:
            s2,sd=get("/fixtures/statistics",{"fixture":fid}); last_poll[fid]=time.time()
            if not sd or len(sd.get('response',[]))<2: continue
            s=parse(sd['response']); h,a=s['h'],s['a']; ev=f"{home} v {away}"; lg=f['league']['name']
            hs=f['goals']['home'] or 0; as_=f['goals']['away'] or 0
            if mid: matched+=1
            cur.execute('INSERT INTO ip_stats (sofa_id,event_name,league,market_id,minute,hs,"as",h_xg,a_xg,h_shots,a_shots,h_sot,a_sot,h_poss,a_poss,h_dang,a_dang,h_corn,a_corn) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
                        (fid,ev,lg,mid,int(minute),hs,as_,h['xg'],a['xg'],int(h['shots']),int(a['shots']),int(h['sot']),int(a['sot']),h['poss'],a['poss'],0,0,int(h['corn']),int(a['corn'])))
            if fid in open_tr:
                t=open_tr[fid]
                if hs+as_>0 or minute>=65:
                    px=draw_px(mid,'lay_px' if hs+as_>0 else 'back_px') if mid else None
                    if hs+as_>0 and mid:
                        cur.execute("SELECT lay_px FROM liq_goal_depth WHERE market_id=%s AND mkt='MO' AND upper(sel) IN ('THE DRAW','DRAW') AND offset_s=60 AND goal_ts>%s ORDER BY goal_ts LIMIT 1",(mid,t['ts'])); r=cur.fetchone()
                        if r and r[0]: px=float(r[0])
                    if px:
                        pnl=(1-t['px']/px)*10; pnl=pnl*0.98 if pnl>0 else pnl
                        cur.execute("UPDATE s6_paper SET exit_min=%s, exit_px=%s, exit_reason=%s, pnl_per_10=%s WHERE sofa_id=%s",(int(minute),px,'GOAL' if hs+as_>0 else 'STOP65',round(pnl,2),fid))
                        print(f"S6 EXIT {ev} {t['px']}->{px} {pnl:+.2f}",flush=True); del open_tr[fid]
                continue
            if mid and 20<=minute<=35 and hs==0 and as_==0 and h['xg'] is not None and a['xg'] is not None:
                dom=None
                if h['xg']-a['xg']>=0.6 and h['shots']>=4 and h['sot']>=2: dom='HOME'
                elif a['xg']-h['xg']>=0.6 and a['shots']>=4 and a['sot']>=2: dom='AWAY'
                if dom:
                    dl=draw_px(mid,'lay_px')
                    if dl and 3.0<=dl<=4.5:
                        cur.execute("INSERT INTO s6_paper (sofa_id,market_id,event_name,league,entry_min,dominant,h_xg,a_xg,h_sot,a_sot,draw_lay) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(fid,mid,ev,lg,int(minute),dom,h['xg'],a['xg'],int(h['sot']),int(a['sot']),dl))
                        if cur.rowcount: open_tr[fid]={'px':dl,'ts':datetime.datetime.now(datetime.timezone.utc)}; print(f"S6 ENTRY {ev} {minute}' {dom} xG {h['xg']}-{a['xg']} lay draw {dl}",flush=True)
            time.sleep(0.3)
        cur.execute("INSERT INTO stats_heartbeat VALUES (1,now(),%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), live=EXCLUDED.live, matched=EXCLUDED.matched, http_status=EXCLUDED.http_status",(len(live),matched,remaining if remaining is not None else st))
        time.sleep(60)
    except Exception as ex:
        print("loop",repr(ex)[:200],flush=True); time.sleep(30)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-stats/stats_recorder.py || exit 1
pkill -f stats_recorder.py; sleep 100; pgrep -af stats_recorder.py; tail -5 /root/pe-stats/stats.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM stats_heartbeat"); print("heartbeat (live, matched, api calls remaining):",c.fetchall())
c.execute("SELECT count(*), count(DISTINCT sofa_id), count(*) FILTER (WHERE market_id IS NOT NULL), count(*) FILTER (WHERE h_xg IS NOT NULL) FROM ip_stats"); print("ip_stats rows, games, matched rows, rows with xG:",c.fetchone())
PY
